import { defineStore } from "pinia"
import { ref } from "vue"
import { meApi, type ProfileChanges } from "../api/me.ts"
import type { Profile } from "../api/types.ts"
import { setLanguage } from "../i18n/index.ts"
import { identifyUser } from "../sentry/index.ts"

export const useMeStore = defineStore("me", () => {
  const profile = ref<Profile | null>(null)

  function apply(next: Profile) {
    profile.value = next
    setLanguage(next.lang)
  }

  async function load() {
    const next = await meApi.show()
    apply(next)
    identifyUser(next.id)
  }

  async function update(changes: ProfileChanges) {
    apply(await meApi.update(changes))
  }

  async function updateAvatar(file: File) {
    apply(await meApi.updateAvatar(file))
  }

  return { profile, load, update, updateAvatar }
})
