<script setup lang="ts">
import { ref, watch } from "vue"
import { storeToRefs } from "pinia"
import { useRouter } from "vue-router"
import AppIcon from "../components/ui/AppIcon.vue"
import MarkdownView from "../components/MarkdownView.vue"
import UserAvatar from "../components/UserAvatar.vue"
import CommentItem from "../components/task/CommentItem.vue"
import { useArchiveStore } from "../stores/archive.ts"
import { useUiStore } from "../stores/ui.ts"
import { language, t } from "../i18n/index.ts"
import { formatDate, formatDateTime } from "../i18n/format.ts"

// An archived task, read-only (spec markdown-content, "Read-only Markdown views").
const props = defineProps<{ projectId: number; taskId: number }>()
const router = useRouter()
const archive = useArchiveStore()
const { task, comments } = storeToRefs(archive)
const ui = useUiStore()
const loaded = ref(false)

watch(() => [props.projectId, props.taskId] as const, async ([projectId, taskId]) => {
  loaded.value = false
  const ok = await ui.load(archive.loadTask(projectId, taskId).then(() => true))
  if (!ok) return
  if (!archive.task?.archived_at) {
    await router.replace({ name: "task", params: { pid: projectId, ref: archive.task!.key } })
    return
  }
  loaded.value = true
}, { immediate: true })
</script>

<template>
  <article v-if="loaded && task" class="page archived-task">
    <header class="stack">
      <p class="row small muted">
        <RouterLink :to="{ name: 'archive', params: { pid: projectId } }" class="row"><AppIcon name="chevron_left" :size="18" />{{ t("archive.title") }}</RouterLink>
        <span>· {{ task.key }}</span>
      </p>
      <h1 class="break-word">{{ task.title }}</h1>
      <p class="notice row"><AppIcon name="archive" :size="20" />{{ t("archive.readOnly") }} {{ t("archive.archivedOn", { date: formatDate(language, task.archived_at!) }) }}</p>
    </header>

    <dl class="facts small">
      <div v-if="task.status"><dt>{{ t("task.status") }}</dt><dd>{{ task.status.title }}</dd></div>
      <div><dt>{{ t("task.assignee") }}</dt><dd class="row"><UserAvatar :user="task.assignee" :size="20" />{{ task.assignee?.name ?? t("task.unassigned") }}</dd></div>
      <div v-if="task.deadline"><dt>{{ t("task.deadline") }}</dt><dd>{{ formatDateTime(language, task.deadline) }}</dd></div>
      <div v-if="task.milestone"><dt>{{ t("task.milestone") }}</dt><dd>{{ task.milestone.title }}</dd></div>
      <div v-if="task.label"><dt>{{ t("task.label") }}</dt><dd>{{ task.label.title }}</dd></div>
      <div v-if="task.sprint"><dt>{{ t("task.sprint") }}</dt><dd>{{ task.sprint.title }}</dd></div>
    </dl>

    <section class="stack" aria-labelledby="archived-description">
      <h2 id="archived-description">{{ t("task.description") }}</h2>
      <MarkdownView v-if="task.description" class="panel archived-task__description" :source="task.description" />
      <p v-else class="muted">{{ t("task.noDescription") }}</p>
    </section>

    <section v-if="task.subtasks.length" class="stack" aria-labelledby="archived-subtasks">
      <h2 id="archived-subtasks">{{ t("task.subtasks") }}</h2>
      <ul class="stack">
        <li v-for="subtask in task.subtasks" :key="subtask.id" class="row">
          <AppIcon :name="subtask.complete ? 'check_circle_filled' : 'radio_button_unchecked'" :size="18" />
          <span class="small muted">{{ subtask.key }}</span>{{ subtask.title }}
        </li>
      </ul>
    </section>

    <section class="stack" aria-labelledby="archived-comments">
      <h2 id="archived-comments">{{ t("task.comments") }}</h2>
      <ol v-if="comments.length" role="list" class="stack">
        <CommentItem v-for="comment in comments" :key="comment.id" :comment="comment" :editable="false" />
      </ol>
      <p v-else class="muted">{{ t("task.noComments") }}</p>
    </section>
  </article>
</template>

<style scoped>
.archived-task { max-inline-size: 840px; }
.notice { padding: var(--space-2) var(--space-3); border-radius: var(--radius); background: var(--color-main-lighter); color: var(--color-main-darker); }
.facts { display: flex; flex-wrap: wrap; gap: var(--space-2) var(--space-5); }
.facts dt { color: var(--color-muted); }
.facts dd { margin: 0; font-weight: 500; }
.archived-task__description { padding: var(--space-4); }
</style>
