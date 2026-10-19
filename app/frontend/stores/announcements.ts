import { defineStore } from "pinia"
import { ref } from "vue"
import { accountApi } from "../api/account.ts"
import type { Announcement } from "../api/types.ts"

export const useAnnouncementsStore = defineStore("announcements", () => {
  const announcements = ref<Announcement[]>([])

  async function load() {
    announcements.value = await accountApi.announcements()
  }

  async function dismissAll() {
    await accountApi.dismissAnnouncements()
    announcements.value = []
  }

  return { announcements, load, dismissAll }
})
