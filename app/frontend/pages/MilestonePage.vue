<script setup lang="ts">
import { ref, watch } from "vue"
import { storeToRefs } from "pinia"
import { useRouter } from "vue-router"
import AppIcon from "../components/ui/AppIcon.vue"
import ConfirmDialog from "../components/ui/ConfirmDialog.vue"
import ProgressBar from "../components/ProgressBar.vue"
import TaskRow from "../components/board/TaskRow.vue"
import { useBoardStore } from "../stores/board.ts"
import { useMilestonesStore } from "../stores/milestones.ts"
import { useUiStore } from "../stores/ui.ts"
import { t } from "../i18n/index.ts"

const props = defineProps<{ projectId: number; milestoneId: number }>()
const router = useRouter()
const store = useMilestonesStore()
const { current } = storeToRefs(store)
const board = useBoardStore()
const ui = useUiStore()
const loaded = ref(false)
const confirmingDelete = ref(false)

watch(() => [props.projectId, props.milestoneId] as const, async ([projectId, milestoneId]) => {
  loaded.value = false
  const result = await ui.load(Promise.all([
    store.loadOne(projectId, milestoneId),
    board.projectId === projectId ? Promise.resolve() : board.load(projectId),
  ]))
  loaded.value = !!result && current.value?.id === milestoneId
}, { immediate: true })

async function remove() {
  const milestone = current.value
  if (!milestone) return
  try {
    await store.remove(props.projectId, milestone.id)
    ui.toast(t("milestones.deleted", { title: milestone.title }))
    await router.push({ name: "milestones", params: { pid: props.projectId } })
  } catch (error) {
    ui.fail(error)
  }
}
</script>

<template>
  <section v-if="loaded && current" class="page milestone-page">
    <header class="page__header">
      <h1 class="grow break-word">{{ current.title }}</h1>
      <button type="button" class="button button--text" @click="confirmingDelete = true"><AppIcon name="delete" :size="20" />{{ t("milestones.delete") }}</button>
    </header>
    <ProgressBar :done="current.done" :total="current.total" :label="t('milestones.progress', { done: current.done, total: current.total })" />
    <p class="small muted">{{ t("milestones.progress", { done: current.done, total: current.total }) }}</p>

    <ol v-if="current.tasks.length" role="list" class="milestone-tasks row-list">
      <li v-for="task in current.tasks" :key="task.id">
        <TaskRow
          :task="task"
          :project-id="projectId"
          :assignee="task.assignee_id ? board.memberById.get(task.assignee_id) ?? null : null"
          :label="task.label_id ? board.labelById.get(task.label_id) ?? null : null"
        />
      </li>
    </ol>
    <p v-else class="empty-state panel">{{ t("milestones.noTasks") }}</p>

    <ConfirmDialog
      v-model:open="confirmingDelete"
      :title="t('milestones.delete')"
      :message="t('milestones.deleteConfirm', { title: current.title })"
      :confirm-label="t('common.delete')"
      danger
      :on-confirm="remove"
    />
  </section>
</template>

<style scoped>
.milestone-page { max-inline-size: 960px; }
</style>
