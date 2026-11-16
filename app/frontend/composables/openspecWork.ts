import type { Id, TaskCard } from "../api/types.ts"

export interface OpenspecWork {
  name: string
  count: number
}

// The OpenSpec changes that have cards in a sprint outside the done column,
// each with its number of such cards, by name (spec web-client, "OpenSpec
// work in a sprint being archived").
export function unfinishedOpenspecWork(tasks: Pick<TaskCard, "status_id" | "openspec_change">[], doneColumnIds: ReadonlySet<Id>): OpenspecWork[] {
  const counts = new Map<string, number>()
  for (const task of tasks) {
    if (!task.openspec_change || doneColumnIds.has(task.status_id)) continue
    counts.set(task.openspec_change.name, (counts.get(task.openspec_change.name) ?? 0) + 1)
  }
  return [...counts].sort(([a], [b]) => a.localeCompare(b)).map(([name, count]) => ({ name, count }))
}
