import { nextTick } from "vue"
import { ApiError } from "../api/client.ts"
import { useUiStore } from "../stores/ui.ts"
import { t } from "../i18n/index.ts"

// Runs a board move whose store action updates the board at once and then
// saves. The immediate update is rendered inside a view transition where the
// browser has them; a failed save (already rolled back by the store) is
// reported. Resolves to whether the move was saved.
export function useBoardMove() {
  const ui = useUiStore()

  // afterRender runs once the moved item is in its new place, before saving
  // finishes (keyboard moves put focus back on it).
  return async function run(move: () => Promise<void>, afterRender?: () => void): Promise<boolean> {
    let saving: Promise<void> = Promise.resolve()
    const apply = async () => {
      saving = move()
      saving.catch(() => {}) // awaited below; avoids an unhandled-rejection report meanwhile
      await nextTick()
    }
    try {
      const animate = typeof document.startViewTransition === "function" && !matchMedia("(prefers-reduced-motion: reduce)").matches
      if (animate) await document.startViewTransition(apply).updateCallbackDone
      else await apply()
      afterRender?.()
      await saving
      return true
    } catch (error) {
      if (!(error instanceof ApiError)) throw error
      ui.toast(t("board.moveFailed"), "error")
      return false
    }
  }
}
