<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue"
import { storeToRefs } from "pinia"
import AppIcon from "../components/ui/AppIcon.vue"
import KanbanColumn from "../components/board/KanbanColumn.vue"
import BoardList from "../components/board/BoardList.vue"
import ProgressBar from "../components/ProgressBar.vue"
import { useDragSort, type DragMove } from "../composables/useDragSort.ts"
import { sprintSummary } from "../composables/sprintSummary.ts"
import { useBoardMove } from "../composables/useBoardMove.ts"
import { useKeyboardMoves } from "../composables/useKeyboardMoves.ts"
import { useBoardStore } from "../stores/board.ts"
import { useProjectsStore } from "../stores/projects.ts"
import { useUiStore } from "../stores/ui.ts"
import { language, t, tc } from "../i18n/index.ts"
import { formatDateRange } from "../i18n/format.ts"

const props = defineProps<{ projectId: number; layout: "kanban" | "list" }>()
const board = useBoardStore()
const { columns, activeSprint } = storeToRefs(board)
const projects = useProjectsStore()
const ui = useUiStore()
const loaded = ref(false)
const project = computed(() => projects.list.find((p) => p.id === props.projectId) ?? null)

const summary = computed(() => {
  const sprint = activeSprint.value
  if (!sprint) return null
  const progress = sprintSummary(sprint, columns.value, board.tasks, new Date())
  return {
    ...progress,
    range: formatDateRange(language.value, sprint.starts_on, sprint.ends_on),
    progressText: t("board.sprint.progress", { done: progress.done, total: progress.total }),
    timeText: progress.state === "running" ? tc("board.sprint.daysLeft", progress.daysLeft)
      : progress.state === "last-day" ? t("board.sprint.lastDay") : t("board.sprint.ended"),
  }
})

// "New task" opens the add field of the first column.
const columnRefs = new Map<number, InstanceType<typeof KanbanColumn>>()
function setColumnRef(id: number, instance: unknown) {
  if (instance) columnRefs.set(id, instance as InstanceType<typeof KanbanColumn>)
  else columnRefs.delete(id)
}
function newTask() {
  const first = columns.value[0]
  if (first) void columnRefs.get(first.id)?.startAdding()
}

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

watch(() => props.projectId, async (id) => {
  loaded.value = false
  await ui.load(board.load(id))
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
</script>

<template>
  <section v-if="loaded" class="page page--full board-page">
    <header class="board-header">
      <div class="board-header__main">
        <h1 class="ellipsis">{{ project?.title }}</h1>
        <section v-if="activeSprint && summary" class="sprint-summary" :aria-label="t('board.sprint.label')">
          <AppIcon name="sprint" :size="18" class="sprint-summary__icon" />
          <RouterLink :to="{ name: 'sprints', params: { pid: projectId } }" class="sprint-summary__title">{{ activeSprint.title }}</RouterLink>
          <span class="sprint-summary__dates">{{ summary.range }}</span>
          <span class="sprint-summary__progress">
            <ProgressBar :done="summary.done" :total="summary.total" :label="summary.progressText" class="sprint-summary__bar" />
            <span>{{ summary.progressText }}</span>
          </span>
          <span class="sprint-summary__time" :class="`sprint-summary__time--${summary.state}`">{{ summary.timeText }}</span>
        </section>
      </div>
      <div class="board-header__actions">
        <nav class="segmented" :aria-label="t('board.layout')">
          <RouterLink :to="{ name: 'board', params: { pid: projectId } }" :aria-current="layout === 'kanban' ? 'page' : undefined">
            <AppIcon name="view_kanban" :size="18" />{{ t("navigation.board") }}
          </RouterLink>
          <RouterLink :to="{ name: 'board-list', params: { pid: projectId } }" :aria-current="layout === 'list' ? 'page' : undefined">
            <AppIcon name="view_list" :size="18" />{{ t("navigation.list") }}
          </RouterLink>
        </nav>
        <button v-if="layout === 'kanban' && columns.length" type="button" class="button" @click="newTask">
          <AppIcon name="add" :size="20" />{{ t("board.newTask") }}
        </button>
      </div>
    </header>

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
            :ref="(instance) => setColumnRef(column.id, instance)"
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
  </section>
</template>

<style scoped>
.board-page { block-size: 100%; grid-template-rows: auto 1fr; }

.board-header {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--space-3) var(--space-5);
}

.board-header__main { display: grid; gap: var(--space-2); min-inline-size: 0; }
.board-header__actions { display: flex; flex-wrap: wrap; align-items: center; gap: var(--space-3); }

.sprint-summary {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-1) var(--space-3);
  color: var(--color-muted);
  font-size: var(--text-sm);
}

.sprint-summary__icon { color: var(--color-primary); }

.sprint-summary__title {
  color: var(--color-text);
  font-weight: 500;
  text-decoration: none;

  &:hover { color: var(--color-primary); text-decoration: underline; }
}

.sprint-summary__progress { display: inline-flex; align-items: center; gap: var(--space-2); }
.sprint-summary__bar { inline-size: 120px; }
.sprint-summary__time { color: var(--color-text); font-weight: 500; }
.sprint-summary__time--ended { color: var(--color-overdue); }

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
