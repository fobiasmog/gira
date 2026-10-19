<script setup lang="ts">
import { ref, watch } from "vue"
import { storeToRefs } from "pinia"
import AppIcon from "../components/ui/AppIcon.vue"
import AppMenu from "../components/ui/AppMenu.vue"
import TaskRow from "../components/board/TaskRow.vue"
import StatusDot from "../components/board/StatusDot.vue"
import type { Column, TaskCard } from "../api/types.ts"
import { useBacklogStore } from "../stores/backlog.ts"
import { useBoardStore } from "../stores/board.ts"
import { useUiStore } from "../stores/ui.ts"
import { t } from "../i18n/index.ts"

const props = defineProps<{ projectId: number }>()
const backlog = useBacklogStore()
const { tasks } = storeToRefs(backlog)
const board = useBoardStore()
const ui = useUiStore()
const loaded = ref(false)
const newTitle = ref("")

watch(() => props.projectId, async (id) => {
  loaded.value = false
  await ui.load(Promise.all([backlog.load(id), board.load(id)]))
  loaded.value = backlog.projectId === id && board.projectId === id
}, { immediate: true })

async function create() {
  const title = newTitle.value.trim()
  if (!title) return
  try {
    await backlog.create(props.projectId, title)
    newTitle.value = ""
  } catch (error) {
    ui.fail(error)
  }
}

async function place(task: TaskCard, column: Column) {
  try {
    await backlog.placeOnColumn(props.projectId, task.id, column.id, board.tasksIn(column.id).length)
    ui.toast(t("backlog.placed", { key: task.key, column: column.title }))
  } catch (error) {
    ui.fail(error)
  }
}
</script>

<template>
  <section v-if="loaded" class="page backlog-page">
    <header class="backlog-page__intro">
      <h1 class="backlog-page__title">{{ t("backlog.title") }} <span class="badge">{{ tasks.length }}</span></h1>
      <p class="muted">{{ t("backlog.info") }}</p>
    </header>

    <form class="new-bar" @submit.prevent="create">
      <AppIcon name="add" :size="20" class="new-bar__icon" />
      <input v-model="newTitle" class="input new-bar__input" maxlength="255" :aria-label="t('backlog.newTask')" :placeholder="t('backlog.newTask')">
      <button type="submit" class="button">{{ t("common.create") }}</button>
    </form>

    <ol v-if="tasks.length" role="list" class="backlog row-list">
      <li v-for="task in tasks" :key="task.id">
        <TaskRow
          :task="task"
          :project-id="projectId"
          :assignee="task.assignee_id ? board.memberById.get(task.assignee_id) ?? null : null"
          :label="task.label_id ? board.labelById.get(task.label_id) ?? null : null"
        >
          <template #actions>
            <AppMenu :label="t('backlog.placeOnBoard', { key: task.key })" align="end">
              <template #trigger="{ id, expanded }">
                <button
                  type="button"
                  class="button button--secondary to-board"
                  :popovertarget="id"
                  :aria-expanded="expanded"
                  :aria-label="t('backlog.placeOnBoard', { key: task.key })"
                >
                  <AppIcon name="view_kanban" :size="18" />{{ t("backlog.toBoard") }}<AppIcon name="expand_more" :size="18" />
                </button>
              </template>
              <template #default="{ close }">
                <button v-for="column in board.columns" :key="column.id" type="button" class="menu__item" @click="close(); place(task, column)">
                  <StatusDot :column="column" />{{ t("backlog.placeIn", { column: column.title }) }}
                </button>
              </template>
            </AppMenu>
          </template>
        </TaskRow>
      </li>
    </ol>
    <p v-else class="empty-state panel">{{ t("backlog.empty") }}</p>
  </section>
</template>

<style scoped>
.backlog-page { max-inline-size: 1040px; gap: var(--space-4); }
.backlog-page__intro { display: grid; gap: var(--space-2); }
.backlog-page__title { display: flex; align-items: center; gap: var(--space-2); }
.backlog-page__title .badge { font-size: var(--text-sm); }

/* The new-task field and its button as one bar; the bar is the field's
   visible boundary, so it takes the control border and the focus ring. */
.new-bar {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  padding: var(--space-1) var(--space-1) var(--space-1) var(--space-3);
  border: 1px solid var(--color-control-border);
  border-radius: var(--radius-card);
  background: var(--color-surface);

  &:hover { border-color: var(--color-main-dark); }
  &:has(.new-bar__input:focus-visible) { outline: 2px solid var(--color-focus); outline-offset: 0; border-color: var(--color-primary); }
}

.new-bar__icon { color: var(--color-muted); }

.new-bar__input,
.new-bar__input:hover,
.new-bar__input:focus-visible,
.new-bar__input:focus-within {
  flex-grow: 1;
  padding-inline: 0;
  border: none;
  outline: none;
  background: none;
}

.to-board { --target-size: 32px; padding: var(--space-1) var(--space-2); gap: var(--space-1); }
</style>
