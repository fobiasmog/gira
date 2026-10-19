<script setup lang="ts">
import { ref } from "vue"
import AppIcon from "../ui/AppIcon.vue"
import type { Subtask } from "../../api/types.ts"
import { t } from "../../i18n/index.ts"

const props = defineProps<{ subtasks: Subtask[]; projectId: number; disabled?: boolean }>()
const emit = defineEmits<{ add: [title: string]; complete: [subtask: Subtask, complete: boolean] }>()
const title = ref("")

function add() {
  const value = title.value.trim()
  if (!value) return
  emit("add", value)
  title.value = ""
}
</script>

<template>
  <section class="stack" aria-labelledby="task-subtasks">
    <h2 id="task-subtasks">{{ t("task.subtasks") }}</h2>
    <ul v-if="subtasks.length" role="list" class="subtasks">
      <li v-for="subtask in subtasks" :key="subtask.id" class="subtask" :class="{ 'subtask--done': subtask.complete }">
        <input
          type="checkbox"
          :checked="subtask.complete"
          :disabled="disabled"
          :aria-label="t('task.subtaskDone', { key: subtask.key })"
          @change="emit('complete', subtask, ($event.target as HTMLInputElement).checked)"
        >
        <span class="small muted">{{ subtask.key }}</span>
        <RouterLink class="grow break-word" :to="{ name: 'task', params: { pid: props.projectId, ref: subtask.key } }">{{ subtask.title }}</RouterLink>
      </li>
    </ul>
    <form v-if="!disabled" class="row" @submit.prevent="add">
      <input v-model="title" class="input grow" maxlength="255" :aria-label="t('task.newSubtask')" :placeholder="t('task.newSubtask')">
      <button type="submit" class="icon-button" :aria-label="t('task.newSubtask')"><AppIcon name="add" /></button>
    </form>
  </section>
</template>

<style scoped>
.subtasks { display: grid; gap: var(--space-1); }

.subtask {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  padding: var(--space-2) var(--space-3);
  border-radius: var(--radius);
  background: var(--color-surface);
}

.subtask--done a { color: var(--color-muted); text-decoration: line-through; }
</style>
