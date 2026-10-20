import { defineStore } from "pinia"
import { ref } from "vue"
import { tasksApi } from "../api/tasks.ts"
import type { Id, TaskCard } from "../api/types.ts"

// The project's backlog: open root tasks in no sprint, in column order, and
// apart from them the done ones, most recently completed first.
export const useBacklogStore = defineStore("backlog", () => {
  const projectId = ref<Id | null>(null)
  const tasks = ref<TaskCard[]>([])
  const done = ref<TaskCard[]>([])

  async function load(id: Id) {
    const [open, finished] = await Promise.all([tasksApi.list(id, "backlog"), tasksApi.list(id, "backlog_done")])
    tasks.value = open
    done.value = finished
    projectId.value = id
  }

  // On the first column, in no sprint even while a sprint is active. Loads the
  // lists again to show it in column order.
  async function create(id: Id, title: string) {
    await tasksApi.create(id, { title, sprint_id: null })
    await load(id)
  }

  function remove(taskId: Id) {
    tasks.value = tasks.value.filter((task) => task.id !== taskId)
  }

  async function moveToSprint(id: Id, taskId: Id, sprintId: Id): Promise<TaskCard> {
    const card = await tasksApi.setSprint(id, taskId, sprintId)
    remove(taskId)
    return card
  }

  // Puts a task at a position in a column on the board, adding it to the
  // active sprint (sprintId) in the same request.
  async function placeOnColumn(id: Id, taskId: Id, columnId: Id, position: number, sprintId: Id): Promise<TaskCard> {
    const card = await tasksApi.place(id, taskId, { status_id: columnId, position, sprint_id: sprintId })
    remove(taskId)
    return card
  }

  return { projectId, tasks, done, load, create, moveToSprint, placeOnColumn }
})
