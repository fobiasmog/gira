import { defineStore } from "pinia"
import { computed, ref } from "vue"
import { ApiError } from "../api/client.ts"
import { changesApi } from "../api/changes.ts"
import { tasksApi, type NewTask } from "../api/tasks.ts"
import { columnsApi } from "../api/columns.ts"
import type { Board, Change, ChangeReference, Column, Id, Label, TaskCard, UserCard } from "../api/types.ts"
import { useProjectsStore } from "./projects.ts"

const byPosition = (a: { position: number | null }, b: { position: number | null }) => (a.position ?? 0) - (b.position ?? 0)

// Moves an item within or between ordered lists and renumbers positions from
// 0, as the server does. toIndex is the item's index in the destination list
// once it has been taken out of its source list.
export function reorder<T extends { position: number | null }>(from: T[], to: T[], item: T, toIndex: number): void {
  from.splice(from.indexOf(item), 1)
  to.splice(Math.max(0, Math.min(toIndex, to.length)), 0, item)
  from.forEach((t, i) => { t.position = i })
  to.forEach((t, i) => { t.position = i })
}

// Which board the address asks for (spec web-client, "Board change tabs"):
// the default one, the tasks in no change, or an open change by name.
export type BoardTab = { kind: "default" } | { kind: "other" } | { kind: "change"; name: string }
export const DEFAULT_TAB: BoardTab = { kind: "default" }
export const OTHER_TAB: BoardTab = { kind: "other" }

// The change a tab shows among the open changes, newest first, or null for
// the tasks in no change. Without a tab, and for a change that is not open,
// that is the newest open change, or no change when none is open; missing
// then names the change the address asked for.
export function resolveTab(tab: BoardTab, changes: ChangeReference[]): { change: ChangeReference | null; missing: string | null } {
  if (tab.kind === "other") return { change: null, missing: null }
  const named = tab.kind === "change" ? changes.find((change) => change.name === tab.name) : undefined
  return { change: named ?? changes[0] ?? null, missing: tab.kind === "change" && !named ? tab.name : null }
}

// Whether a card belongs on the board of a change (or of the tasks in no
// change, for null): a root, non-archived task of that change.
export function onBoard(card: Pick<TaskCard, "parent_id" | "archived_at" | "change_id">, changeId: Id | null): boolean {
  return card.parent_id === null && card.archived_at === null && card.change_id === changeId
}

// The board of one project and one change (or of the tasks in no change):
// columns in order and the root tasks on them (see onBoard), the members and
// labels cards refer to, and the project's open changes for the tabs.
export const useBoardStore = defineStore("board", () => {
  const projectId = ref<Id | null>(null)
  const columns = ref<Column[]>([])
  const tasks = ref<TaskCard[]>([])
  const members = ref<UserCard[]>([])
  const labels = ref<Label[]>([])
  // The change shown, or null for the tasks in no change.
  const change = ref<ChangeReference | null>(null)
  const changes = ref<Change[]>([])
  // The name of a change the address asked for that is not open.
  const missingChange = ref<string | null>(null)

  const tasksByColumn = computed(() => {
    const groups = new Map<Id, TaskCard[]>(columns.value.map((column) => [column.id, []]))
    for (const task of tasks.value) groups.get(task.status_id)?.push(task)
    for (const list of groups.values()) list.sort(byPosition)
    return groups
  })
  const memberById = computed(() => new Map(members.value.map((member) => [member.id, member])))
  const labelById = computed(() => new Map(labels.value.map((label) => [label.id, label])))

  function tasksIn(columnId: Id): TaskCard[] {
    return tasksByColumn.value.get(columnId) ?? []
  }

  function requireProject(): Id {
    if (projectId.value === null) throw new Error("board not loaded")
    return projectId.value
  }

  // A change's board, or null when the change is not open.
  async function changeBoard(id: Id, name: string): Promise<Board | null> {
    try {
      return await tasksApi.board(id, name)
    } catch (error) {
      if (error instanceof ApiError && error.status === 404) return null
      throw error
    }
  }

  // Each load is numbered, so a slow answer for a tab left in the meantime
  // does not replace the board shown.
  let loads = 0

  // A named change takes one request. The default tab, or a change that is
  // not open, takes the board of the tasks in no change first, which lists
  // the open changes to choose from.
  async function load(id: Id, tab: BoardTab = DEFAULT_TAB) {
    const ticket = ++loads
    let board = tab.kind === "change" ? await changeBoard(id, tab.name) : null
    let missing: string | null = null
    if (!board) {
      const other = await tasksApi.board(id, null)
      const resolved = resolveTab(tab, other.changes)
      missing = resolved.missing
      board = resolved.change ? await tasksApi.board(id, resolved.change.id) : other
    }
    if (ticket !== loads) return
    projectId.value = id
    columns.value = board.columns.sort(byPosition)
    tasks.value = board.tasks
    members.value = board.members
    labels.value = board.labels
    change.value = board.change
    changes.value = board.changes
    missingChange.value = missing
    useProjectsStore().upsert(board.project)
  }

  function snapshot() {
    const saved = tasks.value.map((task) => ({ ...task }))
    return () => { tasks.value = saved }
  }

  // Shows the move at once and saves it; puts everything back if saving fails.
  // toIndex is as for reorder().
  async function moveTask(taskId: Id, toColumnId: Id, toIndex: number) {
    const task = tasks.value.find((t) => t.id === taskId)
    if (!task) return
    const restore = snapshot()
    const from = tasksIn(task.status_id)
    const to = toColumnId === task.status_id ? from : tasksIn(toColumnId)
    task.status_id = toColumnId
    reorder(from, to, task, toIndex)
    try {
      upsertCard(await tasksApi.place(requireProject(), taskId, { status_id: toColumnId, position: task.position ?? 0 }))
    } catch (error) {
      restore()
      throw error
    }
  }

  async function moveColumn(columnId: Id, toIndex: number) {
    const column = columns.value.find((c) => c.id === columnId)
    if (!column) return
    const saved = columns.value.map((c) => ({ ...c }))
    const list = [...columns.value]
    reorder(list, list, column, toIndex)
    columns.value = list
    try {
      columns.value = (await columnsApi.move(requireProject(), columnId, toIndex)).sort(byPosition)
    } catch (error) {
      columns.value = saved
      throw error
    }
  }

  async function addColumn(title: string) {
    columns.value = (await columnsApi.create(requireProject(), title)).sort(byPosition)
  }

  async function renameColumn(columnId: Id, title: string) {
    columns.value = (await columnsApi.rename(requireProject(), columnId, title)).sort(byPosition)
  }

  // The column's tasks move to the end of the first remaining column (and are
  // completed if that is the done column), so the board is loaded again.
  async function deleteColumn(columnId: Id) {
    await columnsApi.delete(requireProject(), columnId)
    await load(requireProject(), change.value ? { kind: "change", name: change.value.name } : OTHER_TAB)
  }

  // In the change shown, or in no change on the board of other tasks.
  async function createTask(fields: NewTask): Promise<TaskCard> {
    const task = await tasksApi.create(requireProject(), { ...fields, change_id: change.value?.id ?? null })
    upsertCard(task)
    return task
  }

  async function createChange(name: string, idea = ""): Promise<Change> {
    const created = await changesApi.create(requireProject(), name, idea)
    changes.value = [created, ...changes.value]
    return created
  }

  async function archiveChange(changeId: Id): Promise<Change> {
    const archived = await changesApi.archive(requireProject(), changeId)
    changes.value = changes.value.filter((open) => open.id !== changeId)
    return archived
  }

  // Keeps the board in step with changes made elsewhere (task page, keyboard
  // moves): a card that left the board is removed.
  function upsertCard(card: TaskCard) {
    const index = tasks.value.findIndex((t) => t.id === card.id)
    if (!onBoard(card, change.value?.id ?? null)) {
      if (index !== -1) tasks.value.splice(index, 1)
      return
    }
    const fields: TaskCard = { ...card }
    if (index === -1) tasks.value.push(fields)
    else tasks.value[index] = { ...tasks.value[index], ...fields }
  }

  function removeTask(taskId: Id) {
    tasks.value = tasks.value.filter((task) => task.id !== taskId)
  }

  return {
    projectId, columns, tasks, members, labels, change, changes, missingChange, tasksByColumn, memberById, labelById,
    tasksIn, load, moveTask, moveColumn, addColumn, renameColumn, deleteColumn, createTask, createChange, archiveChange,
    upsertCard, removeTask,
  }
})
