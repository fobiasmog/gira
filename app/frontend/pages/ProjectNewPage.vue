<script setup lang="ts">
import { useRouter } from "vue-router"
import ProjectForm from "../components/project/ProjectForm.vue"
import type { ProjectFields } from "../api/projects.ts"
import { useProjectsStore } from "../stores/projects.ts"
import { t } from "../i18n/index.ts"

const router = useRouter()
const projects = useProjectsStore()

async function create(fields: ProjectFields) {
  const project = await projects.create(fields)
  await router.push({ name: "board", params: { pid: project.id } })
}
</script>

<template>
  <section class="page">
    <h1>{{ t("projects.newTitle") }}</h1>
    <ProjectForm :submit-label="t('projects.create')" :submit="create" />
  </section>
</template>
