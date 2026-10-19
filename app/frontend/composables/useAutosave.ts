import { onBeforeUnmount, ref } from "vue"

// Saves after `delay` ms without changes, or at once on flush() (blur,
// leaving the page). A failed save keeps the changes pending for the next try.
export function useAutosave(save: () => Promise<void>, onError: (error: unknown) => void, delay = 1000) {
  const pending = ref(false)
  let timer: ReturnType<typeof setTimeout> | undefined
  let running: Promise<void> | null = null

  function schedule() {
    pending.value = true
    clearTimeout(timer)
    timer = setTimeout(flush, delay)
  }

  async function flush(): Promise<void> {
    clearTimeout(timer)
    if (running) await running
    if (!pending.value) return
    pending.value = false
    running = save()
      .catch((error: unknown) => {
        pending.value = true
        onError(error)
      })
      .finally(() => { running = null })
    await running
  }

  onBeforeUnmount(() => { void flush() })

  return { pending, schedule, flush }
}
