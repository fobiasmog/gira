import { defineStore } from "pinia"
import { computed, markRaw, ref, shallowRef } from "vue"
import type { Participant, RemoteParticipant, Room, SimulationScenario, Track } from "livekit-client"
import { ApiError } from "../api/client.ts"
import { callApi } from "../api/call.ts"
import { projectsApi } from "../api/projects.ts"
import type { Id, UserCard } from "../api/types.ts"
import {
  deviceProblemKey, disconnectMessageKey, nextView, orderParticipants, parseMediaPreferences,
  type CallView, type CallViewAction, type MediaPreferences,
} from "../composables/callState.ts"
import { readStored, writeStored } from "../composables/storage.ts"
import { t, type MessageKey } from "../i18n/index.ts"
import { useUiStore } from "./ui.ts"

export type CallStatus = "idle" | "connecting" | "connected" | "reconnecting"
export type DeviceKind = "audioinput" | "videoinput"

// What a tile shows. Tracks are LiveKit class instances, kept out of Vue's
// reactivity with markRaw (its proxies break their private fields).
export interface CallParticipant {
  identity: string
  name: string
  avatarUrl: string | null
  local: boolean
  joinedAt: number
  speaking: boolean
  micOn: boolean
  videoTrack: Track | null
}

export interface RemoteAudio {
  sid: string
  track: Track
}

export interface DeviceOption {
  deviceId: string
  label: string
}

const MEDIA_KEY = "goalner.callMedia"

type LiveKit = typeof import("livekit-client")

// The call lives here for the whole page, whatever the route (team-call
// design.md, Decision 7). livekit-client is loaded on the first join only.
let lk: LiveKit | null = null
let room: Room | null = null
// Bumped by every join and leave, so a join that was overtaken gives up.
let attempt = 0

// Test builds only: system tests interrupt the connection with LiveKit's own
// simulation, as a network drop would. (DevTools' offline mode leaves the
// signalling WebSocket open.)
if (import.meta.env.MODE === "test") {
  Object.assign(window, { simulateCallScenario: (scenario: SimulationScenario, arg?: number) => room?.simulateScenario(scenario, arg) })
}

function readPreferences(): MediaPreferences {
  return parseMediaPreferences(readStored(MEDIA_KEY))
}

function savePreferences(changes: Partial<MediaPreferences>) {
  writeStored(MEDIA_KEY, JSON.stringify({ ...readPreferences(), ...changes }))
}

export const useCallStore = defineStore("call", () => {
  const ui = useUiStore()

  const status = ref<CallStatus>("idle")
  const projectId = ref<Id | null>(null)
  const projectTitle = ref("")
  const view = ref<CallView>("expanded")
  // Replaced as a whole on every change, so shallow.
  const participants = shallowRef<CallParticipant[]>([])
  const remoteAudio = shallowRef<RemoteAudio[]>([])
  const micOn = ref(false)
  const camOn = ref(false)
  const micProblem = ref<MessageKey | null>(null)
  const camProblem = ref<MessageKey | null>(null)
  const audioBlocked = ref(false)
  const devices = ref<Record<DeviceKind, DeviceOption[]>>({ audioinput: [], videoinput: [] })
  const activeDevices = ref<Record<DeviceKind, string | null>>({ audioinput: null, videoinput: null })

  const active = computed(() => status.value !== "idle")
  const notices = computed(() => [micProblem.value, camProblem.value].filter((key) => key !== null).map((key) => t(key)))

  // Member cards give tiles their avatar; a participant who joined after
  // they were loaded makes them load again, once per unknown identity.
  let members = new Map<string, UserCard>()
  let reloadedFor = new Set<string>()

  function inCallOf(id: Id): boolean {
    return active.value && projectId.value === id
  }

  async function loadMembers(id: Id) {
    try {
      const cards = await projectsApi.members(id)
      if (projectId.value === id) members = new Map(cards.map((card) => [String(card.id), card]))
    } catch {
      // Tiles show LiveKit's name and initials instead.
    }
  }

  function nameOf(participant: Participant): string {
    return members.get(participant.identity)?.name ?? (participant.name || participant.identity)
  }

  function viewOf(participant: Participant): CallParticipant {
    const camera = participant.getTrackPublication(lk!.Track.Source.Camera)
    const video = camera && !camera.isMuted && camera.track ? markRaw(camera.track) : null
    return {
      identity: participant.identity,
      name: nameOf(participant),
      avatarUrl: members.get(participant.identity)?.avatar_url ?? null,
      local: participant.isLocal,
      joinedAt: participant.joinedAt?.getTime() ?? 0,
      speaking: participant.isSpeaking,
      micOn: participant.isMicrophoneEnabled,
      videoTrack: video,
    }
  }

  // Rebuilds the plain view models from the room after any change in it.
  function sync() {
    if (!room || !lk) return
    const remotes = [...room.remoteParticipants.values()]
    participants.value = orderParticipants([room.localParticipant, ...remotes].map(viewOf))
    remoteAudio.value = remotes.flatMap((participant) => {
      const microphone = participant.getTrackPublication(lk!.Track.Source.Microphone)
      return microphone?.track && microphone.trackSid ? [{ sid: microphone.trackSid, track: markRaw(microphone.track) }] : []
    })
    micOn.value = room.localParticipant.isMicrophoneEnabled
    camOn.value = room.localParticipant.isCameraEnabled
    activeDevices.value = { audioinput: room.getActiveDevice("audioinput") ?? null, videoinput: room.getActiveDevice("videoinput") ?? null }
    audioBlocked.value = !room.canPlaybackAudio

    const unknown = remotes.find((participant) => !members.has(participant.identity) && !reloadedFor.has(participant.identity))
    if (unknown && projectId.value !== null) {
      reloadedFor.add(unknown.identity)
      void loadMembers(projectId.value).then(sync)
    }
  }

  function reset() {
    room = null
    status.value = "idle"
    projectId.value = null
    projectTitle.value = ""
    participants.value = []
    remoteAudio.value = []
    micOn.value = false
    camOn.value = false
    micProblem.value = null
    camProblem.value = null
    audioBlocked.value = false
    members = new Map()
    reloadedFor = new Set()
  }

  function listen(target: Room, livekit: LiveKit) {
    const { RoomEvent, ConnectionState, DisconnectReason } = livekit
    const current = () => room === target
    const update = () => { if (current()) sync() }

    for (const event of [
      RoomEvent.TrackSubscribed, RoomEvent.TrackUnsubscribed, RoomEvent.TrackMuted, RoomEvent.TrackUnmuted,
      RoomEvent.TrackPublished, RoomEvent.TrackUnpublished, RoomEvent.LocalTrackPublished, RoomEvent.LocalTrackUnpublished,
      RoomEvent.ActiveSpeakersChanged, RoomEvent.ParticipantNameChanged, RoomEvent.AudioPlaybackStatusChanged,
      RoomEvent.ActiveDeviceChanged,
    ] as const) target.on(event, update)

    target.on(RoomEvent.ParticipantConnected, (participant: RemoteParticipant) => {
      if (!current()) return
      sync()
      void ui.announce(t("call.joined", { name: nameOf(participant) }))
    })
    target.on(RoomEvent.ParticipantDisconnected, (participant: RemoteParticipant) => {
      if (!current()) return
      sync()
      void ui.announce(t("call.left", { name: nameOf(participant) }))
    })
    target.on(RoomEvent.ConnectionStateChanged, (state) => {
      if (!current()) return
      if (state === ConnectionState.Reconnecting || state === ConnectionState.SignalReconnecting) status.value = "reconnecting"
      else if (state === ConnectionState.Connected) status.value = "connected"
    })
    target.on(RoomEvent.MediaDevicesChanged, () => { if (current()) void refreshDevices() })
    target.on(RoomEvent.Disconnected, (reason) => {
      if (!current()) return
      attempt++
      reset()
      const key = disconnectMessageKey(reason === undefined ? undefined : DisconnectReason[reason])
      if (key) ui.toast(t(key), key === "call.ended.elsewhere" ? "info" : "error")
    })
  }

  // Turns a device on or off. When the browser refuses it, it stays off and
  // the problem is shown; the call goes on without it.
  async function enable(device: "mic" | "cam", on: boolean) {
    if (!room) return
    const problem = device === "mic" ? micProblem : camProblem
    try {
      if (device === "mic") await room.localParticipant.setMicrophoneEnabled(on)
      else await room.localParticipant.setCameraEnabled(on)
      problem.value = null
    } catch (error) {
      problem.value = deviceProblemKey(device, error)
    }
    sync()
  }

  async function join(id: Id, title: string) {
    if (inCallOf(id)) {
      setView("expand")
      return
    }
    if (active.value) await leave()

    const thisAttempt = ++attempt
    status.value = "connecting"
    projectId.value = id
    projectTitle.value = title
    view.value = "expanded"
    const preferences = readPreferences()

    let target: Room | null = null
    try {
      const [{ url, token }, livekit] = await Promise.all([callApi.createToken(id), import("livekit-client"), loadMembers(id)])
      if (thisAttempt !== attempt) return
      lk = livekit
      target = new livekit.Room({
        adaptiveStream: true,
        dynacast: true,
        videoCaptureDefaults: {
          resolution: livekit.VideoPresets.h360.resolution,
          deviceId: preferences.camId ? { ideal: preferences.camId } : undefined,
        },
        audioCaptureDefaults: { deviceId: preferences.micId ? { ideal: preferences.micId } : undefined },
      })
      listen(target, livekit)
      await target.connect(url, token)
      if (thisAttempt !== attempt) {
        await target.disconnect()
        return
      }
    } catch (error) {
      void target?.disconnect()
      if (thisAttempt !== attempt) return
      reset()
      if (error instanceof ApiError) ui.fail(error)
      else ui.toast(t("call.failed"), "error")
      return
    }

    room = target
    status.value = "connected"
    sync()
    await enable("mic", preferences.mic)
    await enable("cam", preferences.cam)
    void refreshDevices()
  }

  // Leaving stops the camera and microphone.
  async function leave() {
    attempt++
    const leaving = room
    reset()
    await leaving?.disconnect()
  }

  async function toggleMic() {
    const on = !micOn.value
    savePreferences({ mic: on })
    await enable("mic", on)
  }

  async function toggleCam() {
    const on = !camOn.value
    savePreferences({ cam: on })
    await enable("cam", on)
  }

  // Device names are only known once the browser allowed a device; devices
  // are listed without asking for permission again.
  async function refreshDevices() {
    if (!lk) return
    const list = async (kind: DeviceKind) => (await lk!.Room.getLocalDevices(kind, false))
      .filter((device) => device.deviceId !== "")
      .map((device, index) => ({
        deviceId: device.deviceId,
        label: device.label || t(kind === "audioinput" ? "call.microphoneNumber" : "call.cameraNumber", { number: index + 1 }),
      }))
    try {
      devices.value = { audioinput: await list("audioinput"), videoinput: await list("videoinput") }
    } catch {
      devices.value = { audioinput: [], videoinput: [] }
    }
  }

  async function switchDevice(kind: DeviceKind, deviceId: string) {
    if (!room) return
    try {
      await room.switchActiveDevice(kind, deviceId)
      savePreferences(kind === "audioinput" ? { micId: deviceId } : { camId: deviceId })
    } catch (error) {
      if (kind === "audioinput") micProblem.value = deviceProblemKey("mic", error)
      else camProblem.value = deviceProblemKey("cam", error)
    }
    sync()
  }

  // Called from a click: browsers then allow the call's sound to play.
  async function startAudio() {
    await room?.startAudio()
    sync()
  }

  function setView(action: CallViewAction) {
    view.value = nextView(view.value, action)
  }

  return {
    status, active, projectId, projectTitle, view, participants, remoteAudio, micOn, camOn, notices, audioBlocked,
    devices, activeDevices, inCallOf, join, leave, toggleMic, toggleCam, refreshDevices, switchDevice, startAudio, setView,
  }
})
