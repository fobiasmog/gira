<script setup lang="ts">
import { computed } from "vue"
import { storeToRefs } from "pinia"
import AppIcon from "../ui/AppIcon.vue"
import AppMenu from "../ui/AppMenu.vue"
import TaskRow from "./TaskRow.vue"
import type { TaskCard } from "../../api/types.ts"
import { useDragSort, type DragMove } from "../../composables/useDragSort.ts"
import { useBoardMove } from "../../composables/useBoardMove.ts"
import { useKeyboardMoves } from "../../composables/useKeyboardMoves.ts"
import { useBoardStore } from "../../stores/board.ts"
import { useUiStore } from "../../stores/ui.ts"
import { t, tc } from "../../i18n/index.ts"

// The list layout: the board's tasks as rows grouped by column.
const props = defineProps<{ projectId: number }>()
const board = useBoardStore()
const { columns } = storeToRefs(board)
const ui = useUiStore()
const runMove = useBoardMove()
const { onTaskKey } = useKeyboardMoves()

const rowDrag = useDragSort({
  group: "row",
  axis: "y",
  onMove: (move: DragMove) => runMove(() => board.moveTask(move.id, Number(move.to), move.toIndex)),
})

const indicators = computed(() => new Map(columns.value.map((column) => [
  column.id,
  rowDrag.indicatorIn(column.id, board.tasksIn(column.id).map((task) => task.id)),
])))

async function sendToBacklog(task: TaskCard) {
  try {
    await board.sendToBacklog(task.id)
    ui.toast(t("board.sentToBacklog", { key: task.key }))
  } catch (error) {
    ui.fail(error)
  }
}
</script>

<template>
  <div class="board-list stack stack--lg">
    <span id="row-hint" class="visually-hidden">{{ t("board.keyboardHint") }}</span>
    <section v-for="column in columns" :key="column.id" class="board-list__group" :aria-labelledby="`group-${column.id}`">
      <header class="row">
        <h2 :id="`group-${column.id}`">{{ column.title }}</h2>
        <span class="small muted">{{ tc("board.taskCount", board.tasksIn(column.id).length) }}</span>
      </header>
      <ol role="list" class="board-list__rows" v-bind="rowDrag.container(column.id)">
        <template v-for="(task, index) in board.tasksIn(column.id)" :key="task.id">
          <li v-if="indicators.get(column.id)?.beforeId === task.id" class="drop-indicator" aria-hidden="true" />
          <li
            data-drag-item="row"
            :data-drag-id="task.id"
            :class="{ 'is-dragging': rowDrag.draggingId.value === task.id }"
            :style="{ viewTransitionName: `row-${task.id}` }"
            @keydown="onTaskKey($event, task)"
          >
            <TaskRow
              :task="task"
              :project-id="props.projectId"
              :assignee="task.assignee_id ? board.memberById.get(task.assignee_id) ?? null : null"
              :label="task.label_id ? board.labelById.get(task.label_id) ?? null : null"
              described-by="row-hint"
            >
              <template #handle>
                <span class="drag-handle" v-bind="rowDrag.handle(task.id, column.id, index)" :title="t('board.moveHandle', { key: task.key })" aria-hidden="true">
                  <AppIcon name="drag_indicator" :size="18" />
                </span>
              </template>
              <template #actions>
                <AppMenu :label="t('board.taskActions', { key: task.key })" align="end">
                  <template #trigger="{ id, expanded }">
                    <button type="button" class="icon-button" :popovertarget="id" :aria-expanded="expanded" :aria-label="t('board.taskActions', { key: task.key })">
                      <AppIcon name="more_vert" :size="20" />
                    </button>
                  </template>
                  <template #default="{ close }">
                    <button type="button" class="menu__item" @click="close(); sendToBacklog(task)">
                      <AppIcon name="inbox" />{{ t("board.sendToBacklog") }}
                    </button>
                  </template>
                </AppMenu>
              </template>
            </TaskRow>
          </li>
        </template>
        <li v-if="indicators.get(column.id)?.beforeId === null" class="drop-indicator" aria-hidden="true" />
      </ol>
    </section>
  </div>
</template>

<style scoped>
.board-list { max-inline-size: 960px; }
.board-list__group { display: grid; gap: var(--space-2); }
.board-list__group h2 { font-size: var(--text-md); }
.board-list__rows { display: grid; gap: var(--space-1); min-block-size: 44px; }
.is-dragging { opacity: 0.4; }
</style>
