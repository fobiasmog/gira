<script setup lang="ts">
import { computed } from "vue"
import AppIcon from "../ui/AppIcon.vue"
import UserAvatar from "../UserAvatar.vue"
import type { Label, TaskCard, UserCard } from "../../api/types.ts"
import { language, t, tc } from "../../i18n/index.ts"
import { formatDateTime, formatRelativeDay } from "../../i18n/format.ts"
import { toneOf } from "../../styles/tones.ts"

const props = defineProps<{ task: TaskCard; projectId: number; assignee: UserCard | null; label: Label | null; describedBy?: string }>()

const overdue = computed(() => !!props.task.deadline && !props.task.completed_at && new Date(props.task.deadline) < new Date())
</script>

<template>
  <article class="card">
    <div class="card__top">
      <slot name="handle" />
      <span class="card__key">{{ task.key }}</span>
      <span v-if="label" class="chip ellipsis" :data-tone="toneOf(label.id)">{{ label.title }}</span>
      <span class="grow" />
      <span v-if="assignee" class="card__assignee" :title="assignee.name">
        <UserAvatar :user="assignee" :size="24" />
        <span class="visually-hidden">{{ t("board.assignedTo", { name: assignee.name }) }}</span>
      </span>
    </div>
    <RouterLink
      class="card__title break-word"
      :to="{ name: 'task', params: { pid: projectId, ref: task.key } }"
      :aria-describedby="describedBy"
      data-move-focus
    >
      {{ task.title }}
    </RouterLink>
    <div v-if="task.important || task.deadline || task.subtask_count || task.comment_count" class="card__meta">
      <span v-if="task.important" class="card__important">
        <AppIcon name="local_fire_department_filled" :size="16" />{{ t("board.important") }}
      </span>
      <time
        v-if="task.deadline"
        class="card__deadline"
        :class="{ 'card__deadline--overdue': overdue }"
        :datetime="task.deadline"
        :title="formatDateTime(language, task.deadline)"
      >
        <AppIcon name="calendar_today" :size="14" />
        <span class="visually-hidden">{{ t("board.deadline", { date: "" }) }}</span>{{ formatRelativeDay(language, task.deadline) }}
      </time>
      <span class="grow" />
      <span v-if="task.subtask_count" class="card__count" :title="t('board.subtasks', { done: task.subtask_done_count, total: task.subtask_count })">
        <AppIcon name="checklist" :size="16" />
        <span aria-hidden="true">{{ task.subtask_done_count }}/{{ task.subtask_count }}</span>
        <span class="visually-hidden">{{ t("board.subtasks", { done: task.subtask_done_count, total: task.subtask_count }) }}</span>
      </span>
      <span v-if="task.comment_count" class="card__count" :title="tc('board.comments', task.comment_count)">
        <AppIcon name="chat_bubble" :size="16" />
        <span aria-hidden="true">{{ task.comment_count }}</span>
        <span class="visually-hidden">{{ tc("board.comments", task.comment_count) }}</span>
      </span>
    </div>
  </article>
</template>

<style scoped>
.card {
  position: relative;
  display: grid;
  gap: var(--space-2);
  padding: var(--space-3);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  background: var(--color-surface);
  box-shadow: var(--shadow);

  &:hover { border-color: var(--color-main-light); box-shadow: var(--shadow-hover); }
  &:has(.card__title:focus-visible) { outline: 2px solid var(--color-focus); outline-offset: 2px; }
}

.card__top {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  min-block-size: 24px;
  font-size: var(--text-xs);
}

.card__key { flex: none; color: var(--color-muted); font-weight: 500; letter-spacing: 0.02em; }

.card__assignee { position: relative; z-index: 1; }

/* The whole card opens the task; the link's box is stretched over it. */
.card__title {
  color: var(--color-text);
  font-size: var(--text-sm);
  font-weight: 500;
  line-height: 1.4;
  text-decoration: none;

  &::after { content: ""; position: absolute; inset: 0; border-radius: inherit; }
  &:focus-visible { outline: none; }
}

.card__meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-1) var(--space-3);
  color: var(--color-muted);
  font-size: var(--text-xs);
}

.card__important {
  display: inline-flex;
  align-items: center;
  gap: 2px;
  color: var(--color-important);
  font-weight: 500;
}

.card__deadline { display: inline-flex; align-items: center; gap: var(--space-1); }

.card__deadline--overdue {
  margin-inline: calc(-1 * var(--space-1));
  padding: 1px var(--space-1);
  border-radius: var(--radius-sm);
  background: var(--color-overdue-bg);
  color: var(--color-overdue);
  font-weight: 500;
}

.card__count { display: inline-flex; align-items: center; gap: 2px; }
</style>
