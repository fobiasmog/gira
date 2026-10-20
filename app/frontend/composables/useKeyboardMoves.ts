import type { Column, TaskCard } from "../api/types.ts"
import { useBoardStore } from "../stores/board.ts"
import { useUiStore } from "../stores/ui.ts"
import { useBoardMove } from "./useBoardMove.ts"
import { t } from "../i18n/index.ts"

// Alt+arrow moves for focused cards, list rows and column headers (spec
// board-drag-and-drop, "Keyboard moves"), saved like drag moves. Focus stays
// on the moved item and the result is announced.
export function useKeyboardMoves() {
  const board = useBoardStore()
  const ui = useUiStore()
  const runMove = useBoardMove()

  const isMoveKey = (event: KeyboardEvent) => event.altKey && !event.ctrlKey && !event.metaKey && !event.shiftKey

  function focus(selector: string) {
    document.querySelector<HTMLElement>(selector)?.focus()
  }

  function onTaskKey(event: KeyboardEvent, task: TaskCard) {
    if (!isMoveKey(event)) return
    const columns = board.columns
    const columnIndex = columns.findIndex((column) => column.id === task.status_id)
    const index = board.tasksIn(task.status_id).findIndex((t) => t.id === task.id)
    const count = board.tasksIn(task.status_id).length
    let to: Column | undefined = columns[columnIndex]
    let toIndex: number

    switch (event.key) {
      case "ArrowUp":
        if (index <= 0) return
        toIndex = index - 1
        break
      case "ArrowDown":
        if (index >= count - 1) return
        toIndex = index + 1
        break
      case "ArrowLeft":
      case "ArrowRight":
        to = columns[columnIndex + (event.key === "ArrowLeft" ? -1 : 1)]
        if (!to) return
        toIndex = board.tasksIn(to.id).length
        break
      default:
        return
    }
    event.preventDefault()
    const column = to!
    void runMove(() => board.moveTask(task.id, column.id, toIndex), () => {
      focus(`[data-drag-id="${task.id}"] [data-move-focus]`)
      void ui.announce(t("board.movedTo", { key: task.key, column: column.title, position: toIndex + 1 }))
    })
  }

  function onColumnKey(event: KeyboardEvent, column: Column) {
    if (!isMoveKey(event) || (event.key !== "ArrowLeft" && event.key !== "ArrowRight")) return
    const index = board.columns.findIndex((c) => c.id === column.id)
    const toIndex = index + (event.key === "ArrowLeft" ? -1 : 1)
    if (toIndex < 0 || toIndex >= board.columns.length) return
    event.preventDefault()
    void runMove(() => board.moveColumn(column.id, toIndex), () => {
      focus(`#column-${column.id}`)
      void ui.announce(t("board.columnMovedTo", { title: column.title, position: toIndex + 1 }))
    })
  }

  return { onTaskKey, onColumnKey }
}
