<script setup lang="ts">
import { computed, ref } from "vue"
import AppIcon from "../ui/AppIcon.vue"
import ProgressBar from "../ProgressBar.vue"
import type { Subtask } from "../../api/types.ts"
import { t } from "../../i18n/index.ts"

const props = defineProps<{ subtasks: Subtask[]; projectId: number; disabled?: boolean }>()
const emit = defineEmits<{ add: [title: string]; complete: [subtask: Subtask, complete: boolean] }>()
const title = ref("")

const done = computed(() => props.subtasks.filter((subtask) => subtask.complete).length)
const progress = computed(() => t("task.subtaskProgress", { done: done.value, total: props.subtasks.length }))

function add() {
  const value = title.value.trim()
  if (!value) return
  emit("add", value)
  title.value = ""
}
</script>

<template>
  <section class="subtasks" aria-labelledby="task-subtasks">
    <div class="subtasks__header">
      <h2 id="task-subtasks" class="section-title">{{ t("task.subtasks") }}</h2>
      <template v-if="subtasks.length">
        <span class="subtasks__progress">{{ progress }}</span>
        <ProgressBar :done="done" :total="subtasks.length" :label="progress" class="subtasks__bar" />
      </template>
    </div>
    <ul v-if="subtasks.length || !disabled" role="list" class="subtasks__list row-list">
      <li v-for="subtask in subtasks" :key="subtask.id" class="subtask" :class="{ 'subtask--done': subtask.complete }">
        <input
          type="checkbox"
          :checked="subtask.complete"
          :disabled="disabled"
          :aria-label="t('task.subtaskDone', { key: subtask.key })"
          @change="emit('complete', subtask, ($event.target as HTMLInputElement).checked)"
        >
        <span class="subtask__key">{{ subtask.key }}</span>
        <RouterLink class="subtask__title grow break-word" :to="{ name: 'task', params: { pid: props.projectId, ref: subtask.key } }">{{ subtask.title }}</RouterLink>
      </li>
      <li v-if="!disabled" class="subtask subtask--new">
        <form class="subtask__form" @submit.prevent="add">
          <AppIcon name="add" :size="20" class="subtask__add-icon" />
          <input v-model="title" class="input" maxlength="255" :aria-label="t('task.newSubtask')" :placeholder="t('task.newSubtask')">
          <button type="submit" class="button button--secondary" :disabled="!title.trim()">{{ t("common.create") }}</button>
        </form>
      </li>
    </ul>
  </section>
</template>

<style scoped>
.subtasks { display: grid; gap: var(--space-3); }

.subtasks__header {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-2) var(--space-3);
}

.subtasks__progress { margin-inline-start: auto; color: var(--color-muted); font-size: var(--text-sm); }
.subtasks__bar { inline-size: 140px; }

.subtask {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  min-block-size: 48px;
  padding: var(--space-2) var(--space-3);
  font-size: var(--text-sm);
}

.subtask input[type="checkbox"] { inline-size: 18px; block-size: 18px; margin: 0; flex: none; }
.subtask__key { flex: none; color: var(--color-muted); font-size: var(--text-xs); font-weight: 500; }

.subtask__title {
  border-radius: var(--radius-sm);
  color: var(--color-text);
  text-decoration: none;

  &:hover { color: var(--color-primary); text-decoration: underline; }
}

.subtask--done .subtask__title { color: var(--color-muted); text-decoration: line-through; }

.subtask__form { display: flex; flex-grow: 1; align-items: center; gap: var(--space-3); }
.subtask__add-icon { color: var(--color-muted); }
</style>
