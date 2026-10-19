<script setup lang="ts">
import { computed, ref, watch } from "vue"
import { useRouter } from "vue-router"
import AppIcon from "../components/ui/AppIcon.vue"
import ConfirmDialog from "../components/ui/ConfirmDialog.vue"
import ProjectForm from "../components/project/ProjectForm.vue"
import type { ProjectFields } from "../api/projects.ts"
import { useProjectsStore } from "../stores/projects.ts"
import { useUiStore } from "../stores/ui.ts"
import { t } from "../i18n/index.ts"

// Owner only: other members get the not-found screen, as the API forbids it.
const props = defineProps<{ projectId: number }>()
const router = useRouter()
const projects = useProjectsStore()
const ui = useUiStore()
const project = computed(() => projects.list.find((p) => p.id === props.projectId) ?? null)
const confirmingArchive = ref(false)

watch(project, (value) => {
  if (projects.loaded && (!value || !value.owned_by_me)) ui.notFound = true
}, { immediate: true })

async function save(fields: ProjectFields) {
  await projects.update(props.projectId, fields)
  ui.toast(t("projects.saved"))
}

async function archive() {
  const title = project.value?.title ?? ""
  try {
    await projects.archive(props.projectId)
    ui.toast(t("projects.archived", { title }))
    await router.push({ name: "projects" })
  } catch (error) {
    ui.fail(error)
  }
}
</script>

<template>
  <section v-if="project?.owned_by_me" class="page">
    <h1>{{ t("projects.settings") }}</h1>
    <ProjectForm
      :key="project.id"
      :initial="{ title: project.title, short_name: project.short_name }"
      :submit-label="t('common.save')"
      :submit="save"
    />
    <section class="stack danger-zone" aria-labelledby="archive-project">
      <h2 id="archive-project">{{ t("projects.archive") }}</h2>
      <p class="muted">{{ t("projects.archiveHint") }}</p>
      <p>
        <button type="button" class="button button--danger" @click="confirmingArchive = true">
          <AppIcon name="archive" :size="20" />{{ t("projects.archive") }}
        </button>
      </p>
    </section>
    <ConfirmDialog
      v-model:open="confirmingArchive"
      :title="t('projects.archive')"
      :message="t('projects.archiveConfirm', { title: project.title })"
      :confirm-label="t('projects.archive')"
      danger
      :on-confirm="archive"
    />
  </section>
</template>

<style scoped>
.danger-zone { max-inline-size: 480px; padding-block-start: var(--space-4); border-block-start: 1px solid var(--color-border); }
</style>
