import { test } from "node:test"
import assert from "node:assert/strict"
import { onBoard, resolveTab } from "./board.ts"

const card = (change_id: number | null, extra: { parent_id?: number | null; archived_at?: string | null } = {}) =>
  ({ change_id, parent_id: null, archived_at: null, ...extra })

// Open changes, newest first, as the board lists them.
const changes = [{ id: 9, name: "fix-login" }, { id: 7, name: "add-labels" }]

test("a change's board holds that change's tasks only", () => {
  assert.equal(onBoard(card(7), 7), true)
  assert.equal(onBoard(card(null), 7), false)
  assert.equal(onBoard(card(8), 7), false)
})

test("the board of other tasks holds the tasks in no change", () => {
  assert.equal(onBoard(card(null), null), true)
  assert.equal(onBoard(card(7), null), false)
})

test("subtasks and archived tasks are never on a board", () => {
  assert.equal(onBoard(card(7, { parent_id: 1 }), 7), false)
  assert.equal(onBoard(card(null, { archived_at: "2026-10-20T10:00:00Z" }), null), false)
})

test("without a tab, the newest open change is shown", () => {
  assert.deepEqual(resolveTab({ kind: "default" }, changes), { change: changes[0], missing: null })
})

test("without an open change, the tasks in no change are shown", () => {
  assert.deepEqual(resolveTab({ kind: "default" }, []), { change: null, missing: null })
  assert.deepEqual(resolveTab({ kind: "change", name: "add-labels" }, []), { change: null, missing: "add-labels" })
})

test("a named open change is shown, and the other tasks when asked for", () => {
  assert.deepEqual(resolveTab({ kind: "change", name: "add-labels" }, changes), { change: changes[1], missing: null })
  assert.deepEqual(resolveTab({ kind: "other" }, changes), { change: null, missing: null })
})

test("a change that is not open shows the default tab and names the missing change", () => {
  assert.deepEqual(resolveTab({ kind: "change", name: "old-work" }, changes), { change: changes[0], missing: "old-work" })
})
