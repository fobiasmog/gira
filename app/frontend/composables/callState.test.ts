import { test } from "node:test"
import assert from "node:assert/strict"
import {
  clampPaneWidth, deviceProblemKey, disconnectMessageKey, nextView, orderParticipants, parseMediaPreferences, parsePaneWidth,
} from "./callState.ts"
import { en } from "../i18n/en.ts"

test("the call shrinks from the expanded view to the bar and then the tab, and comes back the same way", () => {
  assert.equal(nextView("expanded", "shrink"), "bar")
  assert.equal(nextView("bar", "hide"), "tab")
  assert.equal(nextView("tab", "show"), "bar")
  assert.equal(nextView("bar", "expand"), "expanded")
})

test("expand brings a hidden call straight back", () => {
  assert.equal(nextView("tab", "expand"), "expanded")
})

test("steps that do not apply keep the view", () => {
  assert.equal(nextView("expanded", "hide"), "expanded")
  assert.equal(nextView("expanded", "show"), "expanded")
  assert.equal(nextView("tab", "shrink"), "tab")
  assert.equal(nextView("bar", "show"), "bar")
})

test("participants in join order, with the member's own tile last", () => {
  const bob = { name: "Bob", local: false, joinedAt: 2000 }
  const me = { name: "Me", local: true, joinedAt: 500 }
  const alice = { name: "Alice", local: false, joinedAt: 1000 }

  assert.deepEqual(orderParticipants([bob, me, alice]).map((p) => p.name), ["Alice", "Bob", "Me"])
})

test("the pane width stays between 240 and 480 pixels", () => {
  assert.equal(clampPaneWidth(100), 240)
  assert.equal(clampPaneWidth(900), 480)
  assert.equal(clampPaneWidth(333.6), 334)
  assert.equal(clampPaneWidth(Number.NaN), 320)
})

test("a stored pane width is read back, and anything else gives 320 pixels", () => {
  assert.equal(parsePaneWidth("400"), 400)
  assert.equal(parsePaneWidth("1000"), 480)
  assert.equal(parsePaneWidth(null), 320)
  assert.equal(parsePaneWidth("wide"), 320)
})

test("media preferences: both devices on the first time", () => {
  assert.deepEqual(parseMediaPreferences(null), { mic: true, cam: true, micId: null, camId: null })
})

test("media preferences are read back", () => {
  const stored = JSON.stringify({ mic: true, cam: false, micId: "usb-mic", camId: "" })
  assert.deepEqual(parseMediaPreferences(stored), { mic: true, cam: false, micId: "usb-mic", camId: null })
})

test("unreadable media preferences give the defaults, field by field", () => {
  assert.deepEqual(parseMediaPreferences("{not json"), { mic: true, cam: true, micId: null, camId: null })
  assert.deepEqual(parseMediaPreferences("[false]"), { mic: true, cam: true, micId: null, camId: null })
  assert.deepEqual(parseMediaPreferences(JSON.stringify({ mic: "no", cam: false, micId: 4 })), { mic: true, cam: false, micId: null, camId: null })
})

test("a disconnect reason gives the message to show", () => {
  assert.equal(disconnectMessageKey("CLIENT_INITIATED"), null)
  assert.equal(disconnectMessageKey("DUPLICATE_IDENTITY"), "call.ended.elsewhere")
  assert.equal(disconnectMessageKey("PARTICIPANT_REMOVED"), "call.ended.noAccess")
  assert.equal(disconnectMessageKey("ROOM_DELETED"), "call.ended.noAccess")
  assert.equal(disconnectMessageKey("SIGNAL_CLOSE"), "call.ended.disconnected")
  assert.equal(disconnectMessageKey(undefined), "call.ended.disconnected")
})

test("a device error says why the device is off", () => {
  const error = (name: string) => Object.assign(new Error(name), { name })
  assert.equal(deviceProblemKey("cam", error("NotAllowedError")), "call.device.camBlocked")
  assert.equal(deviceProblemKey("mic", error("NotFoundError")), "call.device.micMissing")
  assert.equal(deviceProblemKey("cam", error("NotReadableError")), "call.device.camBusy")
  assert.equal(deviceProblemKey("mic", error("TypeError")), "call.device.micFailed")
  assert.equal(deviceProblemKey("mic", "weird"), "call.device.micFailed")
})

test("every message key exists", () => {
  const keys = [
    ...["CLIENT_INITIATED", "DUPLICATE_IDENTITY", "PARTICIPANT_REMOVED", "OTHER"].map(disconnectMessageKey),
    ...["NotAllowedError", "NotFoundError", "NotReadableError", "Other"].flatMap((name) =>
      (["mic", "cam"] as const).map((device) => deviceProblemKey(device, { name }))),
  ].filter((key) => key !== null)
  for (const key of keys) {
    const text = key.split(".").reduce<unknown>((node, part) => (node as Record<string, unknown>)[part], en)
    assert.equal(typeof text, "string", key)
  }
})
