<script setup lang="ts">
import { computed, ref, watch } from "vue"
import { storeToRefs } from "pinia"
import AppIcon from "../components/ui/AppIcon.vue"
import AppMenu from "../components/ui/AppMenu.vue"
import TaskRow from "../components/board/TaskRow.vue"
import ArchiveChangeDialog from "../components/changes/ArchiveChangeDialog.vue"
import NewChangeDialog from "../components/changes/NewChangeDialog.vue"
import type { Change, TaskCard } from "../api/types.ts"
import { countsProgress, unfinished } from "../composables/changes.ts"
import { boardLocation } from "../router/routes.ts"
import { OTHER_TAB, useBoardStore } from "../stores/board.ts"
import { useChangesStore } from "../stores/changes.ts"
import { useUiStore } from "../stores/ui.ts"
import { language, t, tc } from "../i18n/index.ts"
import { formatDate } from "../i18n/format.ts"

// The changes screen (spec web-client, "Changes screen"): each open change is
// a section listing its tasks, which can be added and moved between changes
// and out of them; archived changes are listed below.
const props = defineProps<{ projectId: number }>()
const store = useChangesStore()
const { open, archived } = storeToRefs(store)
const board = useBoardStore()
const ui = useUiStore()
const loaded = ref(false)

// Sections the viewer closed or opened again; open changes start open.
const toggled = ref(new Map<number, boolean>())
const isOpen = (change: Change) => toggled.value.get(change.id) ?? true

// The board store has the columns, members and labels rows show.
watch(() => props.projectId, async (id) => {
  loaded.value = false
  toggled.value = new Map()
  await ui.load(Promise.all([store.load(id), board.projectId === id ? Promise.resolve() : board.load(id, OTHER_TAB)]))
  loaded.value = store.projectId === id
}, { immediate: true })

// A section's tasks load the first time it is open, also after changes come
// and go.
watch([loaded, open], () => {
  if (loaded.value) for (const change of open.value) if (isOpen(change)) loadTasks(change)
})

async function loadTasks(change: Change) {
  try {
    await store.loadTasks(props.projectId, change.id)
  } catch (error) {
    ui.fail(error)
  }
}

function toggle(change: Change) {
  const opened = !isOpen(change)
  toggled.value.set(change.id, opened)
  if (opened) loadTasks(change)
}

function onArchivedToggle(change: Change, event: Event) {
  if ((event.target as HTMLDetailsElement).open) loadTasks(change)
}

// Task counts per column, in board order.
function counts(change: Change): { label: string; count: number }[] {
  const byStatus = change.task_counts.by_status
  return board.columns.map((column) => ({ label: column.title, count: byStatus[String(column.id)] ?? 0 })).filter((row) => row.count > 0)
}

const columnById = computed(() => new Map(board.columns.map((column) => [column.id, column])))
const isDone = (task: TaskCard) => columnById.value.get(task.status_id)?.done ?? false
const otherChanges = (change: Change) => open.value.filter((other) => other.id !== change.id)

// A done task shows a "Done" chip in place of its column.
const rowProps = (task: TaskCard) => ({
  task,
  projectId: props.projectId,
  column: isDone(task) ? null : columnById.value.get(task.status_id) ?? null,
  assignee: task.assignee_id ? board.memberById.get(task.assignee_id) ?? null : null,
  label: task.label_id ? board.labelById.get(task.label_id) ?? null : null,
})

// Changes answer with the task's card; a board of this project follows along.
function syncBoard(card: TaskCard) {
  if (board.projectId === props.projectId) board.upsertCard(card)
}

const newTitles = ref<Record<number, string>>({})

async function addTask(change: Change) {
  const title = (newTitles.value[change.id] ?? "").trim()
  if (!title) return
  try {
    syncBoard(await store.addTask(props.projectId, change.id, title))
    newTitles.value[change.id] = ""
  } catch (error) {
    ui.fail(error)
  }
}

// Into another open change, or out of its change (null).
async function moveTask(task: TaskCard, target: Change | null) {
  try {
    syncBoard(await store.moveTask(props.projectId, task.id, target?.id ?? null))
    ui.toast(target ? t("changes.movedTo", { key: task.key, name: target.name }) : t("changes.movedToOther", { key: task.key }))
  } catch (error) {
    ui.fail(error)
  }
}

const creating = ref(false)
const createChange = (name: string) => store.create(props.projectId, name)

// Archive dialog.
const archiving = ref<Change | null>(null)
const archiveOpen = computed({ get: () => archiving.value !== null, set: (value) => { if (!value) archiving.value = null } })
const unfinishedCards = computed(() => archiving.value ? unfinished(countsProgress(board.columns, archiving.value.task_counts)) : 0)

async function archive() {
  const change = archiving.value
  if (!change) return
  await store.archive(props.projectId, change.id)
  ui.toast(t("changes.archived", { name: change.name }))
}
</script>

<template>
  <section v-if="loaded" class="page changes-page">
    <header class="page__header">
      <h1 class="grow">{{ t("changes.title") }}</h1>
      <button type="button" class="button" @click="creating = true"><AppIcon name="add" />{{ t("changes.new") }}</button>
    </header>
    <p class="muted">{{ t("changes.info") }}</p>

    <ul v-if="open.length" role="list" class="changes">
      <li v-for="change in open" :key="change.id" class="change panel">
        <header class="change__header">
          <div class="row row--wrap">
            <h2 class="grow">
              <button
                type="button"
                class="change__toggle"
                :aria-expanded="isOpen(change)"
                :aria-controls="`change-${change.id}-tasks`"
                @click="toggle(change)"
              >
                <AppIcon name="chevron_right" :size="20" class="change__chevron" />{{ change.name }}
              </button>
            </h2>
            <RouterLink :to="boardLocation(projectId, 'kanban', { kind: 'change', name: change.name })" class="button button--secondary">
              <AppIcon name="view_kanban" :size="20" />{{ t("navigation.board") }}
            </RouterLink>
            <button type="button" class="button button--text" :aria-label="t('changes.archiveChange', { name: change.name })" @click="archiving = change">
              <AppIcon name="archive" :size="20" />{{ t("changes.archive") }}
            </button>
          </div>
          <p class="small muted">{{ tc("changes.total", change.task_counts.total) }}</p>
          <ul v-if="counts(change).length" role="list" class="change__counts small">
            <li v-for="row in counts(change)" :key="row.label"><span class="muted">{{ row.label }}</span> <strong>{{ row.count }}</strong></li>
          </ul>
        </header>

        <div v-show="isOpen(change)" :id="`change-${change.id}-tasks`" class="change__body">
          <template v-if="store.tasks.get(change.id)">
            <ol v-if="store.tasks.get(change.id)!.length" role="list" class="row-list">
              <li v-for="task in store.tasks.get(change.id)" :key="task.id" :class="{ 'change-task--done': isDone(task) }">
                <TaskRow v-bind="rowProps(task)">
                  <template #actions>
                    <span v-if="isDone(task)" class="chip">{{ t("changes.done") }}</span>
                    <!-- tasks.md keeps its cards in their change (spec changes, "Tasks in a change"). -->
                    <span v-if="task.in_tasks_md" class="chip" :title="t('task.changeFixed')">tasks.md</span>
                    <AppMenu v-else :label="t('changes.moveTask', { key: task.key })" align="end">
                      <template #trigger="{ id, expanded }">
                        <button
                          type="button"
                          class="button button--secondary move-button"
                          :popovertarget="id"
                          :aria-expanded="expanded"
                          :aria-label="t('changes.moveTask', { key: task.key })"
                        >
                          {{ t("changes.move") }}<AppIcon name="expand_more" :size="18" />
                        </button>
                      </template>
                      <template #default="{ close }">
                        <template v-if="otherChanges(change).length">
                          <p :id="`move-${task.id}-changes`" class="menu__heading">{{ t("changes.toChange") }}</p>
                          <div role="group" :aria-labelledby="`move-${task.id}-changes`">
                            <button v-for="target in otherChanges(change)" :key="target.id" type="button" class="menu__item" @click="close(); moveTask(task, target)">
                              <AppIcon name="flag" />{{ target.name }}
                            </button>
                          </div>
                          <hr class="menu__separator">
                        </template>
                        <button type="button" class="menu__item" @click="close(); moveTask(task, null)">
                          <AppIcon name="view_kanban" />{{ t("changes.toOther") }}
                        </button>
                      </template>
                    </AppMenu>
                  </template>
                </TaskRow>
              </li>
            </ol>
            <p v-else class="small muted">{{ t("changes.noTasks") }}</p>
          </template>
          <p v-else class="small muted">{{ t("common.loading") }}</p>

          <form class="new-bar" @submit.prevent="addTask(change)">
            <AppIcon name="add" :size="20" class="new-bar__icon" />
            <input
              v-model="newTitles[change.id]"
              class="input new-bar__input"
              maxlength="255"
              :aria-label="t('changes.newTask', { name: change.name })"
              :placeholder="t('changes.newTask', { name: change.name })"
            >
            <button type="submit" class="button">{{ t("common.create") }}</button>
          </form>
        </div>
      </li>
    </ul>
    <p v-else class="empty-state panel">{{ t("changes.noChanges") }}</p>

    <details v-if="archived.length" class="archived">
      <summary>{{ t("changes.archivedChanges") }} ({{ archived.length }})</summary>
      <ul role="list" class="stack archived__list">
        <li v-for="change in archived" :key="change.id">
          <details class="archived-change" @toggle="onArchivedToggle(change, $event)">
            <summary>
              <strong>{{ change.name }}</strong>
              <span class="small muted">
                {{ t("changes.archivedOn", { date: formatDate(language, change.archived_at!) }) }} · {{ tc("changes.total", change.task_counts.total) }}
              </span>
            </summary>
            <template v-if="store.tasks.get(change.id)">
              <ol v-if="store.tasks.get(change.id)!.length" role="list" class="row-list">
                <li v-for="task in store.tasks.get(change.id)" :key="task.id" :class="{ 'change-task--done': isDone(task) }">
                  <TaskRow v-bind="rowProps(task)">
                    <template #actions>
                      <span v-if="isDone(task)" class="chip">{{ t("changes.done") }}</span>
                    </template>
                  </TaskRow>
                </li>
              </ol>
              <p v-else class="small muted">{{ t("changes.noTasks") }}</p>
            </template>
            <p v-else class="small muted">{{ t("common.loading") }}</p>
          </details>
        </li>
      </ul>
    </details>

    <NewChangeDialog v-model:open="creating" :create="createChange" @created="(change) => ui.toast(t('changes.created', { name: change.name }))" />
    <ArchiveChangeDialog v-model:open="archiveOpen" :change="archiving" :unfinished="unfinishedCards" :on-confirm="archive" />
  </section>
</template>

<style scoped>
.changes-page { max-inline-size: 1040px; }
.changes { display: grid; gap: var(--space-3); }

.change {
  display: grid;
  gap: var(--space-3);
  padding: var(--space-4);
}

.change__header { display: grid; gap: var(--space-2); }

/* The section's disclosure button carries the heading's text. */
.change__toggle {
  display: inline-flex;
  align-items: center;
  gap: var(--space-1);
  min-block-size: var(--target-size);
  padding: 0 var(--space-1) 0 0;
  border: none;
  border-radius: var(--radius-sm);
  background: none;
  font-weight: inherit;
  text-align: start;
  overflow-wrap: anywhere;

  &:hover { color: var(--color-primary); }
}

.change__chevron { color: var(--color-muted); transition: rotate 0.15s; }
.change__toggle[aria-expanded="true"] .change__chevron { rotate: 90deg; }
.change__counts { display: flex; flex-wrap: wrap; gap: var(--space-1) var(--space-4); }
.change__body { display: grid; gap: var(--space-3); }
.change-task--done :deep(.task-row__title) { color: var(--color-muted); }
.move-button { --target-size: 32px; padding: var(--space-1) var(--space-2); gap: var(--space-1); }

@media (prefers-reduced-motion: reduce) {
  .change__chevron { transition: none; }
}

.archived summary { cursor: pointer; font-weight: 500; }
.archived__list { margin-block-start: var(--space-3); }
.archived-change summary { display: flex; flex-wrap: wrap; align-items: baseline; gap: var(--space-1) var(--space-3); font-weight: 400; }
.archived-change .row-list { margin-block-start: var(--space-2); }
</style>
