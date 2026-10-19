<script setup lang="ts">
import { computed, ref, watch } from "vue"
import { storeToRefs } from "pinia"
import AppDialog from "../components/ui/AppDialog.vue"
import AppField from "../components/ui/AppField.vue"
import AppIcon from "../components/ui/AppIcon.vue"
import { ApiError } from "../api/client.ts"
import type { FieldErrors, Sprint } from "../api/types.ts"
import { useBoardStore } from "../stores/board.ts"
import { useSprintsStore } from "../stores/sprints.ts"
import { useUiStore } from "../stores/ui.ts"
import { language, t, tc } from "../i18n/index.ts"
import { formatDate } from "../i18n/format.ts"

const props = defineProps<{ projectId: number }>()
const store = useSprintsStore()
const { sprints, archived, active } = storeToRefs(store)
const board = useBoardStore()
const ui = useUiStore()
const loaded = ref(false)

watch(() => props.projectId, async (id) => {
  loaded.value = false
  await ui.load(Promise.all([store.load(id), board.projectId === id ? Promise.resolve() : board.load(id)]))
  loaded.value = store.projectId === id
}, { immediate: true })

const dates = (sprint: Sprint) => t("sprints.dates", { start: formatDate(language.value, sprint.starts_on), end: formatDate(language.value, sprint.ends_on) })

// Task counts per column, in board order, then the backlog.
function counts(sprint: Sprint): { label: string; count: number }[] {
  const byStatus = sprint.task_counts.by_status
  const rows = board.columns.map((column) => ({ label: column.title, count: byStatus[String(column.id)] ?? 0 }))
  if (byStatus.backlog) rows.push({ label: t("sprints.inBacklog"), count: byStatus.backlog })
  return rows.filter((row) => row.count > 0)
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
        <header class="row row--wrap">
          <h2 class="grow">{{ sprint.title }}</h2>
          <span v-if="sprint.active" class="chip">{{ t("sprints.active") }}</span>
        </header>
        <p class="small muted">{{ dates(sprint) }} · {{ tc("sprints.total", sprint.task_counts.total) }}</p>
        <ul v-if="counts(sprint).length" role="list" class="sprint__counts small">
          <li v-for="row in counts(sprint)" :key="row.label"><span class="muted">{{ row.label }}</span> <strong>{{ row.count }}</strong></li>
        </ul>
        <div class="row">
          <button v-if="!sprint.active" type="button" class="button button--secondary" @click="activate(sprint)">{{ t("sprints.makeActive") }}</button>
          <button type="button" class="button button--text" @click="openArchive(sprint)"><AppIcon name="archive" :size="20" />{{ t("sprints.archive") }}</button>
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
.sprints-page { max-inline-size: 840px; }
.sprints { display: grid; gap: var(--space-3); }

.sprint {
  display: grid;
  gap: var(--space-2);
  padding: var(--space-4);
  border-inline-start: 3px solid transparent;
}

.sprint--active { border-inline-start-color: var(--color-main); }
.sprint__counts { display: flex; flex-wrap: wrap; gap: var(--space-1) var(--space-4); }
.dates > * { flex: 1 1 10rem; }
.carry { margin: 0; padding: 0; border: none; }
.archived summary { cursor: pointer; font-weight: 500; }
.archived ul { margin-block-start: var(--space-3); }
</style>
