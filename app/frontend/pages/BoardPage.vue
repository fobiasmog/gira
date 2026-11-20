<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue"
import { storeToRefs } from "pinia"
import { useRouter } from "vue-router"
import AppIcon from "../components/ui/AppIcon.vue"
import KanbanColumn from "../components/board/KanbanColumn.vue"
import BoardList from "../components/board/BoardList.vue"
import ChangeTabs, { changeTabId } from "../components/changes/ChangeTabs.vue"
import ChangeSummary from "../components/changes/ChangeSummary.vue"
import NewChangeDialog from "../components/changes/NewChangeDialog.vue"
import type { Change } from "../api/types.ts"
import { useDragSort, type DragMove } from "../composables/useDragSort.ts"
import { useBoardMove } from "../composables/useBoardMove.ts"
import { useKeyboardMoves } from "../composables/useKeyboardMoves.ts"
import { boardLocation, type BoardLayout } from "../router/routes.ts"
import { useBoardStore, type BoardTab } from "../stores/board.ts"
import { useProjectsStore } from "../stores/projects.ts"
import { useUiStore } from "../stores/ui.ts"
import { t } from "../i18n/index.ts"

// The board of one change, or of the tasks in no change, picked from a row of
// tabs (spec web-client, "Board change tabs" and "Board change summary").
const props = defineProps<{ projectId: number; layout: BoardLayout; tab: BoardTab }>()
const router = useRouter()
const board = useBoardStore()
const { columns, change, changes, missingChange } = storeToRefs(board)
const projects = useProjectsStore()
const ui = useUiStore()
const loaded = ref(false)
const project = computed(() => projects.list.find((p) => p.id === props.projectId) ?? null)
const panelId = "board-panel"

const boardElement = ref<HTMLElement>()
const runMove = useBoardMove()
const cardDrag = useDragSort({
  group: "card",
  axis: "y",
  scroller: () => boardElement.value,
  onMove: (move: DragMove) => runMove(() => board.moveTask(move.id, Number(move.to), move.toIndex)),
})
const columnDrag = useDragSort({
  group: "column",
  axis: "x",
  scroller: () => boardElement.value,
  onMove: (move: DragMove) => runMove(() => board.moveColumn(move.id, move.toIndex)),
})
const { onTaskKey, onColumnKey } = useKeyboardMoves()
const columnIndicator = computed(() => columnDrag.indicatorIn("board", columns.value.map((column) => column.id)))

const addingColumn = ref(false)
const columnTitle = ref("")
const columnInput = ref<HTMLInputElement>()

async function startAddingColumn() {
  addingColumn.value = true
  await nextTick()
  columnInput.value?.focus()
}

// Another project hides the page while it loads; another tab of the same
// project keeps the page and swaps the board.
watch(() => [props.projectId, JSON.stringify(props.tab)] as const, async ([id], previous) => {
  if (previous?.[0] !== id) loaded.value = false
  await ui.load(board.load(id, props.tab))
  loaded.value = board.projectId === id
}, { immediate: true })

async function addColumn() {
  const title = columnTitle.value.trim()
  if (!title) return
  try {
    await board.addColumn(title)
    columnTitle.value = ""
    addingColumn.value = false
  } catch (error) {
    ui.fail(error)
  }
}

const creatingChange = ref(false)

async function showCreated(created: Change) {
  ui.toast(t("changes.created", { name: created.name }))
  await router.push(boardLocation(props.projectId, props.layout, { kind: "change", name: created.name }))
}
</script>

<template>
  <section v-if="loaded" class="page page--full board-page">
    <div class="board-top">
      <header class="board-header">
        <h1 class="ellipsis">{{ project?.title }}</h1>
        <!-- No layout switch and no "New task" for now: tasks are added in
             their column, and the list layout is reached only by its address
             (spec web-client, "Screens"). -->
      </header>

      <ChangeTabs
        :project-id="projectId"
        :layout="layout"
        :changes="changes"
        :shown="change"
        :panel-id="panelId"
        @new="creatingChange = true"
      />
    </div>

    <div :id="panelId" role="tabpanel" :aria-labelledby="changeTabId(change)" class="board-panel">
      <p v-if="missingChange" class="notice" role="status">{{ t("board.tabs.missing", { name: missingChange }) }}</p>
      <ChangeSummary
        v-if="change"
        :project-id="projectId"
        :change="change"
        :columns="columns"
        :tasks="board.tasks"
      />

      <BoardList v-if="layout === 'list'" :project-id="projectId" />
      <div v-else ref="boardElement" class="board" v-bind="columnDrag.container('board')">
        <template v-for="(column, index) in columns" :key="column.id">
          <div v-if="columnIndicator?.beforeId === column.id" class="drop-indicator drop-indicator--vertical" aria-hidden="true" />
          <div
            data-drag-item="column"
            :data-drag-id="column.id"
            class="board__column"
            :class="{ 'is-dragging': columnDrag.draggingId.value === column.id }"
            :style="{ viewTransitionName: `column-${column.id}` }"
          >
            <KanbanColumn
              :column="column"
              :tasks="board.tasksIn(column.id)"
              :project-id="projectId"
              :card-drag="cardDrag"
              :on-task-key="onTaskKey"
              :on-column-key="onColumnKey"
            >
              <template #column-handle>
                <span class="drag-handle" v-bind="columnDrag.handle(column.id, 'board', index)" :title="t('board.moveColumnHandle', { title: column.title })" aria-hidden="true">
                  <AppIcon name="drag_indicator" :size="18" />
                </span>
              </template>
            </KanbanColumn>
          </div>
        </template>
        <div v-if="columnIndicator && columnIndicator.beforeId === null" class="drop-indicator drop-indicator--vertical" aria-hidden="true" />
        <div class="board__add">
          <form v-if="addingColumn" class="stack" @submit.prevent="addColumn">
            <input
              ref="columnInput"
              v-model="columnTitle"
              class="input"
              maxlength="255"
              :aria-label="t('board.columnTitle')"
              :placeholder="t('board.columnTitle')"
              @keydown.esc="addingColumn = false"
            >
            <div class="row">
              <button type="submit" class="button">{{ t("common.create") }}</button>
              <button type="button" class="button button--text" @click="addingColumn = false">{{ t("common.cancel") }}</button>
            </div>
          </form>
          <button v-else type="button" class="board__add-button" @click="startAddingColumn">
            <AppIcon name="add" :size="20" />{{ t("board.addColumn") }}
          </button>
        </div>
      </div>
    </div>

    <NewChangeDialog v-model:open="creatingChange" :project-id="projectId" :create="board.createChange" @created="showCreated" />
  </section>
</template>

<style scoped>
.board-page { block-size: 100%; grid-template-rows: auto 1fr; gap: var(--space-4); }

/* The page header and the tabs on one white band across the content's
   padding (AppShell.vue's .shell__content), down to the tabs' bottom line;
   the shown tab takes the board's colour below. Up to the top bar unless an
   announcement stands above the page. */
.board-top {
  display: grid;
  gap: var(--space-4);
  margin-inline: calc(-1 * var(--space-4));
  padding: var(--space-4) var(--space-4) 0;
  border-block-end: 1px solid var(--color-border);
  background: var(--color-surface);
}

.board-page:first-child > .board-top {
  margin-block-start: calc(-1 * var(--space-5));
  padding-block-start: var(--space-5);
}

@media (min-width: 1024px) {
  .board-top { margin-inline: calc(-1 * var(--space-6)); padding-inline: var(--space-6); }
}

.board-header {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3) var(--space-5);
}


/* The board fills what the tabs and the summary leave. */
.board-panel {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
  min-block-size: 0;
}

.board-panel > .board { flex: 1 1 auto; }

.notice { margin: 0; padding: var(--space-2) var(--space-3); border-radius: var(--radius); background: var(--color-main-lighter); color: var(--color-main-darker); }

/* Positioned, so absolutely positioned descendants (visually hidden text)
   scroll with the board instead of widening the page. */
.board {
  position: relative;
  display: flex;
  align-items: flex-start;
  gap: var(--space-4);
  overflow-x: auto;
  padding-block-end: var(--space-3);
}

.board__column { flex: none; }
.board__column.is-dragging { opacity: 0.4; }

.board__add {
  flex: none;
  inline-size: var(--column-width);
}

.board__add-button {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-2);
  inline-size: 100%;
  min-block-size: 44px;
  padding: var(--space-2) var(--space-3);
  border: 1px dashed var(--color-control-border);
  border-radius: var(--radius-card);
  background: none;
  color: var(--color-muted);
  font-size: var(--text-sm);
  font-weight: 500;

  &:hover { border-color: var(--color-primary); background: var(--color-main-tint); color: var(--color-primary); }
}
</style>
