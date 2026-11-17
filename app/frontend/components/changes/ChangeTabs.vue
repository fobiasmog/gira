<script setup lang="ts">
import { computed } from "vue"
import AppIcon from "../ui/AppIcon.vue"
import type { Change, ChangeReference, Column, TaskCard } from "../../api/types.ts"
import { boardProgress, countsProgress, type ChangeProgress } from "../../composables/changes.ts"
import { boardLocation, type BoardLayout } from "../../router/routes.ts"
import type { BoardTab } from "../../stores/board.ts"
import { t } from "../../i18n/index.ts"

// The board's tabs (spec web-client, "Board change tabs"): one per open
// change, newest first, then the tasks in no change, then "New change". Each
// tab is a link, so the address names the tab; as in any tab list, the arrow
// keys move between tabs and Enter or Space opens one.
const props = defineProps<{
  projectId: number
  layout: BoardLayout
  changes: Change[]
  // The change shown, or null for the tasks in no change.
  shown: ChangeReference | null
  columns: Column[]
  // The cards on the board, which count for the change shown.
  tasks: TaskCard[]
  panelId: string
}>()
const emit = defineEmits<{ new: [] }>()

interface Tab {
  id: string
  label: string
  tab: BoardTab
  selected: boolean
  progress: ChangeProgress | null
}

const tabs = computed<Tab[]>(() => [
  ...props.changes.map((change) => {
    const selected = props.shown?.id === change.id
    return {
      id: changeTabId(change),
      label: change.name,
      tab: { kind: "change", name: change.name } as BoardTab,
      selected,
      progress: selected ? boardProgress(props.columns, props.tasks) : countsProgress(props.columns, change.task_counts),
    }
  }),
  { id: changeTabId(null), label: t("board.tabs.otherTasks"), tab: { kind: "other" }, selected: props.shown === null, progress: null },
])

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
    <div role="tablist" :aria-label="t('board.tabs.label')" class="change-tabs__list" @keydown="onKey">
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
        <span v-if="tab.progress" class="change-tabs__count">
          <span aria-hidden="true">{{ tab.progress.done }}/{{ tab.progress.total }}</span>
          <span class="visually-hidden">{{ t("board.tabs.progress", { done: tab.progress.done, total: tab.progress.total }) }}</span>
        </span>
      </RouterLink>
    </div>
    <button type="button" class="button button--text change-tabs__new" @click="emit('new')">
      <AppIcon name="add" :size="20" />{{ t("board.tabs.newChange") }}
    </button>
  </div>
</template>

<style scoped>
.change-tabs {
  display: flex;
  align-items: flex-end;
  gap: var(--space-2);
  min-inline-size: 0;
  border-block-end: 1px solid var(--color-border);
}

.change-tabs__list {
  display: flex;
  min-inline-size: 0;
  overflow-x: auto;
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
  border-radius: var(--radius-sm) var(--radius-sm) 0 0;
  color: var(--color-muted);
  font-size: var(--text-sm);
  font-weight: 500;
  text-decoration: none;

  &:hover { background: var(--color-main-tint); color: var(--color-text); }

  &[aria-selected="true"] {
    border-block-end-color: var(--color-primary);
    color: var(--color-text);
  }
}

.change-tabs__count {
  flex: none;
  padding: 0 var(--space-1);
  border-radius: var(--radius-sm);
  background: var(--color-badge);
  color: var(--color-badge-text);
  font-size: var(--text-xs);
}

.change-tabs__new { flex: none; margin-block-end: var(--space-1); }
</style>
