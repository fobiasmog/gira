<script setup lang="ts">
import { computed, ref } from "vue"
import AppIcon from "../ui/AppIcon.vue"
import ChoiceMenu, { type Choice } from "../ui/ChoiceMenu.vue"
import UserAvatar from "../UserAvatar.vue"
import StatusDot from "../board/StatusDot.vue"
import type { Column, Label, Milestone, SprintSummary, TaskDetail, UserCard } from "../../api/types.ts"
import { language, t } from "../../i18n/index.ts"
import { formatDate, fromDateTimeInput, toDateTimeInput } from "../../i18n/format.ts"
import { toneOf } from "../../styles/tones.ts"

// The task's properties, each changed in place.
const props = defineProps<{
  task: TaskDetail
  columns: Column[]
  members: UserCard[]
  milestones: Milestone[]
  labels: Label[]
  sprints: SprintSummary[]
}>()
const emit = defineEmits<{
  status: [columnId: number | null]
  complete: [complete: boolean]
  update: [fields: { assignee_id?: number | null; deadline?: string | null; important?: boolean; milestone_id?: number | null }]
  label: [labelId: number | null]
  "create-label": [title: string]
  sprint: [sprintId: number | null]
}>()

const statusChoices = computed<Choice<number | null>[]>(() => [
  ...props.columns.map((column) => ({ value: column.id, label: column.title })),
  { value: null, label: t("task.backlog") },
])
const assigneeChoices = computed<Choice<number | null>[]>(() => [
  { value: null, label: t("task.unassigned") },
  ...props.members.map((member) => ({ value: member.id, label: member.name })),
])
const milestoneChoices = computed<Choice<number | null>[]>(() => [
  { value: null, label: t("task.noMilestone") },
  ...props.milestones.map((milestone) => ({ value: milestone.id, label: milestone.title })),
])
const labelChoices = computed<Choice<number | null>[]>(() => [
  { value: null, label: t("task.noLabel") },
  ...props.labels.map((label) => ({ value: label.id, label: label.title })),
])
const sprintChoices = computed<Choice<number | null>[]>(() => {
  const choices = props.sprints.map((sprint) => ({ value: sprint.id, label: sprint.title }))
  // The task's own sprint stays listed even when it is no longer open.
  if (props.task.sprint && !choices.some((choice) => choice.value === props.task.sprint!.id)) choices.push({ value: props.task.sprint.id, label: props.task.sprint.title })
  return [{ value: null, label: t("task.noSprint") }, ...choices]
})

const statusColumn = computed(() => props.columns.find((column) => column.id === props.task.status_id) ?? null)
const assignee = computed(() => props.members.find((member) => member.id === props.task.assignee_id) ?? props.task.assignee)
const newLabel = ref("")

function onDeadline(event: Event) {
  emit("update", { deadline: fromDateTimeInput((event.target as HTMLInputElement).value) })
}

function createLabel(close: () => void) {
  const title = newLabel.value.trim()
  if (!title) return
  emit("create-label", title)
  newLabel.value = ""
  close()
}
</script>

<template>
  <dl class="details">
    <div class="details__row">
      <dt>{{ task.parent_id ? t("task.complete") : t("task.status") }}</dt>
      <dd>
        <label v-if="task.parent_id" class="row">
          <input type="checkbox" :checked="!!task.status?.done" @change="emit('complete', ($event.target as HTMLInputElement).checked)">
          {{ t("task.markComplete") }}
        </label>
        <ChoiceMenu v-else :label="t('task.status')" :choices="statusChoices" :selected="task.status_id" @choose="emit('status', $event)">
          <template #value>
            <span class="value"><StatusDot v-if="statusColumn" :column="statusColumn" /><span class="ellipsis">{{ statusColumn?.title ?? t("task.backlog") }}</span></span>
          </template>
        </ChoiceMenu>
      </dd>
    </div>

    <div class="details__row">
      <dt>{{ t("task.assignee") }}</dt>
      <dd>
        <ChoiceMenu :label="t('task.assignee')" :choices="assigneeChoices" :selected="task.assignee_id" @choose="emit('update', { assignee_id: $event })">
          <template #value>
            <span class="value"><UserAvatar :user="assignee" :size="22" /><span class="ellipsis">{{ assignee?.name ?? t("task.unassigned") }}</span></span>
          </template>
        </ChoiceMenu>
      </dd>
    </div>

    <div class="details__row">
      <dt><label :for="`deadline-${task.id}`">{{ t("task.deadline") }}</label></dt>
      <dd class="details__deadline">
        <input :id="`deadline-${task.id}`" class="input" type="datetime-local" :value="toDateTimeInput(task.deadline)" @change="onDeadline">
        <button v-if="task.deadline" type="button" class="icon-button" :aria-label="t('task.clearDeadline')" @click="emit('update', { deadline: null })">
          <AppIcon name="close" :size="20" />
        </button>
      </dd>
    </div>

    <div class="details__row">
      <dt>{{ t("task.important") }}</dt>
      <dd>
        <button
          type="button"
          class="button button--secondary important-toggle"
          :aria-pressed="task.important"
          @click="emit('update', { important: !task.important })"
        >
          <AppIcon :name="task.important ? 'local_fire_department_filled' : 'local_fire_department'" :size="18" />
          {{ t("task.important") }}
        </button>
      </dd>
    </div>

    <div class="details__row">
      <dt>{{ t("task.milestone") }}</dt>
      <dd>
        <ChoiceMenu :label="t('task.milestone')" :choices="milestoneChoices" :selected="task.milestone_id" @choose="emit('update', { milestone_id: $event })" />
      </dd>
    </div>

    <div v-if="!task.parent_id" class="details__row">
      <dt>{{ t("task.label") }}</dt>
      <dd>
        <ChoiceMenu :label="t('task.label')" :choices="labelChoices" :selected="task.label_id" @choose="emit('label', $event)">
          <template #value>
            <span v-if="task.label" class="chip ellipsis" :data-tone="toneOf(task.label.id)">{{ task.label.title }}</span>
            <span v-else class="muted">{{ t("task.noLabel") }}</span>
          </template>
          <template #default="{ close }">
            <hr class="menu__separator">
            <form class="row new-label" @submit.prevent="createLabel(close)">
              <input v-model="newLabel" class="input" maxlength="100" :aria-label="t('task.newLabel')" :placeholder="t('task.newLabel')">
              <button type="submit" class="icon-button" :aria-label="t('common.create')"><AppIcon name="add" /></button>
            </form>
          </template>
        </ChoiceMenu>
      </dd>
    </div>

    <div v-if="!task.parent_id" class="details__row">
      <dt>{{ t("task.sprint") }}</dt>
      <dd>
        <ChoiceMenu :label="t('task.sprint')" :choices="sprintChoices" :selected="task.sprint_id" @choose="emit('sprint', $event)" />
      </dd>
    </div>

  </dl>
  <p v-if="task.creator" class="details__creator">
    {{ t("task.creator", { name: task.creator.name, date: formatDate(language, task.created_at) }) }}
  </p>
</template>

<style scoped>
/* One grid for all rows, so the labels share a column. */
.details {
  display: grid;
  grid-template-columns: max-content minmax(0, 1fr);
  align-items: center;
  gap: var(--space-2) var(--space-3);
  font-size: var(--text-sm);
}

.details__row {
  display: contents;

  & dt { color: var(--color-muted); }
  & dd { margin: 0; min-inline-size: 0; }
}

/* ChoiceMenu's trigger fills the value column. */
.details__row dd > :deep(.menu-anchor) { display: flex; }

.value { display: flex; align-items: center; gap: var(--space-2); min-inline-size: 0; }

.details__deadline { display: flex; align-items: center; gap: var(--space-1); }
.details__deadline .input { flex: 1 1 auto; min-inline-size: 0; padding-inline: var(--space-2); font-size: var(--text-sm); }
.details__deadline .icon-button { --target-size: 32px; }

.important-toggle { inline-size: 100%; justify-content: flex-start; padding-inline: var(--space-3); box-shadow: none; }
.important-toggle[aria-pressed="true"] { border-color: var(--color-important); background: var(--color-overdue-bg); color: var(--color-overdue); }

.details__creator { margin-block-start: var(--space-4); color: var(--color-muted); font-size: var(--text-xs); }
.new-label { padding: var(--space-1) var(--space-2); }
</style>
