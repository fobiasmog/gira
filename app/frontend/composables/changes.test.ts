import { mock, test } from "node:test"
import assert from "node:assert/strict"
import {
  agentState, asksForReply, boardProgress, canAskStep, countsProgress, nextStep, refresher, statusLine, threadEntries,
  typedChangeName, unfinished,
} from "./changes.ts"
import type { ChangeAgent, ChangeEvent, ChangeRequest, Comment, ProjectAgent, UserCard } from "../api/types.ts"

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
  ({ kind: phase ? "phase" : "import", actor: fish, phase, paths: phase ? null : ["tasks.md"], agent: null, step: null, state: null, created_at })

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


// Requests and agents

test("the next step for each phase: explore, propose, implement twice, then archive", () => {
  assert.deepEqual(
    (["idea", "exploring", "proposed", "implementing", "done"] as const).map((phase) => nextStep(phase)),
    [
      { kind: "explore", label: "startExploring" },
      { kind: "propose", label: "writeProposal" },
      { kind: "implement", label: "implement" },
      { kind: "implement", label: "continueImplementing" },
      { kind: "archive", label: "archiveAndSync" },
    ],
  )
})

const member: UserCard = { id: 1, name: "Ann", email_address: "ann@example.com", avatar_url: null, agent: false, deleted: false }
const request = (fields: Partial<ChangeRequest>): ChangeRequest => ({
  id: 5, kind: "explore", state: "waiting", change: { id: 3, name: "export-csv", phase: "idea" }, requested_by: member,
  taken_by: null, finished_by: null, created_at: "2026-11-18T14:00:00Z", taken_at: null, finished_at: null, ...fields,
})
const agentOf = (fields: Partial<ChangeAgent> = {}): ChangeAgent => ({ user: fish, on: false, since: null, blocked_at: null, ...fields })
const listed = (fields: Partial<ProjectAgent>): ProjectAgent => ({
  ...fish, created_by: member, created_at: "2026-11-01T00:00:00Z", deleted_at: null, token_count: 1, removable: false,
  checked_in_at: null, online: false, working_on: null, ...fields,
})

test("asking for a step: with no open request, or over a waiting reply request, and never on an archived change", () => {
  assert.equal(canAskStep({ archived_at: null, request: null }), true)
  assert.equal(canAskStep({ archived_at: null, request: request({ kind: "reply" }) }), true)
  assert.equal(canAskStep({ archived_at: null, request: request({ kind: "reply", state: "taken" }) }), false)
  assert.equal(canAskStep({ archived_at: null, request: request({}) }), false)
  assert.equal(canAskStep({ archived_at: "2026-11-18T00:00:00Z", request: null }), false)
})

test("agent states: offline first, then on a change, then free", () => {
  assert.deepEqual(agentState(listed({ online: false, working_on: { id: 1, name: "export-csv", project_id: 1 } })), { kind: "offline" })
  assert.deepEqual(agentState(listed({ online: true, working_on: { id: 1, name: "export-csv", project_id: 1 } })), { kind: "busy", change: "export-csv" })
  assert.deepEqual(agentState(listed({ online: true, working_on: { id: null, name: null, project_id: null } })), { kind: "busy", change: null })
  assert.deepEqual(agentState(listed({ online: true })), { kind: "free" })
})

test("the status line: blocked, working, queued, or on the change while an agent is on it, and nothing otherwise", () => {
  const agents = new Map([[fish.id, listed({ online: true, working_on: { id: 3, name: "export-csv", project_id: 1 } })]])
  const taken = request({ state: "taken", taken_by: fish, taken_at: "2026-11-18T14:05:00Z" })

  assert.deepEqual(statusLine({ request: taken, agent: agentOf({ on: true, blocked_at: "2026-11-18T15:00:00Z" }) }, agents), { key: "blocked", agent: fish })
  assert.deepEqual(statusLine({ request: taken, agent: agentOf({ on: true }) }, agents), { key: "working", agent: fish, since: "2026-11-18T14:05:00Z" })
  assert.deepEqual(statusLine({ request: request({ kind: "reply" }), agent: agentOf({ on: true }) }, agents), { key: "queued", agent: fish, offline: false })
  assert.deepEqual(statusLine({ request: request({ kind: "reply" }), agent: agentOf({ on: true }) }, new Map([[fish.id, listed({ online: false })]])),
    { key: "queued", agent: fish, offline: true })
  assert.deepEqual(statusLine({ request: null, agent: agentOf({ on: true }) }, agents), { key: "onChange", agent: fish })

  assert.equal(statusLine({ request: request({}), agent: null }, agents), null, "the agent menu: any free agent will take it")
  assert.equal(statusLine({ request: request({}), agent: agentOf() }, agents), null, "the agent menu: the picked agent will take it")
  assert.equal(statusLine({ request: null, agent: null }, agents), null)
})

test("a comment asks for a reply on an open change past Idea with no open request", () => {
  assert.equal(asksForReply({ archived_at: null, phase: "exploring", request: null }), true)
  assert.equal(asksForReply({ archived_at: null, phase: "idea", request: null }), false)
  assert.equal(asksForReply({ archived_at: null, phase: "done", request: request({}) }), false)
  assert.equal(asksForReply({ archived_at: "2026-11-18T00:00:00Z", phase: "proposed", request: null }), false)
})

test("the refresh: runs every interval while set running and the page is visible, and stops when set off", () => {
  mock.timers.enable({ apis: ["setInterval"] })
  try {
    let visible = true
    let calls = 0
    const refresh = refresher(() => { calls++ }, 10_000, () => visible)

    refresh.set(true)
    refresh.set(true)
    assert.equal(refresh.running, true)
    mock.timers.tick(10_000)
    mock.timers.tick(10_000)
    assert.equal(calls, 2, "one timer, however often it is set running")

    visible = false
    mock.timers.tick(10_000)
    assert.equal(calls, 2, "not while the page is hidden")

    visible = true
    refresh.set(false)
    assert.equal(refresh.running, false)
    mock.timers.tick(30_000)
    assert.equal(calls, 2, "stopped")
  } finally {
    mock.timers.reset()
  }
})
