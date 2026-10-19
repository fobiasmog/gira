import { defineStore } from "pinia"
import { computed, ref } from "vue"
import { sprintsApi, type NewSprint } from "../api/sprints.ts"
import type { Id, Sprint } from "../api/types.ts"

export const useSprintsStore = defineStore("sprints", () => {
  const projectId = ref<Id | null>(null)
  const sprints = ref<Sprint[]>([])
  const archived = ref<Sprint[]>([])
  const active = computed(() => sprints.value.find((sprint) => sprint.active) ?? null)

  async function load(id: Id) {
    const [current, past] = await Promise.all([sprintsApi.list(id, "all"), sprintsApi.list(id, "archived")])
    projectId.value = id
    sprints.value = current
    archived.value = past
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

  return { projectId, sprints, archived, active, load, create, activate, archive }
})
