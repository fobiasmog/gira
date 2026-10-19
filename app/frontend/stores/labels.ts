import { defineStore } from "pinia"
import { ref } from "vue"
import { labelsApi } from "../api/labels.ts"
import type { Id, Label } from "../api/types.ts"

export const useLabelsStore = defineStore("labels", () => {
  const projectId = ref<Id | null>(null)
  const labels = ref<Label[]>([])

  async function load(id: Id) {
    labels.value = await labelsApi.list(id)
    projectId.value = id
  }

  async function create(id: Id, title: string): Promise<Label> {
    const label = await labelsApi.create(id, title)
    labels.value = [...labels.value, label].sort((a, b) => a.title.localeCompare(b.title))
    return label
  }

  return { projectId, labels, load, create }
})
