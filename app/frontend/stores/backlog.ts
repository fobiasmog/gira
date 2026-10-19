import { defineStore } from "pinia"
import { ref } from "vue"
import { tasksApi } from "../api/tasks.ts"
import type { Id, TaskCard } from "../api/types.ts"

// Root tasks of a project that are not on a column.
export const useBacklogStore = defineStore("backlog", () => {
  const projectId = ref<Id | null>(null)
  const tasks = ref<TaskCard[]>([])

  async function load(id: Id) {
    tasks.value = await tasksApi.list(id, "backlog")
    projectId.value = id
  }

  async function create(id: Id, title: string) {
    const task = await tasksApi.create(id, { title, status_id: null })
    tasks.value.push(task)
  }

  // Puts a task at the end of a column on the board.
  async function placeOnColumn(id: Id, taskId: Id, columnId: Id, position: number) {
    await tasksApi.place(id, taskId, { status_id: columnId, position })
    tasks.value = tasks.value.filter((task) => task.id !== taskId)
  }

  return { projectId, tasks, load, create, placeOnColumn }
})
