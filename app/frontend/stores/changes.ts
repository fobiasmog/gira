import { defineStore } from "pinia"
import { ref } from "vue"
import { changesApi } from "../api/changes.ts"
import { tasksApi } from "../api/tasks.ts"
import type { Change, Id, TaskCard } from "../api/types.ts"

// The changes screen (spec web-client, "Changes screen"): open changes newest
// first, archived ones most recently archived first, and the tasks of each
// change whose section is open.
export const useChangesStore = defineStore("changes", () => {
  const projectId = ref<Id | null>(null)
  const open = ref<Change[]>([])
  const archived = ref<Change[]>([])
  // The tasks of each change whose section has been opened, by change id.
  const tasks = ref(new Map<Id, TaskCard[]>())

  // Also loads again the task lists already shown, so counts and lists agree
  // after a change.
  async function load(id: Id) {
    const [current, past] = await Promise.all([changesApi.list(id, "open"), changesApi.list(id, "archived")])
    const listed = new Set([...current, ...past].map((change) => change.id))
    const shown = projectId.value === id ? [...tasks.value.keys()].filter((changeId) => listed.has(changeId)) : []
    const lists = await Promise.all(shown.map((changeId) => changesApi.tasks(id, changeId)))
    projectId.value = id
    open.value = current
    archived.value = past
    tasks.value = new Map(shown.map((changeId, index) => [changeId, lists[index]!]))
  }

  // A change's tasks, fetched the first time its section opens.
  async function loadTasks(id: Id, changeId: Id) {
    if (tasks.value.has(changeId)) return
    tasks.value.set(changeId, await changesApi.tasks(id, changeId))
  }

  async function create(id: Id, name: string, idea = ""): Promise<Change> {
    const change = await changesApi.create(id, name, idea)
    await load(id)
    return change
  }

  async function archive(id: Id, changeId: Id) {
    await changesApi.archive(id, changeId)
    await load(id)
  }

  // On the first column of the change.
  async function addTask(id: Id, changeId: Id, title: string): Promise<TaskCard> {
    const task = await tasksApi.create(id, { title, change_id: changeId })
    await load(id)
    return task
  }

  // Into another open change, or into no change (null); the task keeps its
  // column.
  async function moveTask(id: Id, taskId: Id, changeId: Id | null): Promise<TaskCard> {
    const card = await tasksApi.setChange(id, taskId, changeId)
    await load(id)
    return card
  }

  return { projectId, open, archived, tasks, load, loadTasks, create, archive, addTask, moveTask }
})
