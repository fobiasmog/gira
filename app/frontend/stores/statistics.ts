import { defineStore } from "pinia"
import { ref } from "vue"
import { accountApi } from "../api/account.ts"
import type { Deadline, Id, StatisticsProject, UserCard } from "../api/types.ts"

// The dashboard: open tasks and upcoming deadlines of the user or a teammate.
export const useStatisticsStore = defineStore("statistics", () => {
  const overview = ref<StatisticsProject[]>([])
  const deadlines = ref<Deadline[]>([])
  const teammates = ref<UserCard[]>([])

  async function load(userId?: Id) {
    const [projects, upcoming, people] = await Promise.all([
      accountApi.overview(userId),
      accountApi.deadlines(userId),
      accountApi.teammates(),
    ])
    overview.value = projects
    deadlines.value = upcoming
    teammates.value = people
  }

  return { overview, deadlines, teammates, load }
})
