import type { Column, Id, TaskCard, TaskCounts } from "../api/types.ts"

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
