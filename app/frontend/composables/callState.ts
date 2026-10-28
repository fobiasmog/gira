import type { MessageKey } from "../i18n/index.ts"

// The pure parts of a call (team-call design.md, Decision 7), apart from the
// store so they run under node --test without a browser or livekit-client.

// expanded: the pane on wide screens, the full-screen overlay on narrow ones.
// bar: controls docked at the bottom. tab: a small tab at the bottom edge.
export type CallView = "expanded" | "bar" | "tab"
export type CallViewAction = "expand" | "shrink" | "hide" | "show"

// expanded ⇄ bar ⇄ tab, one step at a time. "expand" also brings a hidden
// call straight back ("In call" on the board).
export function nextView(view: CallView, action: CallViewAction): CallView {
  switch (action) {
    case "expand": return "expanded"
    case "shrink": return view === "expanded" ? "bar" : view
    case "hide": return view === "bar" ? "tab" : view
    case "show": return view === "tab" ? "bar" : view
  }
}

// Join order, with the member's own tile last. joinedAt is in milliseconds.
export function orderParticipants<T extends { local: boolean; joinedAt: number }>(participants: readonly T[]): T[] {
  return [...participants].sort((a, b) => Number(a.local) - Number(b.local) || a.joinedAt - b.joinedAt)
}

export const PANE_WIDTH = { min: 240, max: 480, default: 320, step: 16 } as const

export function clampPaneWidth(width: number): number {
  if (!Number.isFinite(width)) return PANE_WIDTH.default
  return Math.min(PANE_WIDTH.max, Math.max(PANE_WIDTH.min, Math.round(width)))
}

export function parsePaneWidth(stored: string | null): number {
  return stored === null ? PANE_WIDTH.default : clampPaneWidth(Number(stored))
}

// Microphone and camera on or off, and the chosen devices (null: the
// browser's default), remembered for the next call. Both on the first time.
export interface MediaPreferences {
  mic: boolean
  cam: boolean
  micId: string | null
  camId: string | null
}

export function parseMediaPreferences(stored: string | null): MediaPreferences {
  let value: unknown = null
  try {
    value = stored === null ? null : JSON.parse(stored)
  } catch {
    // Unreadable: the defaults.
  }
  const fields = value !== null && typeof value === "object" ? value as Record<string, unknown> : {}
  const flag = (name: string) => typeof fields[name] === "boolean" ? fields[name] : true
  const id = (name: string) => typeof fields[name] === "string" && fields[name] !== "" ? fields[name] : null
  return { mic: flag("mic"), cam: flag("cam"), micId: id("micId"), camId: id("camId") }
}

// The message for a call that ended, from the name of LiveKit's
// DisconnectReason. Leaving on purpose needs none.
export function disconnectMessageKey(reason: string | undefined): MessageKey | null {
  switch (reason) {
    case "CLIENT_INITIATED": return null
    case "DUPLICATE_IDENTITY": return "call.ended.elsewhere"
    case "PARTICIPANT_REMOVED":
    case "ROOM_DELETED": return "call.ended.noAccess"
    default: return "call.ended.disconnected"
  }
}

// Why a device stays off, from the error the browser gave when it was asked
// for it.
export function deviceProblemKey(device: "mic" | "cam", error: unknown): MessageKey {
  const name = typeof error === "object" && error !== null && "name" in error ? String(error.name) : ""
  const problem = ["NotAllowedError", "PermissionDeniedError", "SecurityError"].includes(name) ? "Blocked"
    : ["NotFoundError", "DevicesNotFoundError", "OverconstrainedError"].includes(name) ? "Missing"
      : ["NotReadableError", "TrackStartError", "AbortError"].includes(name) ? "Busy"
        : "Failed"
  return `call.device.${device}${problem}`
}
