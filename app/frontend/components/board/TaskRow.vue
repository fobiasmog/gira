<script setup lang="ts">
import { computed } from "vue"
import AppIcon from "../ui/AppIcon.vue"
import UserAvatar from "../UserAvatar.vue"
import type { Label, TaskCard, UserCard } from "../../api/types.ts"
import { language, t } from "../../i18n/index.ts"
import { formatDateTime, formatRelativeDay } from "../../i18n/format.ts"

// One task as a list row (list layout, backlog, milestone, archive).
const props = defineProps<{ task: TaskCard; projectId: number; assignee: UserCard | null; label: Label | null; describedBy?: string; archived?: boolean }>()
defineSlots<{ handle(): unknown; actions(): unknown }>()

const overdue = computed(() => !!props.task.deadline && !props.task.completed_at && new Date(props.task.deadline) < new Date())
</script>

<template>
  <div class="task-row">
    <slot name="handle" />
    <span class="task-row__key small">{{ task.key }}</span>
    <RouterLink
      class="task-row__title ellipsis"
      :to="archived ? { name: 'archived-task', params: { pid: projectId, tid: task.id } } : { name: 'task', params: { pid: projectId, ref: task.key } }"
      :aria-describedby="describedBy"
      data-move-focus
    >{{ task.title }}</RouterLink>
    <span v-if="label" class="chip ellipsis">{{ label.title }}</span>
    <span v-if="task.important" class="task-row__important" :title="t('board.important')">
      <AppIcon name="local_fire_department_filled" :size="18" />
      <span class="visually-hidden">{{ t("board.important") }}</span>
    </span>
    <time
      v-if="task.deadline"
      class="task-row__deadline small"
      :class="{ 'task-row__deadline--overdue': overdue }"
      :datetime="task.deadline"
      :title="formatDateTime(language, task.deadline)"
    >{{ formatRelativeDay(language, task.deadline) }}</time>
    <span class="task-row__assignee" :title="assignee?.name ?? t('board.unassigned')">
      <UserAvatar :user="assignee" :size="24" />
      <span class="visually-hidden">{{ assignee ? t("board.assignedTo", { name: assignee.name }) : t("board.unassigned") }}</span>
    </span>
    <slot name="actions" />
  </div>
</template>

<style scoped>
.task-row {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  min-block-size: 44px;
  padding: var(--space-1) var(--space-2);
  border-radius: var(--radius);
  background: var(--color-surface);
  box-shadow: var(--shadow);

  &:hover { box-shadow: var(--shadow-hover); }
}

.task-row__key { flex: none; color: var(--color-muted); font-weight: 500; }

.task-row__title {
  flex: 1 1 auto;
  color: var(--color-text);
  text-decoration: none;

  &:hover { color: var(--color-main-dark); text-decoration: underline; }
}

.task-row__important { display: inline-flex; color: var(--color-accent-dark); }
.task-row__deadline { flex: none; color: var(--color-muted); }
.task-row__deadline--overdue { color: var(--color-danger); font-weight: 500; }
.task-row__assignee { display: inline-flex; }
</style>
