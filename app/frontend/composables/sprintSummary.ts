import type { Column, DateString, SprintSummary, TaskCard } from "../api/types.ts"

export type SprintState = "running" | "last-day" | "ended"

export interface SprintProgress {
  done: number
  total: number
  daysLeft: number
  state: SprintState
}

const DAY_MS = 86_400_000

// A calendar date as a day number. Both sides of a difference go through
// UTC, so a DST change between them cannot shift the count.
function dayNumber(year: number, monthIndex: number, day: number): number {
  return Date.UTC(year, monthIndex, day) / DAY_MS
}

function parseDay(value: DateString): number {
  const [year, month, day] = value.split("-").map(Number)
  return dayNumber(year!, month! - 1, day!)
}

// The board's view of the active sprint. The board holds only the active
// sprint's tasks, so its tasks are the sprint's tasks on the board; done ones
// are those in a done column. Days are counted from the browser's local date.
export function sprintSummary(
  sprint: Pick<SprintSummary, "ends_on">,
  columns: Pick<Column, "id" | "done">[],
  tasks: Pick<TaskCard, "status_id">[],
  today: Date,
): SprintProgress {
  const doneColumns = new Set(columns.filter((column) => column.done).map((column) => column.id))
  const left = parseDay(sprint.ends_on) - dayNumber(today.getFullYear(), today.getMonth(), today.getDate())
  return {
    done: tasks.filter((task) => task.status_id !== null && doneColumns.has(task.status_id)).length,
    total: tasks.length,
    daysLeft: Math.max(0, left),
    state: left > 0 ? "running" : left === 0 ? "last-day" : "ended",
  }
}
