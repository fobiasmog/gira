import type { ChangeEvent, ChangePhase, ChosenPhase, Column, Comment, Id, TaskCard, TaskCounts } from "../api/types.ts"

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

// The phase a member chooses to keep a change where it is: Done is reported
// while the change is in Implementing (spec changes, "Phase of a change").
export function chosenPhase(phase: ChangePhase): ChosenPhase {
  return phase === "done" ? "implementing" : phase
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
