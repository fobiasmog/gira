import { test } from "node:test"
import assert from "node:assert/strict"
import { boardProgress, countsProgress, typedChangeName, unfinished } from "./changes.ts"

const columns = [{ id: 1, done: false }, { id: 2, done: false }, { id: 3, done: true }]

test("board progress: cards in the done column of all cards on the board", () => {
  const tasks = [{ status_id: 1 }, { status_id: 2 }, { status_id: 3 }, { status_id: 1 }]

  assert.deepEqual(boardProgress(columns, tasks), { done: 1, total: 4 })
  assert.deepEqual(boardProgress(columns, []), { done: 0, total: 0 })
})

test("listed progress: from the counts per column, keyed by column id", () => {
  assert.deepEqual(countsProgress(columns, { by_status: { "1": 2, "3": 1 }, total: 3 }), { done: 1, total: 3 })
  assert.deepEqual(countsProgress(columns, { by_status: {}, total: 0 }), { done: 0, total: 0 })
})

test("unfinished cards: those not in the done column", () => {
  assert.equal(unfinished({ done: 1, total: 4 }), 3)
  assert.equal(unfinished({ done: 2, total: 2 }), 0)
})

test("a typed name: capitals to lowercase and spaces to hyphens, one character for one", () => {
  assert.equal(typedChangeName("Export CSV"), "export-csv")
  assert.equal(typedChangeName("add-labels"), "add-labels")
  assert.equal(typedChangeName("Fix  2FA"), "fix--2fa")
  assert.equal(typedChangeName("Fix_Login!").length, "Fix_Login!".length)
})
