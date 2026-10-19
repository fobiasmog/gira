<script setup lang="ts">
import { ref, watch } from "vue"
import { storeToRefs } from "pinia"
import TaskRow from "../components/board/TaskRow.vue"
import { useArchiveStore } from "../stores/archive.ts"
import { useBoardStore } from "../stores/board.ts"
import { useUiStore } from "../stores/ui.ts"
import { language, t } from "../i18n/index.ts"
import { formatDate } from "../i18n/format.ts"

const props = defineProps<{ projectId: number }>()
const archive = useArchiveStore()
const { tasks } = storeToRefs(archive)
const board = useBoardStore()
const ui = useUiStore()
const loaded = ref(false)

watch(() => props.projectId, async (id) => {
  loaded.value = false
  const result = await ui.load(Promise.all([archive.load(id), board.projectId === id ? Promise.resolve() : board.load(id)]))
  loaded.value = !!result
}, { immediate: true })
</script>

<template>
  <section v-if="loaded" class="page archive-page">
    <h1>{{ t("archive.title") }}</h1>
    <ol v-if="tasks.length" role="list" class="archive">
      <li v-for="task in tasks" :key="task.id" class="stack archive__item">
        <TaskRow
          :task="task"
          :project-id="projectId"
          :assignee="task.assignee_id ? board.memberById.get(task.assignee_id) ?? null : null"
          :label="task.label_id ? board.labelById.get(task.label_id) ?? null : null"
          archived
        >
          <template #actions>
            <span class="small muted">{{ formatDate(language, task.archived_at!) }}</span>
          </template>
        </TaskRow>
      </li>
    </ol>
    <p v-else class="empty-state panel">{{ t("archive.empty") }}</p>
  </section>
</template>

<style scoped>
.archive-page { max-inline-size: 960px; }
.archive { display: grid; gap: var(--space-1); }
</style>
