<script setup lang="ts">
import { computed, ref, watch } from "vue"
import { storeToRefs } from "pinia"
import AppDialog from "../components/ui/AppDialog.vue"
import AppField from "../components/ui/AppField.vue"
import AppIcon from "../components/ui/AppIcon.vue"
import AppMenu from "../components/ui/AppMenu.vue"
import TaskRow from "../components/board/TaskRow.vue"
import { ApiError } from "../api/client.ts"
import type { FieldErrors, Sprint, SprintTaskCard, TaskCard } from "../api/types.ts"
import { useBoardStore } from "../stores/board.ts"
import { useSprintsStore } from "../stores/sprints.ts"
import { useUiStore } from "../stores/ui.ts"
import { language, t, tc } from "../i18n/index.ts"
import { formatDate } from "../i18n/format.ts"

// Sprint planning (spec web-client, "Sprint planning screen"): each open
// sprint is a section listing its tasks, which can be added and moved between
// sprints and the backlog.
const props = defineProps<{ projectId: number }>()
const store = useSprintsStore()
const { sprints, archived, active } = storeToRefs(store)
const board = useBoardStore()
const ui = useUiStore()
const loaded = ref(false)

// Sections the viewer opened or closed. The others start open for planned
// sprints and closed for the active one, whose tasks are on the board.
const toggled = ref(new Map<number, boolean>())
const isOpen = (sprint: Sprint) => toggled.value.get(sprint.id) ?? !sprint.active

watch(() => props.projectId, async (id) => {
  loaded.value = false
  toggled.value = new Map()
  await ui.load(Promise.all([store.load(id), board.projectId === id ? Promise.resolve() : board.load(id)]))
  loaded.value = store.projectId === id
}, { immediate: true })

// A section's tasks load the first time it is open, also after sprints change.
watch([loaded, sprints], () => {
  if (loaded.value) for (const sprint of sprints.value) if (isOpen(sprint)) loadTasks(sprint)
})

async function loadTasks(sprint: Sprint) {
  try {
    await store.loadTasks(props.projectId, sprint.id)
  } catch (error) {
    ui.fail(error)
  }
}

function toggle(sprint: Sprint) {
  const open = !isOpen(sprint)
  toggled.value.set(sprint.id, open)
  if (open) loadTasks(sprint)
}

const dates = (sprint: Sprint) => t("sprints.dates", { start: formatDate(language.value, sprint.starts_on), end: formatDate(language.value, sprint.ends_on) })

// Task counts per column, in board order.
function counts(sprint: Sprint): { label: string; count: number }[] {
  const byStatus = sprint.task_counts.by_status
  return board.columns.map((column) => ({ label: column.title, count: byStatus[String(column.id)] ?? 0 })).filter((row) => row.count > 0)
}

const columnById = computed(() => new Map(board.columns.map((column) => [column.id, column])))
const isDone = (task: SprintTaskCard) => columnById.value.get(task.status_id)?.done ?? false
const otherSprints = (sprint: Sprint) => sprints.value.filter((other) => other.id !== sprint.id)

// A done task shows a "Done" chip in place of its column.
const rowProps = (task: SprintTaskCard) => ({
  task,
  projectId: props.projectId,
  column: isDone(task) ? null : columnById.value.get(task.status_id) ?? null,
  assignee: task.assignee_id ? board.memberById.get(task.assignee_id) ?? null : null,
  label: task.label_id ? board.labelById.get(task.label_id) ?? null : null,
})

// Changes answer with the task's card; the board follows along.
function syncBoard(card: TaskCard) {
  if (board.projectId === props.projectId) board.upsertCard(card)
}

const newTitles = ref<Record<number, string>>({})

async function addTask(sprint: Sprint) {
  const title = (newTitles.value[sprint.id] ?? "").trim()
  if (!title) return
  try {
    syncBoard(await store.addTask(props.projectId, sprint.id, title))
    newTitles.value[sprint.id] = ""
  } catch (error) {
    ui.fail(error)
  }
}

// Into another sprint, or to the backlog (null).
async function moveTask(task: SprintTaskCard, target: Sprint | null) {
  try {
    syncBoard(await store.moveTask(props.projectId, task.id, target?.id ?? null))
    ui.toast(target ? t("sprints.movedTo", { key: task.key, title: target.title }) : t("sprints.movedToBacklog", { key: task.key }))
  } catch (error) {
    ui.fail(error)
  }
}

// New sprint dialog.
const creating = ref(false)
const form = ref({ title: "", starts_on: "", ends_on: "", activate: false, carry_over: false })
const errors = ref<FieldErrors>({})

function openNew() {
  form.value = { title: "", starts_on: "", ends_on: "", activate: !active.value, carry_over: false }
  errors.value = {}
  creating.value = true
}

async function create() {
  errors.value = {}
  try {
    const title = form.value.title.trim()
    await store.create(props.projectId, { ...form.value, title, carry_over: form.value.activate && form.value.carry_over })
    creating.value = false
    ui.toast(t("sprints.created", { title }))
    if (form.value.activate) await board.load(props.projectId)
  } catch (error) {
    if (error instanceof ApiError && error.status === 422) errors.value = error.fields
    else ui.fail(error)
  }
}

async function activate(sprint: Sprint) {
  try {
    await store.activate(props.projectId, sprint.id)
    await board.load(props.projectId)
    ui.toast(t("sprints.activated", { title: sprint.title }))
  } catch (error) {
    ui.fail(error)
  }
}

// Archive dialog.
const archiving = ref<Sprint | null>(null)
const archiveOpen = computed({ get: () => archiving.value !== null, set: (open) => { if (!open) archiving.value = null } })
const carryTo = ref<number | null>(null)
const carryTargets = computed(() => sprints.value.filter((sprint) => sprint.id !== archiving.value?.id))

function openArchive(sprint: Sprint) {
  carryTo.value = null
  archiving.value = sprint
}

async function archive() {
  const sprint = archiving.value
  if (!sprint) return
  try {
    await store.archive(props.projectId, sprint.id, carryTo.value)
    archiving.value = null
    await board.load(props.projectId)
    ui.toast(t("sprints.archived", { title: sprint.title }))
  } catch (error) {
    ui.fail(error)
  }
}
</script>

<template>
  <section v-if="loaded" class="page sprints-page">
    <header class="page__header">
      <h1 class="grow">{{ t("sprints.title") }}</h1>
      <button type="button" class="button" @click="openNew"><AppIcon name="add" />{{ t("sprints.new") }}</button>
    </header>
    <p class="muted">{{ t("sprints.info") }}</p>

    <ul v-if="sprints.length" role="list" class="sprints">
      <li v-for="sprint in sprints" :key="sprint.id" class="sprint panel" :class="{ 'sprint--active': sprint.active }">
        <header class="sprint__header">
          <div class="row row--wrap">
            <h2 class="grow">
              <button
                type="button"
                class="sprint__toggle"
                :aria-expanded="isOpen(sprint)"
                :aria-controls="`sprint-${sprint.id}-tasks`"
                @click="toggle(sprint)"
              >
                <AppIcon name="chevron_right" :size="20" class="sprint__chevron" />{{ sprint.title }}
              </button>
            </h2>
            <span v-if="sprint.active" class="chip">{{ t("sprints.active") }}</span>
            <button v-if="!sprint.active" type="button" class="button button--secondary" @click="activate(sprint)">{{ t("sprints.makeActive") }}</button>
            <button type="button" class="button button--text" @click="openArchive(sprint)"><AppIcon name="archive" :size="20" />{{ t("sprints.archive") }}</button>
          </div>
          <p class="small muted">{{ dates(sprint) }} · {{ tc("sprints.total", sprint.task_counts.total) }}</p>
          <ul v-if="counts(sprint).length" role="list" class="sprint__counts small">
            <li v-for="row in counts(sprint)" :key="row.label"><span class="muted">{{ row.label }}</span> <strong>{{ row.count }}</strong></li>
          </ul>
        </header>

        <div v-show="isOpen(sprint)" :id="`sprint-${sprint.id}-tasks`" class="sprint__body">
          <template v-if="store.tasks.get(sprint.id)">
            <ol v-if="store.tasks.get(sprint.id)!.length" role="list" class="row-list">
              <li v-for="task in store.tasks.get(sprint.id)" :key="task.id" :class="{ 'sprint-task--done': isDone(task) }">
                <TaskRow v-bind="rowProps(task)">
                  <template #actions>
                    <span v-if="isDone(task)" class="chip">{{ t("sprints.done") }}</span>
                    <span v-if="task.carried_to" class="chip ellipsis">{{ t("sprints.carriedTo", { title: task.carried_to.title }) }}</span>
                    <AppMenu :label="t('sprints.moveTask', { key: task.key })" align="end">
                      <template #trigger="{ id, expanded }">
                        <button
                          type="button"
                          class="button button--secondary move-button"
                          :popovertarget="id"
                          :aria-expanded="expanded"
                          :aria-label="t('sprints.moveTask', { key: task.key })"
                        >
                          {{ t("sprints.move") }}<AppIcon name="expand_more" :size="18" />
                        </button>
                      </template>
                      <template #default="{ close }">
                        <template v-if="otherSprints(sprint).length">
                          <p :id="`move-${task.id}-sprints`" class="menu__heading">{{ t("sprints.toSprint") }}</p>
                          <div role="group" :aria-labelledby="`move-${task.id}-sprints`">
                            <button v-for="target in otherSprints(sprint)" :key="target.id" type="button" class="menu__item" @click="close(); moveTask(task, target)">
                              <AppIcon name="sprint" />{{ target.title }}
                            </button>
                          </div>
                          <hr class="menu__separator">
                        </template>
                        <button type="button" class="menu__item" @click="close(); moveTask(task, null)">
                          <AppIcon name="inbox" />{{ t("sprints.toBacklog") }}
                        </button>
                      </template>
                    </AppMenu>
                  </template>
                </TaskRow>
              </li>
            </ol>
            <p v-else class="small muted">{{ t("sprints.noTasks") }}</p>
          </template>
          <p v-else class="small muted">{{ t("common.loading") }}</p>

          <form class="new-bar" @submit.prevent="addTask(sprint)">
            <AppIcon name="add" :size="20" class="new-bar__icon" />
            <input
              v-model="newTitles[sprint.id]"
              class="input new-bar__input"
              maxlength="255"
              :aria-label="t('sprints.newTask', { title: sprint.title })"
              :placeholder="t('sprints.newTask', { title: sprint.title })"
            >
            <button type="submit" class="button">{{ t("common.create") }}</button>
          </form>
        </div>
      </li>
    </ul>
    <p v-else class="empty-state panel">{{ t("sprints.noSprints") }}</p>

    <details v-if="archived.length" class="archived">
      <summary>{{ t("sprints.archivedSprints") }} ({{ archived.length }})</summary>
      <ul role="list" class="stack">
        <li v-for="sprint in archived" :key="sprint.id" class="row row--wrap">
          <strong>{{ sprint.title }}</strong>
          <span class="small muted">{{ dates(sprint) }} · {{ tc("sprints.total", sprint.task_counts.total) }}</span>
        </li>
      </ul>
    </details>

    <AppDialog v-model:open="creating" :title="t('sprints.new')">
      <form id="new-sprint" class="stack" novalidate @submit.prevent="create">
        <AppField :label="t('sprints.name')" :errors="errors.title">
          <template #default="{ control }"><input v-model="form.title" v-bind="control" class="input" maxlength="100" required></template>
        </AppField>
        <div class="row row--wrap dates">
          <AppField :label="t('sprints.startsOn')" :errors="errors.starts_on">
            <template #default="{ control }"><input v-model="form.starts_on" v-bind="control" class="input" type="date" required :max="form.ends_on || undefined"></template>
          </AppField>
          <AppField :label="t('sprints.endsOn')" :errors="errors.ends_on">
            <template #default="{ control }"><input v-model="form.ends_on" v-bind="control" class="input" type="date" required :min="form.starts_on || undefined"></template>
          </AppField>
        </div>
        <label class="row"><input v-model="form.activate" type="checkbox">{{ t("sprints.activate") }}</label>
        <label v-if="active" class="row" :class="{ muted: !form.activate }">
          <input v-model="form.carry_over" type="checkbox" :disabled="!form.activate">{{ t("sprints.carryOver") }}
        </label>
      </form>
      <template #actions>
        <button type="button" class="button button--text" @click="creating = false">{{ t("common.cancel") }}</button>
        <button type="submit" form="new-sprint" class="button">{{ t("sprints.create") }}</button>
      </template>
    </AppDialog>

    <AppDialog v-model:open="archiveOpen" :title="t('sprints.archiveTitle', { title: archiving?.title ?? '' })">
      <fieldset class="stack carry">
        <legend class="field__label">{{ t("sprints.carryTo") }}</legend>
        <label class="row"><input v-model="carryTo" type="radio" name="carry-to" :value="null">{{ t("sprints.noCarry") }}</label>
        <label v-for="target in carryTargets" :key="target.id" class="row">
          <input v-model="carryTo" type="radio" name="carry-to" :value="target.id">{{ target.title }}
        </label>
      </fieldset>
      <template #actions>
        <button type="button" class="button button--text" @click="archiving = null">{{ t("common.cancel") }}</button>
        <button type="button" class="button" @click="archive">{{ t("sprints.archive") }}</button>
      </template>
    </AppDialog>
  </section>
</template>

<style scoped>
.sprints-page { max-inline-size: 1040px; }
.sprints { display: grid; gap: var(--space-3); }

.sprint {
  display: grid;
  gap: var(--space-3);
  padding: var(--space-4);
  border-inline-start: 3px solid transparent;
}

.sprint--active { border-inline-start-color: var(--color-main); }
.sprint__header { display: grid; gap: var(--space-2); }

/* The section's disclosure button carries the heading's text. */
.sprint__toggle {
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

  &:hover { color: var(--color-primary); }
}

.sprint__chevron { color: var(--color-muted); transition: rotate 0.15s; }
.sprint__toggle[aria-expanded="true"] .sprint__chevron { rotate: 90deg; }
.sprint__counts { display: flex; flex-wrap: wrap; gap: var(--space-1) var(--space-4); }
.sprint__body { display: grid; gap: var(--space-3); }
.sprint-task--done :deep(.task-row__title) { color: var(--color-muted); }
.move-button { --target-size: 32px; padding: var(--space-1) var(--space-2); gap: var(--space-1); }

@media (prefers-reduced-motion: reduce) {
  .sprint__chevron { transition: none; }
}
.dates > * { flex: 1 1 10rem; }
.carry { margin: 0; padding: 0; border: none; }
.archived summary { cursor: pointer; font-weight: 500; }
.archived ul { margin-block-start: var(--space-3); }
</style>
