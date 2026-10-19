<script setup lang="ts">
import { ref, watch } from "vue"
import { storeToRefs } from "pinia"
import AppIcon from "../components/ui/AppIcon.vue"
import AppMenu from "../components/ui/AppMenu.vue"
import TaskRow from "../components/board/TaskRow.vue"
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
  <section v-if="loaded" class="page">
    <header class="page__header">
      <h1>{{ t("backlog.title") }}</h1>
    </header>
    <p class="muted">{{ t("backlog.info") }}</p>

    <form class="row" @submit.prevent="create">
      <input v-model="newTitle" class="input grow" maxlength="255" :aria-label="t('backlog.newTask')" :placeholder="t('backlog.newTask')">
      <button type="submit" class="button"><AppIcon name="add" />{{ t("common.create") }}</button>
    </form>

    <ol v-if="tasks.length" role="list" class="backlog">
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
                <button type="button" class="icon-button" :popovertarget="id" :aria-expanded="expanded" :aria-label="t('backlog.placeOnBoard', { key: task.key })">
                  <AppIcon name="view_kanban" :size="20" />
                </button>
              </template>
              <template #default="{ close }">
                <button v-for="column in board.columns" :key="column.id" type="button" class="menu__item" @click="close(); place(task, column)">
                  {{ t("backlog.placeIn", { column: column.title }) }}
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
.backlog { display: grid; gap: var(--space-1); }
</style>
