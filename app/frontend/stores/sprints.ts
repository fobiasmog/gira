import { defineStore } from "pinia"
import { computed, ref } from "vue"
import { sprintsApi, type NewSprint } from "../api/sprints.ts"
import { tasksApi } from "../api/tasks.ts"
import type { Id, Sprint, SprintTaskCard, TaskCard } from "../api/types.ts"

export const useSprintsStore = defineStore("sprints", () => {
  const projectId = ref<Id | null>(null)
  const sprints = ref<Sprint[]>([])
  const archived = ref<Sprint[]>([])
  // The tasks of each sprint whose section has been opened, by sprint id.
  const tasks = ref(new Map<Id, SprintTaskCard[]>())
  const active = computed(() => sprints.value.find((sprint) => sprint.active) ?? null)

  // Also loads again the task lists already shown, so counts and lists agree
  // after a change.
  async function load(id: Id) {
    const [current, past] = await Promise.all([sprintsApi.list(id, "all"), sprintsApi.list(id, "archived")])
    const shown = projectId.value === id ? [...tasks.value.keys()].filter((sprintId) => current.some((sprint) => sprint.id === sprintId)) : []
    const lists = await Promise.all(shown.map((sprintId) => sprintsApi.tasks(id, sprintId)))
    projectId.value = id
    sprints.value = current
    archived.value = past
    tasks.value = new Map(shown.map((sprintId, index) => [sprintId, lists[index]!]))
  }

  // A sprint's tasks, fetched the first time its section opens.
  async function loadTasks(id: Id, sprintId: Id) {
    if (tasks.value.has(sprintId)) return
    tasks.value.set(sprintId, await sprintsApi.tasks(id, sprintId))
  }

  async function create(id: Id, sprint: NewSprint) {
    await sprintsApi.create(id, sprint)
    await load(id)
  }

  async function activate(id: Id, sprintId: Id) {
    await sprintsApi.activate(id, sprintId)
    await load(id)
  }

  async function archive(id: Id, sprintId: Id, carryToSprintId: Id | null) {
    await sprintsApi.archive(id, sprintId, carryToSprintId)
    await load(id)
  }

  // On the first column of the sprint.
  async function addTask(id: Id, sprintId: Id, title: string): Promise<TaskCard> {
    const task = await tasksApi.create(id, { title, sprint_id: sprintId })
    await load(id)
    return task
  }

  // Into another sprint, or to the backlog (null); the task keeps its column.
  async function moveTask(id: Id, taskId: Id, sprintId: Id | null): Promise<TaskCard> {
    const card = await tasksApi.setSprint(id, taskId, sprintId)
    await load(id)
    return card
  }

  return { projectId, sprints, archived, tasks, active, load, loadTasks, create, activate, archive, addTask, moveTask }
})
