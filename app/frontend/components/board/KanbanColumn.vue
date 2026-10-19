<script setup lang="ts">
import { computed, nextTick, ref } from "vue"
import AppIcon from "../ui/AppIcon.vue"
import AppMenu from "../ui/AppMenu.vue"
import ConfirmDialog from "../ui/ConfirmDialog.vue"
import InlineEdit from "../ui/InlineEdit.vue"
import TaskCard from "./TaskCard.vue"
import type { Column, TaskCard as Card } from "../../api/types.ts"
import type { useDragSort } from "../../composables/useDragSort.ts"
import { useBoardStore } from "../../stores/board.ts"
import { useUiStore } from "../../stores/ui.ts"
import { t, tc } from "../../i18n/index.ts"

const props = defineProps<{
  column: Column
  tasks: Card[]
  projectId: number
  cardDrag: ReturnType<typeof useDragSort>
  onTaskKey: (event: KeyboardEvent, task: Card) => void
  onColumnKey: (event: KeyboardEvent, column: Column) => void
}>()
defineSlots<{ "column-handle"(): unknown }>()

const board = useBoardStore()
const ui = useUiStore()
const renaming = ref(false)
const confirmingDelete = ref(false)
const adding = ref(false)
const newTitle = ref("")
const newInput = ref<HTMLInputElement>()
const indicator = computed(() => props.cardDrag.indicatorIn(props.column.id, props.tasks.map((task) => task.id)))

async function rename(title: string) {
  await board.renameColumn(props.column.id, title).catch(ui.fail)
}

async function startAdding() {
  adding.value = true
  await nextTick()
  newInput.value?.focus()
}

async function addTask() {
  const title = newTitle.value.trim()
  if (!title) return
  try {
    await board.createTask({ title, status_id: props.column.id })
    newTitle.value = ""
  } catch (error) {
    ui.fail(error)
  }
}
</script>

<template>
  <section class="column" :aria-labelledby="`column-${column.id}`">
    <header class="column__header" @keydown="onColumnKey($event, column)">
      <slot name="column-handle" />
      <InlineEdit v-model:editing="renaming" :value="column.title" :label="t('board.columnTitle')" @commit="rename" />
      <h2 v-show="!renaming" :id="`column-${column.id}`" class="column__title ellipsis" tabindex="0" :aria-describedby="`column-hint-${column.id}`">{{ column.title }}</h2>
      <span :id="`column-hint-${column.id}`" class="visually-hidden">{{ t("board.columnKeyboardHint") }}</span>
      <span v-show="!renaming" class="column__count small muted">{{ tc("board.taskCount", tasks.length) }}</span>
      <button type="button" class="icon-button" :aria-label="t('board.addTask', { title: column.title })" @click="startAdding">
        <AppIcon name="add" />
      </button>
      <AppMenu :label="t('board.columnActions', { title: column.title })" align="end">
        <template #trigger="{ id, expanded }">
          <button type="button" class="icon-button" :popovertarget="id" :aria-expanded="expanded" :aria-label="t('board.columnActions', { title: column.title })">
            <AppIcon name="more_vert" />
          </button>
        </template>
        <template #default="{ close }">
          <button type="button" class="menu__item" @click="close(); renaming = true"><AppIcon name="edit" />{{ t("board.renameColumn") }}</button>
          <button type="button" class="menu__item" @click="close(); confirmingDelete = true"><AppIcon name="delete" />{{ t("board.deleteColumn") }}</button>
        </template>
      </AppMenu>
    </header>

    <form v-if="adding" class="column__new" @submit.prevent="addTask">
      <input
        ref="newInput"
        v-model="newTitle"
        class="input"
        maxlength="255"
        :aria-label="t('board.taskTitle')"
        :placeholder="t('board.taskTitle')"
        @keydown.esc="adding = false"
        @blur="!newTitle.trim() && (adding = false)"
      >
    </form>

    <ol role="list" class="column__cards" v-bind="cardDrag.container(column.id)">
      <template v-for="(task, index) in tasks" :key="task.id">
        <li v-if="indicator?.beforeId === task.id" class="drop-indicator" aria-hidden="true" />
        <li
          data-drag-item="card"
          :data-drag-id="task.id"
          class="column__card"
          :class="{ 'is-dragging': cardDrag.draggingId.value === task.id }"
          :style="{ viewTransitionName: `card-${task.id}` }"
          @keydown="onTaskKey($event, task)"
        >
          <TaskCard
            :task="task"
            :project-id="projectId"
            :described-by="`card-hint-${column.id}`"
            :assignee="task.assignee_id ? board.memberById.get(task.assignee_id) ?? null : null"
            :label="task.label_id ? board.labelById.get(task.label_id) ?? null : null"
          >
            <template #handle>
              <span class="drag-handle" v-bind="cardDrag.handle(task.id, column.id, index)" :title="t('board.moveHandle', { key: task.key })" aria-hidden="true">
                <AppIcon name="drag_indicator" :size="18" />
              </span>
            </template>
          </TaskCard>
        </li>
      </template>
      <li v-if="indicator && indicator.beforeId === null" class="drop-indicator" aria-hidden="true" />
    </ol>
    <p v-if="!tasks.length && !adding" class="column__empty small muted">{{ t("board.emptyColumn") }}</p>
    <span :id="`card-hint-${column.id}`" class="visually-hidden">{{ t("board.keyboardHint") }}</span>

    <ConfirmDialog
      v-model:open="confirmingDelete"
      :title="t('board.deleteColumn')"
      :message="t('board.deleteColumnConfirm', { title: column.title })"
      :confirm-label="t('common.delete')"
      danger
      :on-confirm="() => board.deleteColumn(column.id).catch(ui.fail)"
    />
  </section>
</template>

<style scoped>
.column {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  inline-size: var(--column-width);
  flex: none;
  padding: var(--space-2);
  border-radius: var(--radius);
  background: rgb(235 236 240 / 0.55);
}

.column__header {
  display: flex;
  align-items: center;
  gap: var(--space-1);
  min-block-size: var(--target-size);
  padding-inline-start: var(--space-2);
}

.column__title { flex-grow: 1; font-size: var(--text-md); }
.column__count { flex: none; }

.column__cards {
  display: grid;
  gap: var(--space-2);
  align-content: start;
  min-block-size: 48px;
}

.column__empty { padding: var(--space-2); text-align: center; }

.column__card.is-dragging { opacity: 0.4; }
</style>
