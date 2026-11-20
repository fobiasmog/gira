<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue"
import AppIcon from "../ui/AppIcon.vue"
import PhasePill from "./PhasePill.vue"
import WaitingMarker from "./WaitingMarker.vue"
import type { Change, ChangePhase, ChangeReference } from "../../api/types.ts"
import { boardLocation, type BoardLayout } from "../../router/routes.ts"
import type { BoardTab } from "../../stores/board.ts"
import { t } from "../../i18n/index.ts"

// The board's tabs (spec web-client, "Board change tabs"): one per open
// change, newest first, then the tasks in no change, then "New change". Each
// change's tab shows its phase and whether it is waiting for people. Each
// tab is a link, so the address names the tab; as in any tab list, the arrow
// keys move between tabs and Enter or Space opens one.
const props = defineProps<{
  projectId: number
  layout: BoardLayout
  changes: Change[]
  // The change shown, or null for the tasks in no change.
  shown: ChangeReference | null
  panelId: string
}>()
const emit = defineEmits<{ new: [] }>()

interface Tab {
  id: string
  label: string
  tab: BoardTab
  selected: boolean
  phase: ChangePhase | null
  waiting: boolean
}

const tabs = computed<Tab[]>(() => [
  ...props.changes.map((change) => {
    const selected = props.shown?.id === change.id
    return {
      id: changeTabId(change),
      label: change.name,
      tab: { kind: "change", name: change.name } as BoardTab,
      selected,
      phase: change.phase,
      waiting: change.waiting_for_people,
    }
  }),
  {
    id: changeTabId(null), label: t("board.tabs.otherTasks"), tab: { kind: "other" }, selected: props.shown === null, phase: null, waiting: false,
  },
])

// While tabs are hidden past the end of the row, the row fades into "New
// change"; scrolled to its end, nothing fades over the last tab.
const list = ref<HTMLElement>()
const moreAfter = ref(false)

function measure() {
  const row = list.value
  moreAfter.value = Boolean(row && row.scrollLeft + row.clientWidth < row.scrollWidth - 1)
}

let resizes: ResizeObserver | undefined
onMounted(() => {
  measure()
  if (typeof ResizeObserver === "undefined" || !list.value) return
  resizes = new ResizeObserver(measure)
  resizes.observe(list.value)
})
onBeforeUnmount(() => resizes?.disconnect())
watch(tabs, () => nextTick(measure))

// The row scrolls without a scrollbar: a mouse wheel over it scrolls it
// sideways, as a trackpad and the arrow keys do.
function onWheel(event: WheelEvent) {
  const row = list.value
  if (!row || row.scrollWidth <= row.clientWidth || Math.abs(event.deltaX) >= Math.abs(event.deltaY)) return
  event.preventDefault()
  row.scrollLeft += event.deltaY
}

function onKey(event: KeyboardEvent) {
  const items = [...(event.currentTarget as HTMLElement).querySelectorAll<HTMLElement>('[role="tab"]')]
  const index = items.indexOf(document.activeElement as HTMLElement)
  const target = index === -1 ? undefined : ({ ArrowRight: index + 1, ArrowLeft: index - 1, Home: 0, End: items.length - 1 } as Record<string, number>)[event.key]
  if (target === undefined) return
  event.preventDefault()
  items[(target + items.length) % items.length]?.focus()
}
</script>

<script lang="ts">
// The id of a change's tab, or of the tab of other tasks (null), which the
// board's tab panel is labelled by.
export function changeTabId(change: ChangeReference | null): string {
  return change ? `board-tab-${change.id}` : "board-tab-other"
}
</script>

<template>
  <div class="change-tabs">
    <div ref="list" role="tablist" :aria-label="t('board.tabs.label')" class="change-tabs__list" @keydown="onKey" @scroll.passive="measure" @wheel="onWheel">
      <RouterLink
        v-for="tab in tabs"
        :id="tab.id"
        :key="tab.id"
        :to="boardLocation(projectId, layout, tab.tab)"
        role="tab"
        class="change-tabs__tab"
        :aria-selected="tab.selected ? 'true' : 'false'"
        :aria-controls="panelId"
        :tabindex="tab.selected ? 0 : -1"
        @keydown.space.prevent="($event.currentTarget as HTMLElement).click()"
      >
        <span class="ellipsis">{{ tab.label }}</span>
        <WaitingMarker v-if="tab.waiting" />
        <PhasePill v-if="tab.phase" :phase="tab.phase" />
      </RouterLink>
    </div>
    <!-- An action, not a tab, styled as one at the end of the row. -->
    <button type="button" class="change-tabs__tab change-tabs__new" :class="{ 'change-tabs__new--fade': moreAfter }" @click="emit('new')">
      <AppIcon name="add" :size="18" />{{ t("board.tabs.newChange") }}
    </button>
  </div>
</template>

<style scoped>
/* On the board page's white band, whose bottom line the tabs stand on. */
.change-tabs {
  display: flex;
  align-items: flex-end;
  min-inline-size: 0;
}

.change-tabs__list {
  display: flex;
  min-inline-size: 0;
  overflow-x: auto;
  scrollbar-width: none;

  &::-webkit-scrollbar { display: none; }
}

.change-tabs__tab {
  display: inline-flex;
  flex: none;
  align-items: center;
  gap: var(--space-2);
  max-inline-size: 18rem;
  min-block-size: var(--target-size);
  margin-block-end: -1px;
  padding: var(--space-1) var(--space-3);
  border-block-end: 2px solid transparent;
  border-radius: var(--radius) var(--radius) 0 0;
  color: var(--color-muted);
  font-size: var(--text-sm);
  font-weight: 500;
  text-decoration: none;

  &:hover { background: var(--color-main-tint); color: var(--color-text); }

  /* The board's colour, joining the board below the band. */
  &[aria-selected="true"] {
    border-block-end-color: var(--color-primary);
    background: var(--color-background);
    color: var(--color-text);
  }
}

.change-tabs__new {
  position: relative;
  border-inline: none;
  border-block-start: none;
  background: none;
  font-family: inherit;
  cursor: pointer;
}

/* Over the end of the tab row, from the band's white at the button to
   transparent; the row's bottom line stays visible. */
.change-tabs__new--fade::before {
  position: absolute;
  inset-block: 0 1px;
  inset-inline-end: 100%;
  inline-size: 3rem;
  background: linear-gradient(to left, var(--color-surface), transparent);
  content: "";
  pointer-events: none;
}
</style>
