import { defineStore } from "pinia"
import { ref } from "vue"
import { milestonesApi } from "../api/milestones.ts"
import type { Id, Milestone, MilestoneDetail } from "../api/types.ts"

export const useMilestonesStore = defineStore("milestones", () => {
  const projectId = ref<Id | null>(null)
  const milestones = ref<Milestone[]>([])
  const deleted = ref<Milestone[]>([])
  const current = ref<MilestoneDetail | null>(null)

  async function load(id: Id) {
    const [kept, removed] = await Promise.all([milestonesApi.list(id), milestonesApi.list(id, "deleted")])
    projectId.value = id
    milestones.value = kept
    deleted.value = removed
  }

  async function loadOne(id: Id, milestoneId: Id) {
    current.value = await milestonesApi.show(id, milestoneId)
  }

  async function create(id: Id, title: string) {
    milestones.value.push(await milestonesApi.create(id, title))
  }

  async function remove(id: Id, milestoneId: Id) {
    await milestonesApi.delete(id, milestoneId)
    const milestone = milestones.value.find((m) => m.id === milestoneId)
    milestones.value = milestones.value.filter((m) => m.id !== milestoneId)
    if (milestone) deleted.value.push({ ...milestone, deleted_at: new Date().toISOString() })
  }

  async function recover(id: Id, milestoneId: Id) {
    const milestone = await milestonesApi.recover(id, milestoneId)
    deleted.value = deleted.value.filter((m) => m.id !== milestoneId)
    milestones.value.push(milestone)
  }

  return { projectId, milestones, deleted, current, load, loadOne, create, remove, recover }
})
