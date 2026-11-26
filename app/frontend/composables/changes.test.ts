import { test } from "node:test"
import assert from "node:assert/strict"
import { boardProgress, chosenPhase, countsProgress, threadEntries, typedChangeName, unfinished } from "./changes.ts"
import type { ChangeEvent, Comment, UserCard } from "../api/types.ts"

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

const fish: UserCard = { id: 9, name: "Fish", email_address: "fish@agents.example", avatar_url: null, agent: true, deleted: false }
const comment = (id: number, created_at: string): Comment =>
  ({ id, body: `Comment ${id}`, author: fish, created_at, updated_at: created_at, attachments: [] })
const event = (phase: ChangeEvent["phase"], created_at: string): ChangeEvent =>
  ({ kind: phase ? "phase" : "import", actor: fish, phase, paths: phase ? null : ["tasks.md"], created_at })

test("the thread: comments and history lines by time, oldest first", () => {
  const entries = threadEntries(
    [comment(2, "2026-11-17T10:48:00.000Z"), comment(3, "2026-11-17T11:02:00.000Z")],
    [event("exploring", "2026-11-17T10:42:00.000Z"), event(null, "2026-11-17T14:05:00.000Z"), event("proposed", "2026-11-17T14:05:00.000Z")],
  )

  assert.deepEqual(
    entries.map((entry) => (entry.kind === "comment" ? `comment ${entry.comment.id}` : `event ${entry.event.kind} ${entry.event.phase}`)),
    ["event phase exploring", "comment 2", "comment 3", "event import null", "event phase proposed"],
  )
})

test("the thread: a history line comes before a comment of the same time, and order is kept within each", () => {
  const at = "2026-11-17T10:42:00.123Z"
  const entries = threadEntries([comment(1, at), comment(2, at)], [event("exploring", at)])

  assert.deepEqual(entries.map((entry) => entry.kind), ["event", "comment", "comment"])
  assert.deepEqual(entries.flatMap((entry) => (entry.kind === "comment" ? [entry.comment.id] : [])), [1, 2])
  assert.deepEqual(threadEntries([], []), [])
})

test("the phase to choose: Done stays Implementing, the others stay as they are", () => {
  assert.equal(chosenPhase("done"), "implementing")
  for (const phase of ["idea", "exploring", "proposed", "implementing"] as const) assert.equal(chosenPhase(phase), phase)
})
