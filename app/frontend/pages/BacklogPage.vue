<script setup lang="ts">
import { computed, ref, watch } from "vue"
import { storeToRefs } from "pinia"
import AppIcon from "../components/ui/AppIcon.vue"
import AppMenu from "../components/ui/AppMenu.vue"
import TaskRow from "../components/board/TaskRow.vue"
import StatusDot from "../components/board/StatusDot.vue"
import type { Column, Sprint, TaskCard } from "../api/types.ts"
import { useBacklogStore } from "../stores/backlog.ts"
import { useBoardStore } from "../stores/board.ts"
import { useSprintsStore } from "../stores/sprints.ts"
import { useUiStore } from "../stores/ui.ts"
import { t } from "../i18n/index.ts"

// Open tasks in no sprint, each with its column, and the done ones below.
// Each task moves into an open sprint or, while a sprint is active, onto the
// board (spec web-client, "Backlog screen").
const props = defineProps<{ projectId: number }>()
const backlog = useBacklogStore()
const { tasks, done } = storeToRefs(backlog)
const board = useBoardStore()
const { activeSprint } = storeToRefs(board)
const sprintsStore = useSprintsStore()
const { sprints } = storeToRefs(sprintsStore)
const ui = useUiStore()
const loaded = ref(false)
const newTitle = ref("")

watch(() => props.projectId, async (id) => {
  loaded.value = false
  await ui.load(Promise.all([backlog.load(id), board.load(id), sprintsStore.load(id)]))
  loaded.value = backlog.projectId === id && board.projectId === id && sprintsStore.projectId === id
}, { immediate: true })

const columnById = computed(() => new Map(board.columns.map((column) => [column.id, column])))

const rowProps = (task: TaskCard) => ({
  task,
  projectId: props.projectId,
  column: columnById.value.get(task.status_id) ?? null,
  assignee: task.assignee_id ? board.memberById.get(task.assignee_id) ?? null : null,
  label: task.label_id ? board.labelById.get(task.label_id) ?? null : null,
})

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

// The board follows along, so it shows the task when it joins the active sprint.
async function moveToSprint(task: TaskCard, sprint: Sprint) {
  try {
    board.upsertCard(await backlog.moveToSprint(props.projectId, task.id, sprint.id))
    ui.toast(t("backlog.movedToSprint", { key: task.key, sprint: sprint.title }))
  } catch (error) {
    ui.fail(error)
  }
}

// To the end of the column, in the active sprint.
async function place(task: TaskCard, column: Column) {
  const sprint = activeSprint.value
  if (!sprint) return
  try {
    board.upsertCard(await backlog.placeOnColumn(props.projectId, task.id, column.id, board.tasksIn(column.id).length, sprint.id))
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
        <TaskRow v-bind="rowProps(task)">
          <template #actions>
            <AppMenu :label="t('backlog.moveTask', { key: task.key })" align="end">
              <template #trigger="{ id, expanded }">
                <button
                  type="button"
                  class="button button--secondary move-button"
                  :popovertarget="id"
                  :aria-expanded="expanded"
                  :aria-label="t('backlog.moveTask', { key: task.key })"
                >
                  {{ t("backlog.move") }}<AppIcon name="expand_more" :size="18" />
                </button>
              </template>
              <template #default="{ close }">
                <template v-if="sprints.length">
                  <p :id="`move-${task.id}-sprints`" class="menu__heading">{{ t("backlog.toSprint") }}</p>
                  <div role="group" :aria-labelledby="`move-${task.id}-sprints`">
                    <button v-for="sprint in sprints" :key="sprint.id" type="button" class="menu__item" @click="close(); moveToSprint(task, sprint)">
                      <AppIcon name="sprint" />{{ sprint.title }}
                    </button>
                  </div>
                </template>
                <template v-if="activeSprint">
                  <hr v-if="sprints.length" class="menu__separator">
                  <p :id="`move-${task.id}-board`" class="menu__heading">{{ t("backlog.toBoard") }}</p>
                  <div role="group" :aria-labelledby="`move-${task.id}-board`">
                    <button v-for="column in board.columns" :key="column.id" type="button" class="menu__item" @click="close(); place(task, column)">
                      <StatusDot :column="column" />{{ column.title }}
                    </button>
                  </div>
                </template>
                <p v-if="!sprints.length && !activeSprint" class="menu__heading">{{ t("backlog.noTargets") }}</p>
              </template>
            </AppMenu>
          </template>
        </TaskRow>
      </li>
    </ol>
    <p v-else class="empty-state panel">{{ t("backlog.empty") }}</p>

    <details v-if="done.length" class="done-group">
      <summary>{{ t("backlog.done", { count: done.length }) }}</summary>
      <ol role="list" class="row-list">
        <li v-for="task in done" :key="task.id">
          <TaskRow v-bind="rowProps(task)" />
        </li>
      </ol>
    </details>
  </section>
</template>

<style scoped>
.backlog-page { max-inline-size: 1040px; gap: var(--space-4); }
.backlog-page__intro { display: grid; gap: var(--space-2); }
.backlog-page__title { display: flex; align-items: center; gap: var(--space-2); }
.backlog-page__title .badge { font-size: var(--text-sm); }
.move-button { --target-size: 32px; padding: var(--space-1) var(--space-2); gap: var(--space-1); }
.done-group summary { cursor: pointer; font-weight: 500; }
.done-group ol { margin-block-start: var(--space-3); }
</style>
