<script setup lang="ts">
import { computed, ref, watch } from "vue"
import { storeToRefs } from "pinia"
import { useRouter } from "vue-router"
import AppIcon from "../components/ui/AppIcon.vue"
import ConfirmDialog from "../components/ui/ConfirmDialog.vue"
import InlineEdit from "../components/ui/InlineEdit.vue"
import DescriptionEditor from "../components/DescriptionEditor.vue"
import TaskDetails from "../components/task/TaskDetails.vue"
import SubtaskList from "../components/task/SubtaskList.vue"
import CommentItem from "../components/task/CommentItem.vue"
import CommentForm from "../components/task/CommentForm.vue"
import StatusDot from "../components/board/StatusDot.vue"
import { tasksApi, type TaskFields } from "../api/tasks.ts"
import { labelsApi } from "../api/labels.ts"
import { milestonesApi } from "../api/milestones.ts"
import { sprintsApi } from "../api/sprints.ts"
import type { Comment, Milestone, Sprint, Subtask, TaskCard, TaskDetail } from "../api/types.ts"
import { useBoardStore } from "../stores/board.ts"
import { useMeStore } from "../stores/me.ts"
import { useUiStore } from "../stores/ui.ts"
import { toneOf } from "../styles/tones.ts"
import { t } from "../i18n/index.ts"

const props = defineProps<{ projectId: number; taskRef: string }>()
const router = useRouter()
const ui = useUiStore()
const board = useBoardStore()
const { columns, members, labels } = storeToRefs(board)
const { profile } = storeToRefs(useMeStore())

const task = ref<TaskDetail | null>(null)
const comments = ref<Comment[]>([])
const milestones = ref<Milestone[]>([])
const sprints = ref<Sprint[]>([])
const editingTitle = ref(false)
const confirmingArchive = ref(false)

watch(() => [props.projectId, props.taskRef] as const, async ([projectId, taskRef]) => {
  task.value = null
  const loaded = await ui.load(tasksApi.show(projectId, taskRef))
  if (!loaded) return
  if (loaded.archived_at) {
    await router.replace({ name: "archived-task", params: { pid: projectId, tid: loaded.id } })
    return
  }
  const rest = await ui.load(Promise.all([
    tasksApi.comments(projectId, loaded.id),
    milestonesApi.list(projectId),
    sprintsApi.list(projectId, "available"),
    board.projectId === projectId ? Promise.resolve() : board.load(projectId),
  ]))
  if (!rest) return
  ;[comments.value, milestones.value, sprints.value] = rest
  task.value = loaded
}, { immediate: true })

const parent = computed(() => {
  const parentId = task.value?.parent_id
  return parentId ? board.tasks.find((t) => t.id === parentId) ?? null : null
})

// The task's column, with its colour when the board has it.
const statusColumn = computed(() => {
  const status = task.value?.status
  return status ? columns.value.find((column) => column.id === status.id) ?? status : null
})

function id(): number {
  return task.value!.id
}

// Changes answer with the task (or its card); the board follows along.
function syncBoard(card: TaskCard) {
  if (board.projectId === props.projectId) board.upsertCard(card)
}

async function refresh() {
  task.value = await tasksApi.show(props.projectId, id())
  syncBoard(task.value)
}

async function run(change: () => Promise<unknown>) {
  try {
    await change()
  } catch (error) {
    ui.fail(error)
  }
}

const update = (fields: TaskFields) => run(async () => {
  task.value = await tasksApi.update(props.projectId, id(), fields)
  syncBoard(task.value)
})

async function saveDescription(description: string) {
  if (!task.value) return
  const updated = await tasksApi.update(props.projectId, id(), { description })
  task.value = updated
  syncBoard(updated)
}

// To the end of the column (the server clamps the position).
const setStatus = (columnId: number) => run(async () => {
  await tasksApi.place(props.projectId, id(), { status_id: columnId, position: Number.MAX_SAFE_INTEGER })
  await refresh()
})
const setComplete = (complete: boolean) => run(async () => {
  await tasksApi.setComplete(props.projectId, id(), complete)
  await refresh()
})
const setLabel = (labelId: number | null) => run(async () => {
  await tasksApi.setLabel(props.projectId, id(), labelId)
  await refresh()
})
const createLabel = (title: string) => run(async () => {
  const label = await labelsApi.create(props.projectId, title)
  board.labels = [...board.labels, label].sort((a, b) => a.title.localeCompare(b.title))
  await tasksApi.setLabel(props.projectId, id(), label.id)
  await refresh()
})
const setSprint = (sprintId: number | null) => run(async () => {
  await tasksApi.setSprint(props.projectId, id(), sprintId)
  await refresh()
})
const addSubtask = (title: string) => run(async () => {
  await tasksApi.addSubtask(props.projectId, id(), title)
  await refresh()
})
const completeSubtask = (subtask: Subtask, complete: boolean) => run(async () => {
  await tasksApi.setComplete(props.projectId, subtask.id, complete)
  await refresh()
})

async function postComment(body: string, files: File[]) {
  const comment = await tasksApi.addComment(props.projectId, id(), body, files)
  comments.value = [comment, ...comments.value]
}

async function saveComment(comment: Comment, body: string) {
  try {
    const updated = await tasksApi.updateComment(comment.id, body)
    comments.value = comments.value.map((c) => (c.id === updated.id ? updated : c))
  } catch (error) {
    ui.fail(error)
    throw error
  }
}

const removeComment = (comment: Comment) => run(async () => {
  await tasksApi.deleteComment(comment.id)
  comments.value = comments.value.filter((c) => c.id !== comment.id)
})

async function archive() {
  if (!task.value) return
  const { key } = task.value
  const taskId = id()
  try {
    await tasksApi.archive(props.projectId, taskId)
    board.removeTask(taskId)
    ui.toast(t("task.archived", { key }))
    await router.push({ name: "board", params: { pid: props.projectId } })
  } catch (error) {
    ui.fail(error)
  }
}
</script>

<template>
  <article v-if="task" class="page page--full task-page">
    <div class="task-page__main panel">
      <header class="task-header">
        <p class="task-header__meta">
          <span class="task-header__key">{{ task.key }}</span>
          <span v-if="task.label" class="chip ellipsis" :data-tone="toneOf(task.label.id)">{{ task.label.title }}</span>
          <span class="status-chip">
            <StatusDot v-if="statusColumn" :column="statusColumn" />
            {{ task.status.title }}
          </span>
          <RouterLink v-if="parent" :to="{ name: 'task', params: { pid: projectId, ref: parent.key } }">
            {{ t("task.parent", { key: parent.key }) }}
          </RouterLink>
        </p>
        <div class="task-header__title">
          <InlineEdit v-model:editing="editingTitle" :value="task.title" :label="t('task.title')" @commit="update({ title: $event })" />
          <h1 v-show="!editingTitle" class="grow break-word">{{ task.title }}</h1>
          <button v-show="!editingTitle" type="button" class="icon-button" :aria-label="t('task.editTitle')" @click="editingTitle = true">
            <AppIcon name="edit" :size="20" />
          </button>
        </div>
      </header>

      <section class="task-section" aria-labelledby="task-description">
        <h2 id="task-description" class="section-title">{{ t("task.description") }}</h2>
        <DescriptionEditor
          :key="task.id"
          :markdown="task.description ?? ''"
          :label="t('task.description')"
          :save="saveDescription"
          :on-error="ui.fail"
        />
      </section>

      <SubtaskList
        v-if="!task.parent_id"
        class="task-section"
        :subtasks="task.subtasks"
        :project-id="projectId"
        @add="addSubtask"
        @complete="completeSubtask"
      />

      <section class="task-section" aria-labelledby="task-comments">
        <h2 id="task-comments" class="section-title">
          {{ t("task.comments") }} <span v-if="comments.length" class="badge">{{ comments.length }}</span>
        </h2>
        <CommentForm :post="postComment" />
        <ol v-if="comments.length" role="list" class="comments">
          <CommentItem
            v-for="comment in comments"
            :key="comment.id"
            :comment="comment"
            :editable="comment.author.id === profile?.id"
            :save="(body: string) => saveComment(comment, body)"
            :remove="() => removeComment(comment)"
          />
        </ol>
        <p v-else class="muted small">{{ t("task.noComments") }}</p>
      </section>
    </div>

    <aside class="task-page__aside panel" aria-labelledby="task-details-title">
      <h2 id="task-details-title" class="section-title">{{ t("task.details") }}</h2>
      <TaskDetails
        :task="task"
        :columns="columns"
        :members="members"
        :milestones="milestones"
        :labels="labels"
        :sprints="sprints"
        @status="setStatus"
        @complete="setComplete"
        @update="update"
        @label="setLabel"
        @create-label="createLabel"
        @sprint="setSprint"
      />
      <hr class="task-page__rule">
      <button type="button" class="button button--text task-page__archive" @click="confirmingArchive = true">
        <AppIcon name="archive" :size="20" />{{ t("task.archive") }}
      </button>
    </aside>

    <ConfirmDialog
      v-model:open="confirmingArchive"
      :title="t('task.archive')"
      :message="t('task.archiveConfirm', { title: task.title })"
      :confirm-label="t('task.archive')"
      :on-confirm="archive"
    />
  </article>
</template>

<style scoped>
.task-page {
  grid-template-columns: minmax(0, 1fr);
  align-items: start;
  gap: var(--space-4);
  max-inline-size: 1240px;
}

@media (min-width: 1200px) {
  .task-page { grid-template-columns: minmax(0, 1fr) 360px; }
  .task-page__aside { position: sticky; top: var(--space-4); }
}

.task-page__main {
  display: grid;
  gap: var(--space-6);
  min-inline-size: 0;
  padding: var(--space-5);
}

@media (max-width: 600px) {
  .task-page__main { padding: var(--space-4); }
}

.task-header { display: grid; gap: var(--space-3); }

.task-header__meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-2);
  font-size: var(--text-sm);
}

.task-header__key { color: var(--color-muted); font-weight: 500; }

.status-chip {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 0 var(--space-2);
  border: 1px solid var(--color-border);
  border-radius: 999px;
  color: var(--color-text);
  font-size: var(--text-xs);
  font-weight: 500;
  line-height: 1.8;
}

.task-header__title { display: flex; align-items: flex-start; gap: var(--space-2); }
.task-header__title h1 { padding-block-start: 2px; }

.task-section { display: grid; gap: var(--space-3); }
.comments { display: grid; gap: var(--space-4); }

.task-page__aside { display: grid; gap: var(--space-4); padding: var(--space-5) var(--space-4); }

.task-page__rule { margin: 0; border: none; border-block-start: 1px solid var(--color-border); }
.task-page__archive { justify-self: start; color: var(--color-muted); }
</style>
