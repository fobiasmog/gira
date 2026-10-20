<script setup lang="ts">
import { computed } from "vue"
import AppIcon from "../ui/AppIcon.vue"
import UserAvatar from "../UserAvatar.vue"
import type { Label, TaskCard, UserCard } from "../../api/types.ts"
import { language, t } from "../../i18n/index.ts"
import { formatDateTime, formatRelativeDay } from "../../i18n/format.ts"
import { toneOf } from "../../styles/tones.ts"

// One task as a list row (list layout, backlog, milestone, archive).
const props = defineProps<{ task: TaskCard; projectId: number; assignee: UserCard | null; label: Label | null; describedBy?: string; archived?: boolean }>()
defineSlots<{ handle(): unknown; actions(): unknown }>()

const overdue = computed(() => !!props.task.deadline && !props.task.completed_at && new Date(props.task.deadline) < new Date())
</script>

<template>
  <div class="task-row">
    <slot name="handle" />
    <span class="task-row__key">{{ task.key }}</span>
    <RouterLink
      class="task-row__title ellipsis"
      :to="archived ? { name: 'archived-task', params: { pid: projectId, tid: task.id } } : { name: 'task', params: { pid: projectId, ref: task.key } }"
      :aria-describedby="describedBy"
      data-move-focus
    >{{ task.title }}</RouterLink>
    <span v-if="label" class="chip ellipsis task-row__label" :data-tone="toneOf(label.id)">{{ label.title }}</span>
    <span v-if="task.important" class="task-row__important" :title="t('board.important')">
      <AppIcon name="local_fire_department_filled" :size="18" />
      <span class="visually-hidden">{{ t("board.important") }}</span>
    </span>
    <time
      v-if="task.deadline"
      class="task-row__deadline"
      :class="{ 'task-row__deadline--overdue': overdue }"
      :datetime="task.deadline"
      :title="formatDateTime(language, task.deadline)"
    >{{ formatRelativeDay(language, task.deadline) }}</time>
    <span class="task-row__assignee" :title="assignee?.name ?? t('board.unassigned')">
      <UserAvatar :user="assignee" :size="26" />
      <span class="visually-hidden">{{ assignee ? t("board.assignedTo", { name: assignee.name }) : t("board.unassigned") }}</span>
    </span>
    <slot name="actions" />
  </div>
</template>

<style scoped>
.task-row {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  min-block-size: 52px;
  padding: var(--space-2) var(--space-3);
  font-size: var(--text-sm);
}

.task-row__key { flex: none; min-inline-size: 4.5em; color: var(--color-muted); font-size: var(--text-xs); font-weight: 500; }

.task-row__title {
  flex: 1 1 auto;
  border-radius: var(--radius-sm);
  color: var(--color-text);
  font-weight: 500;
  text-decoration: none;

  &:hover { color: var(--color-primary); text-decoration: underline; }
}

.task-row__label { flex: none; }
.task-row__important { display: inline-flex; color: var(--color-important); }
.task-row__deadline { flex: none; color: var(--color-muted); font-size: var(--text-xs); }

.task-row__deadline--overdue {
  padding: 1px var(--space-1);
  border-radius: var(--radius-sm);
  background: var(--color-overdue-bg);
  color: var(--color-overdue);
  font-weight: 500;
}

.task-row__assignee { display: inline-flex; }

@media (max-width: 600px) {
  .task-row { flex-wrap: wrap; gap: var(--space-2); }
  .task-row__title { flex-basis: calc(100% - 7em); }
}
</style>
