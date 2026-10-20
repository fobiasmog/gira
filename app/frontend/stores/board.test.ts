import { test } from "node:test"
import assert from "node:assert/strict"
import { onBoard } from "./board.ts"

const card = (sprint_id: number | null, extra: { parent_id?: number | null; archived_at?: string | null } = {}) =>
  ({ sprint_id, parent_id: null, archived_at: null, ...extra })

test("with an active sprint, only its tasks are on the board", () => {
  assert.equal(onBoard(card(7), 7), true)
  assert.equal(onBoard(card(null), 7), false)
})

test("without an active sprint, the tasks in no sprint are on the board", () => {
  assert.equal(onBoard(card(null), null), true)
  assert.equal(onBoard(card(7), null), false)
})

test("a task of another sprint is not on the board", () => {
  assert.equal(onBoard(card(8), 7), false)
})

test("subtasks and archived tasks are never on the board", () => {
  assert.equal(onBoard(card(7, { parent_id: 1 }), 7), false)
  assert.equal(onBoard(card(null, { archived_at: "2026-10-20T10:00:00Z" }), null), false)
})
