<script setup lang="ts">
import { computed, ref } from "vue"
import AppIcon from "../ui/AppIcon.vue"
import ChoiceMenu, { type Choice } from "../ui/ChoiceMenu.vue"
import UserAvatar from "../UserAvatar.vue"
import type { Column, Label, Milestone, SprintSummary, TaskDetail, UserCard } from "../../api/types.ts"
import { language, t } from "../../i18n/index.ts"
import { formatDate, fromDateTimeInput, toDateTimeInput } from "../../i18n/format.ts"

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
        <ChoiceMenu v-else :label="t('task.status')" :choices="statusChoices" :selected="task.status_id" @choose="emit('status', $event)" />
      </dd>
    </div>

    <div class="details__row">
      <dt>{{ t("task.assignee") }}</dt>
      <dd>
        <ChoiceMenu :label="t('task.assignee')" :choices="assigneeChoices" :selected="task.assignee_id" @choose="emit('update', { assignee_id: $event })">
          <template #value>
            <span class="row"><UserAvatar :user="assignee" :size="24" />{{ assignee?.name ?? t("task.unassigned") }}</span>
          </template>
        </ChoiceMenu>
      </dd>
    </div>

    <div class="details__row">
      <dt><label :for="`deadline-${task.id}`">{{ t("task.deadline") }}</label></dt>
      <dd class="row">
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
          <AppIcon :name="task.important ? 'local_fire_department_filled' : 'local_fire_department'" :size="20" />
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

    <p v-if="task.creator" class="small muted">
      {{ t("task.creator", { name: task.creator.name, date: formatDate(language, task.created_at) }) }}
    </p>
  </dl>
</template>

<style scoped>
.details { display: grid; gap: var(--space-2); }

.details__row {
  display: grid;
  gap: var(--space-1);

  & dt { font-size: var(--text-sm); font-weight: 500; color: var(--color-muted); }
  & dd { margin: 0; min-inline-size: 0; }
}

.important-toggle[aria-pressed="true"] { border-color: var(--color-accent); color: var(--color-accent-dark); }
.new-label { padding: var(--space-1) var(--space-3); }
</style>
