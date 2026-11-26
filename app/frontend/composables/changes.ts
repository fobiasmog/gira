import type {
  AskableKind, Change, ChangeEvent, ChangePhase, Column, Comment, Id, ProjectAgent, TaskCard, TaskCounts, UserCard,
} from "../api/types.ts"

// How far a change has come: its cards in the done column, of all its cards.
export interface ChangeProgress {
  done: number
  total: number
}

const doneColumnIds = (columns: Pick<Column, "id" | "done">[]): Set<Id> =>
  new Set(columns.filter((column) => column.done).map((column) => column.id))

// The cards on a board (spec web-client, "Board change summary").
export function boardProgress(columns: Pick<Column, "id" | "done">[], tasks: Pick<TaskCard, "status_id">[]): ChangeProgress {
  const done = doneColumnIds(columns)
  return { done: tasks.filter((task) => done.has(task.status_id)).length, total: tasks.length }
}

// A listed change's root tasks, from its counts per column.
export function countsProgress(columns: Pick<Column, "id" | "done">[], counts: TaskCounts): ChangeProgress {
  let done = 0
  for (const id of doneColumnIds(columns)) done += counts.by_status[String(id)] ?? 0
  return { done, total: counts.total }
}

// The root tasks archiving leaves unfinished with the change (spec
// web-client, "Archiving a change").
export function unfinished(progress: ChangeProgress): number {
  return progress.total - progress.done
}

// A change name as it is typed: capitals become lowercase and spaces become
// hyphens (spec web-client, "New change dialog"). One character stays one
// character, so the caret can stay where it was; anything else the server
// refuses with a message.
export function typedChangeName(value: string): string {
  return value
    .replace(/\p{Lu}/gu, (letter) => {
      const lower = letter.toLowerCase()
      return lower.length === letter.length ? lower : letter
    })
    .replace(/\s/g, "-")
}

// One entry of a change's thread: a comment, or a line of its history.
export type ThreadEntry =
  | { kind: "comment"; at: number; comment: Comment }
  | { kind: "event"; at: number; event: ChangeEvent }

// Comments and history lines merged by time, oldest first (spec web-client,
// "Change page"). At the same time a history line comes first: a move is
// made before the question asked with it.
export function threadEntries(comments: Comment[], history: ChangeEvent[]): ThreadEntry[] {
  const entries: ThreadEntry[] = [
    ...history.map((event) => ({ kind: "event" as const, at: Date.parse(event.created_at), event })),
    ...comments.map((comment) => ({ kind: "comment" as const, at: Date.parse(comment.created_at), comment })),
  ]
  return entries.sort((a, b) => a.at - b.at)
}

// Requests and agents (spec web-client, "Requests on the change page";
// add-change-requests design.md, decision 11).

// The step the change page asks for in each reported phase, and its label.
export type StepLabel = "startExploring" | "writeProposal" | "implement" | "continueImplementing" | "archiveAndSync"

const NEXT_STEPS: Record<ChangePhase, { kind: AskableKind; label: StepLabel }> = {
  idea: { kind: "explore", label: "startExploring" },
  exploring: { kind: "propose", label: "writeProposal" },
  proposed: { kind: "implement", label: "implement" },
  implementing: { kind: "implement", label: "continueImplementing" },
  done: { kind: "archive", label: "archiveAndSync" },
}

export function nextStep(phase: ChangePhase): { kind: AskableKind; label: StepLabel } {
  return NEXT_STEPS[phase]
}

// Whether the next step can be asked for: an open change with no open
// request, or with a reply request that nobody has taken, which the step
// replaces.
export function canAskStep(change: Pick<Change, "archived_at" | "request">): boolean {
  if (change.archived_at !== null) return false
  return change.request === null || (change.request.kind === "reply" && change.request.state === "waiting")
}

// An agent as the pickers and the page describe it: offline, or online and
// on a change (named, unless in a project the viewer does not share), or free.
export type AgentState = { kind: "offline" } | { kind: "free" } | { kind: "busy"; change: string | null }

export function agentState(agent: Pick<ProjectAgent, "online" | "working_on">): AgentState {
  if (!agent.online) return { kind: "offline" }
  return agent.working_on ? { kind: "busy", change: agent.working_on.name } : { kind: "free" }
}

// The line that says where a change's request stands while an agent is on
// the change, as a message key and the values it names. Null while no agent
// is on it: the page then shows the agent menu, "[agent] will take it".
// agents: the project's agents with their states, by id.
export type StatusLine =
  | { key: "blocked"; agent: UserCard }
  | { key: "working"; agent: UserCard; since: string }
  | { key: "queued"; agent: UserCard; offline: boolean }
  | { key: "onChange"; agent: UserCard }

export function statusLine(change: Pick<Change, "request" | "agent">, agents: Map<Id, ProjectAgent>): StatusLine | null {
  const { request, agent } = change
  if (!agent?.on) return null
  if (agent.blocked_at) return { key: "blocked", agent: agent.user }
  if (request?.state === "taken" && request.taken_by && request.taken_at) return { key: "working", agent: request.taken_by, since: request.taken_at }
  if (request?.state === "waiting") return { key: "queued", agent: agent.user, offline: agents.get(agent.user.id)?.online === false }
  return { key: "onChange", agent: agent.user }
}

// Whether a person's comment would ask for a reply: on an open change past
// Idea with no open request (spec change-requests, "Reply requests").
export function asksForReply(change: Pick<Change, "archived_at" | "phase" | "request">): boolean {
  return change.archived_at === null && change.phase !== "idea" && change.request === null
}

// While a change has an open request, its page reloads it this often.
export const REFRESH_MS = 10_000

// Calls refresh every interval while it is set running and the page is
// visible; set(false) stops it.
export function refresher(refresh: () => unknown, interval = REFRESH_MS, visible = () => document.visibilityState === "visible") {
  let timer: ReturnType<typeof setInterval> | null = null
  return {
    set(running: boolean) {
      if (running && timer === null) {
        timer = setInterval(() => { if (visible()) void refresh() }, interval)
      } else if (!running && timer !== null) {
        clearInterval(timer)
        timer = null
      }
    },
    get running() {
      return timer !== null
    },
  }
}
