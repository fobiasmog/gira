<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue"
import { storeToRefs } from "pinia"
import AppIcon from "../components/ui/AppIcon.vue"
import KanbanColumn from "../components/board/KanbanColumn.vue"
import BoardList from "../components/board/BoardList.vue"
import { useDragSort, type DragMove } from "../composables/useDragSort.ts"
import { useBoardMove } from "../composables/useBoardMove.ts"
import { useKeyboardMoves } from "../composables/useKeyboardMoves.ts"
import { useBoardStore } from "../stores/board.ts"
import { useProjectsStore } from "../stores/projects.ts"
import { useUiStore } from "../stores/ui.ts"
import { t } from "../i18n/index.ts"

const props = defineProps<{ projectId: number; layout: "kanban" | "list" }>()
const board = useBoardStore()
const { columns, activeSprint } = storeToRefs(board)
const projects = useProjectsStore()
const ui = useUiStore()
const loaded = ref(false)
const project = computed(() => projects.list.find((p) => p.id === props.projectId) ?? null)

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
    <header class="page__header">
      <h1 class="ellipsis">{{ project?.title }}</h1>
      <span v-if="activeSprint" class="chip">{{ t("board.activeSprint", { title: activeSprint.title }) }}</span>
      <span class="grow" />
      <nav class="segmented" :aria-label="t('board.layout')">
        <RouterLink :to="{ name: 'board', params: { pid: projectId } }" :aria-current="layout === 'kanban' ? 'page' : undefined">
          <AppIcon name="view_kanban" :size="20" />{{ t("navigation.board") }}
        </RouterLink>
        <RouterLink :to="{ name: 'board-list', params: { pid: projectId } }" :aria-current="layout === 'list' ? 'page' : undefined">
          <AppIcon name="view_list" :size="20" />{{ t("navigation.list") }}
        </RouterLink>
      </nav>
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
        <button v-else type="button" class="button button--text" @click="startAddingColumn">
          <AppIcon name="add" />{{ t("board.addColumn") }}
        </button>
      </div>
    </div>
  </section>
</template>

<style scoped>
.board-page { block-size: 100%; grid-template-rows: auto 1fr; }

.board {
  display: flex;
  align-items: flex-start;
  gap: var(--space-3);
  overflow-x: auto;
  padding-block-end: var(--space-3);
}

.board__column { flex: none; }
.board__column.is-dragging { opacity: 0.4; }

.board__add {
  flex: none;
  inline-size: var(--column-width);
  padding: var(--space-2);
}
</style>
