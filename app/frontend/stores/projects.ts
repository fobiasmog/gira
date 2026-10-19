import { defineStore } from "pinia"
import { computed, ref } from "vue"
import { projectsApi, type ProjectFields } from "../api/projects.ts"
import type { Id, Project } from "../api/types.ts"

// The user's projects and the project the current route is in.
export const useProjectsStore = defineStore("projects", () => {
  const list = ref<Project[]>([])
  const loaded = ref(false)
  const currentId = ref<Id | null>(null)
  const current = computed(() => list.value.find((project) => project.id === currentId.value) ?? null)

  function sort() {
    list.value.sort((a, b) => a.title.localeCompare(b.title))
  }

  function upsert(project: Project) {
    const index = list.value.findIndex((p) => p.id === project.id)
    if (index === -1) list.value.push(project)
    else list.value[index] = project
    sort()
  }

  async function load() {
    list.value = await projectsApi.list()
    loaded.value = true
  }

  async function create(fields: ProjectFields): Promise<Project> {
    const project = await projectsApi.create(fields)
    upsert(project)
    return project
  }

  async function update(id: Id, fields: ProjectFields) {
    upsert(await projectsApi.update(id, fields))
  }

  function forget(id: Id) {
    list.value = list.value.filter((project) => project.id !== id)
  }

  async function archive(id: Id) {
    await projectsApi.archive(id)
    forget(id)
  }

  async function leave(id: Id) {
    await projectsApi.leave(id)
    forget(id)
  }

  return { list, loaded, currentId, current, load, upsert, create, update, archive, leave }
})
