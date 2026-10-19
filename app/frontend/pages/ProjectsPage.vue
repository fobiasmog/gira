<script setup lang="ts">
import { onMounted } from "vue"
import { storeToRefs } from "pinia"
import AppIcon from "../components/ui/AppIcon.vue"
import { useProjectsStore } from "../stores/projects.ts"
import { useUiStore } from "../stores/ui.ts"
import { t } from "../i18n/index.ts"

const projects = useProjectsStore()
const { list } = storeToRefs(projects)
const ui = useUiStore()

onMounted(() => ui.load(projects.load()))
</script>

<template>
  <section class="page">
    <header class="page__header">
      <h1 class="grow">{{ t("projects.title") }}</h1>
      <RouterLink :to="{ name: 'project-new' }" class="button"><AppIcon name="add" />{{ t("projects.newTitle") }}</RouterLink>
    </header>

    <ul v-if="list.length" role="list" class="projects">
      <li v-for="project in list" :key="project.id">
        <RouterLink :to="{ name: 'board', params: { pid: project.id } }" class="project panel">
          <span class="project__key">{{ project.short_name }}</span>
          <span class="project__title break-word">{{ project.title }}</span>
          <span v-if="project.owned_by_me" class="chip">{{ t("projects.owner") }}</span>
        </RouterLink>
      </li>
    </ul>
    <div v-else class="empty-state panel stack">
      <p>{{ t("projects.empty") }}</p>
      <p><RouterLink :to="{ name: 'project-new' }" class="button">{{ t("projects.createFirst") }}</RouterLink></p>
    </div>
  </section>
</template>

<style scoped>
.projects {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
  gap: var(--space-3);
}

.project {
  display: grid;
  gap: var(--space-1);
  justify-items: start;
  block-size: 100%;
  padding: var(--space-4);
  color: var(--color-text);
  text-decoration: none;

  &:hover { box-shadow: var(--shadow-hover); color: var(--color-text); }
}

.project__key { font-size: var(--text-sm); font-weight: 500; color: var(--color-muted); }
.project__title { font-size: var(--text-lg); font-weight: 500; }
</style>
