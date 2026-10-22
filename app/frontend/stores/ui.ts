import { defineStore } from "pinia"
import { computed, nextTick, ref } from "vue"
import { ApiError } from "../api/client.ts"
import { errorMessage } from "../api/errors.ts"
import { readStored, writeStored } from "../composables/storage.ts"

export interface Toast {
  id: number
  message: string
  kind: "info" | "error"
}

const TOAST_MS = 5000
const SIDEBAR_KEY = "goalner.sidebarCollapsed"

export const useUiStore = defineStore("ui", () => {
  // Count of pending page loads; the shell shows a progress bar while > 0.
  const pending = ref(0)
  const loading = computed(() => pending.value > 0)
  // Set when the current page's data does not exist (or is not visible); the
  // shell then shows the not-found screen. Cleared on every navigation.
  const notFound = ref(false)
  const toasts = ref<Toast[]>([])
  let nextId = 1
  // Text for the screen-reader-only live region in the shell.
  const announcement = ref("")
  // Whether the wide-screen sidebar is collapsed to a rail of icons.
  const sidebarCollapsed = ref(readStored(SIDEBAR_KEY) === "true")

  function toggleSidebar() {
    sidebarCollapsed.value = !sidebarCollapsed.value
    writeStored(SIDEBAR_KEY, String(sidebarCollapsed.value))
  }

  async function announce(message: string) {
    announcement.value = ""
    await nextTick()
    announcement.value = message
  }

  function dismiss(id: number) {
    toasts.value = toasts.value.filter((toast) => toast.id !== id)
  }

  function toast(message: string, kind: Toast["kind"] = "info") {
    const id = nextId++
    toasts.value = [...toasts.value.filter((t) => t.message !== message), { id, message, kind }]
    setTimeout(() => dismiss(id), TOAST_MS)
  }

  // Reports a failed action. Anything that is not an API error is a bug and
  // goes on to the global error handler.
  function fail(error: unknown): void {
    if (!(error instanceof ApiError)) throw error
    toast(errorMessage(error), "error")
  }

  // Loads a page's data: shows progress, and turns a 404 into the not-found
  // screen. Resolves to undefined when the load failed.
  async function load<T>(work: Promise<T>): Promise<T | undefined> {
    pending.value++
    try {
      return await work
    } catch (error) {
      if (error instanceof ApiError && error.status === 404) notFound.value = true
      else fail(error)
      return undefined
    } finally {
      pending.value--
    }
  }

  return {
    loading, notFound, load, fail, toasts, toast, dismiss, announcement, announce, sidebarCollapsed, toggleSidebar,
  }
})
