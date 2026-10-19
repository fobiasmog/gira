import { computed, onScopeDispose, ref } from "vue"
import { dropIndex, edgeScrollDelta, isNoop } from "./dragMath.ts"

// Sorting by native HTML drag and drop (design.md, Decision 10). Items carry
// data-drag-item="<group>" and data-drag-id; containers are bound with
// container(key); drags start only from elements bound with handle(...).
// The DOM is never moved: Vue renders the result of onMove.

export type DragGroup = "column" | "card" | "row"
export type ContainerKey = string | number

export interface DragMove {
  id: number
  from: ContainerKey
  fromIndex: number
  to: ContainerKey
  // Index among the destination's items once the moved item is taken out.
  toIndex: number
}

interface DragState {
  group: DragGroup
  id: number
  from: ContainerKey
  fromIndex: number
}

interface DropTarget {
  group: DragGroup
  container: ContainerKey
  index: number
}

// One drag at a time, shared by every container. A drop without this state
// did not start from one of our handles and is ignored.
const dragState = ref<DragState | null>(null)
const target = ref<DropTarget | null>(null)
const MIME = (group: DragGroup) => `application/x-goalner-${group}`

let guardInstalled = false
function installDocumentGuard() {
  if (guardInstalled) return
  guardInstalled = true
  // Files, links and text dropped anywhere on the page must not make the
  // browser open or navigate to them.
  document.addEventListener("dragover", (event) => event.preventDefault())
  document.addEventListener("drop", (event) => event.preventDefault())
}

function itemsOf(container: Element, group: DragGroup): HTMLElement[] {
  return [...container.querySelectorAll<HTMLElement>(`[data-drag-item="${group}"]`)]
    .filter((item) => item.closest("[data-drag-container]") === container)
}

function midpoint(element: Element, axis: "x" | "y"): number {
  const rect = element.getBoundingClientRect()
  return axis === "x" ? rect.left + rect.width / 2 : rect.top + rect.height / 2
}

export function useDragSort(options: {
  group: DragGroup
  axis: "x" | "y"
  onMove: (move: DragMove) => unknown
  // A horizontally scrolling element to scroll near its edges during a drag.
  scroller?: () => HTMLElement | null | undefined
}) {
  const { group, axis } = options
  installDocumentGuard()

  let frame = 0
  let scrollFrame = 0
  let scrollDelta = 0

  function scrollLoop() {
    const scroller = options.scroller?.()
    if (!dragState.value || !scroller || scrollDelta === 0) {
      scrollFrame = 0
      return
    }
    scroller.scrollBy({ left: scrollDelta })
    scrollFrame = requestAnimationFrame(scrollLoop)
  }

  function updateEdgeScroll(event: DragEvent) {
    const scroller = options.scroller?.()
    if (!scroller) return
    const rect = scroller.getBoundingClientRect()
    scrollDelta = edgeScrollDelta(event.clientX, rect.left, rect.right)
    if (scrollDelta !== 0 && !scrollFrame) scrollFrame = requestAnimationFrame(scrollLoop)
  }

  function clear() {
    dragState.value = null
    target.value = null
    scrollDelta = 0
    cancelAnimationFrame(frame)
    frame = 0
  }

  function handle(id: number, from: ContainerKey, fromIndex: number) {
    return {
      draggable: "true" as const,
      "data-drag-handle": group,
      onDragstart(event: DragEvent) {
        const item = (event.currentTarget as HTMLElement).closest<HTMLElement>(`[data-drag-item="${group}"]`)
        if (!event.dataTransfer || !item) return
        event.stopPropagation()
        event.dataTransfer.effectAllowed = "move"
        event.dataTransfer.setData(MIME(group), String(id))
        const rect = item.getBoundingClientRect()
        event.dataTransfer.setDragImage(item, event.clientX - rect.left, event.clientY - rect.top)
        dragState.value = { group, id, from, fromIndex }
      },
      onDragend: clear,
    }
  }

  function container(key: ContainerKey) {
    return {
      "data-drag-container": group,
      onDragover(event: DragEvent) {
        if (dragState.value?.group !== group) return
        event.preventDefault()
        event.stopPropagation()
        if (event.dataTransfer) event.dataTransfer.dropEffect = "move"
        updateEdgeScroll(event)
        const element = event.currentTarget as HTMLElement
        const pointer = axis === "x" ? event.clientX : event.clientY
        if (frame) return
        frame = requestAnimationFrame(() => {
          frame = 0
          const state = dragState.value
          if (!state) return
          const others = itemsOf(element, group).filter((item) => Number(item.dataset.dragId) !== state.id)
          target.value = { group, container: key, index: dropIndex(pointer, others.map((item) => midpoint(item, axis))) }
        })
      },
      async onDrop(event: DragEvent) {
        const state = dragState.value
        if (state?.group !== group) return
        event.preventDefault()
        event.stopPropagation()
        const element = event.currentTarget as HTMLElement
        const pointer = axis === "x" ? event.clientX : event.clientY
        const others = itemsOf(element, group).filter((item) => Number(item.dataset.dragId) !== state.id)
        const toIndex = dropIndex(pointer, others.map((item) => midpoint(item, axis)))
        clear()
        if (isNoop(state.from, state.fromIndex, key, toIndex)) return
        await options.onMove({ id: state.id, from: state.from, fromIndex: state.fromIndex, to: key, toIndex })
      },
    }
  }

  // Where Vue should draw the drop indicator in a container: before the
  // item with this id, or at the end (null).
  function indicatorIn(key: ContainerKey, ids: readonly number[]): { beforeId: number | null } | null {
    const drop = target.value
    const state = dragState.value
    if (!drop || !state || drop.group !== group || drop.container !== key) return null
    if (isNoop(state.from, state.fromIndex, key, drop.index)) return null
    const others = ids.filter((id) => id !== state.id)
    return { beforeId: others[drop.index] ?? null }
  }

  const draggingId = computed(() => (dragState.value?.group === group ? dragState.value.id : null))

  onScopeDispose(() => {
    cancelAnimationFrame(frame)
    cancelAnimationFrame(scrollFrame)
  })

  return { handle, container, indicatorIn, draggingId }
}
