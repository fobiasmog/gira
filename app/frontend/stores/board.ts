import { defineStore } from "pinia"
import { computed, ref } from "vue"
import { tasksApi, type NewTask } from "../api/tasks.ts"
import { columnsApi } from "../api/columns.ts"
import type { Column, Id, Label, SprintSummary, TaskCard, UserCard } from "../api/types.ts"
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

// Whether a card belongs on the board: a root, non-archived task of the active
// sprint, or of no sprint when none is active.
export function onBoard(card: Pick<TaskCard, "parent_id" | "archived_at" | "sprint_id">, activeSprintId: Id | null): boolean {
  return card.parent_id === null && card.archived_at === null && card.sprint_id === activeSprintId
}

// The board of one project: columns in order and the root tasks on them
// (see onBoard), plus the members and labels cards refer to.
export const useBoardStore = defineStore("board", () => {
  const projectId = ref<Id | null>(null)
  const columns = ref<Column[]>([])
  const tasks = ref<TaskCard[]>([])
  const members = ref<UserCard[]>([])
  const labels = ref<Label[]>([])
  const activeSprint = ref<SprintSummary | null>(null)

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

  async function load(id: Id) {
    const board = await tasksApi.board(id)
    projectId.value = id
    columns.value = board.columns.sort(byPosition)
    tasks.value = board.tasks
    members.value = board.members
    labels.value = board.labels
    activeSprint.value = board.active_sprint
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

  // Takes the task out of the active sprint; it keeps its column.
  async function sendToBacklog(taskId: Id) {
    await tasksApi.setSprint(requireProject(), taskId, null)
    removeTask(taskId)
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
    await load(requireProject())
  }

  async function createTask(fields: NewTask): Promise<TaskCard> {
    const task = await tasksApi.create(requireProject(), fields)
    upsertCard(task)
    return task
  }

  // Keeps the board in step with changes made elsewhere (task page, keyboard
  // moves): a card that left the board is removed.
  function upsertCard(card: TaskCard) {
    const index = tasks.value.findIndex((t) => t.id === card.id)
    if (!onBoard(card, activeSprint.value?.id ?? null)) {
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
    projectId, columns, tasks, members, labels, activeSprint, tasksByColumn, memberById, labelById,
    tasksIn, load, moveTask, sendToBacklog, moveColumn, addColumn, renameColumn, deleteColumn, createTask, upsertCard, removeTask,
  }
})
