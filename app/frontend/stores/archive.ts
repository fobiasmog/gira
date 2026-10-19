import { defineStore } from "pinia"
import { ref } from "vue"
import { tasksApi } from "../api/tasks.ts"
import type { Comment, Id, TaskCard, TaskDetail } from "../api/types.ts"

export const useArchiveStore = defineStore("archive", () => {
  const tasks = ref<TaskCard[]>([])
  const task = ref<TaskDetail | null>(null)
  const comments = ref<Comment[]>([])

  async function load(id: Id) {
    tasks.value = await tasksApi.list(id, "archived")
  }

  // An archived task with its comments, read-only.
  async function loadTask(id: Id, taskId: Id) {
    const [detail, list] = await Promise.all([tasksApi.show(id, taskId), tasksApi.comments(id, taskId)])
    task.value = detail
    comments.value = list
  }

  return { tasks, task, comments, load, loadTask }
})
