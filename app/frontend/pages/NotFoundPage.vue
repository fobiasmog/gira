<script setup lang="ts">
import AppIcon from "../components/ui/AppIcon.vue"
import { t } from "../i18n/index.ts"
</script>

<template>
  <section class="page not-found">
    <h1>{{ t("notFound.title") }}</h1>
    <p class="muted">{{ t("errors.notFound") }}</p>
    <p>
      <RouterLink :to="{ name: 'projects' }" class="button button--secondary">
        <AppIcon name="folder_open" />{{ t("navigation.toProjects") }}
      </RouterLink>
    </p>
  </section>
</template>

<style scoped>
.not-found { justify-items: start; padding-block: var(--space-6); }
</style>
