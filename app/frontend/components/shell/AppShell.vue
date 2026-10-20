<script setup lang="ts">
import { computed, ref, watch } from "vue"
import { storeToRefs } from "pinia"
import { useRoute, type RouteLocationRaw } from "vue-router"
import SideNav from "./SideNav.vue"
import UserMenu from "./UserMenu.vue"
import AppDialog from "../ui/AppDialog.vue"
import AppIcon from "../ui/AppIcon.vue"
import AppToast from "../ui/AppToast.vue"
import NotFoundPage from "../../pages/NotFoundPage.vue"
import AnnouncementsPanel from "./AnnouncementsPanel.vue"
import FeedbackDialog from "./FeedbackDialog.vue"
import { useMediaQuery } from "../../composables/useMediaQuery.ts"
import { useProjectsStore } from "../../stores/projects.ts"
import { useUiStore } from "../../stores/ui.ts"
import { parseId } from "../../router/routes.ts"
import { sectionOf } from "../../router/sections.ts"
import { t } from "../../i18n/index.ts"

const route = useRoute()
const projects = useProjectsStore()
const { loading, notFound, announcement } = storeToRefs(useUiStore())
const wide = useMediaQuery("(min-width: 1024px)")
const drawerOpen = ref(false)
const feedbackOpen = ref(false)

watch(() => route.params.pid, (pid) => { projects.currentId = parseId(pid) }, { immediate: true })

// On project screens: project / section, and / task key on a task page.
const crumbs = computed(() => {
  const project = projects.current
  const section = sectionOf(route.name)
  if (!project || !section) return []
  const key = route.name === "task" ? String(route.params.ref) : null
  const items: { label: string; to?: RouteLocationRaw }[] = [
    { label: project.title, to: { name: "board", params: { pid: project.id } } },
    { label: t(section.label), to: key ? { name: section.name, params: { pid: project.id } } : undefined },
  ]
  if (key) items.push({ label: key })
  return items
})
watch(wide, (isWide) => { if (isWide) drawerOpen.value = false })
</script>

<template>
  <div class="shell">
    <div v-if="loading" class="progress" role="progressbar" :aria-label="t('common.loading')" />

    <aside v-if="wide" class="shell__sidebar">
      <SideNav>
        <template #footer>
          <button type="button" class="feedback-button" @click="feedbackOpen = true"><AppIcon name="mail" :size="20" />{{ t("navigation.feedback") }}</button>
        </template>
      </SideNav>
    </aside>
    <AppDialog v-else v-model:open="drawerOpen" :title="t('navigation.menu')" drawer>
      <SideNav @navigate="drawerOpen = false">
        <template #footer>
          <button type="button" class="feedback-button" @click="drawerOpen = false; feedbackOpen = true"><AppIcon name="mail" :size="20" />{{ t("navigation.feedback") }}</button>
        </template>
      </SideNav>
    </AppDialog>

    <div class="shell__main">
      <header class="shell__header">
        <button v-if="!wide" type="button" class="icon-button" :aria-label="t('navigation.menu')" @click="drawerOpen = true">
          <AppIcon name="menu" />
        </button>
        <nav v-if="crumbs.length" class="breadcrumb grow" :aria-label="t('navigation.breadcrumb')">
          <ol role="list" class="breadcrumb__list">
            <li v-for="(crumb, index) in crumbs" :key="index" class="breadcrumb__item">
              <span v-if="index" class="breadcrumb__separator" aria-hidden="true"> / </span>
              <RouterLink v-if="crumb.to" :to="crumb.to" class="breadcrumb__link">{{ crumb.label }}</RouterLink>
              <span v-else class="breadcrumb__current" aria-current="page">{{ crumb.label }}</span>
            </li>
          </ol>
        </nav>
        <div v-else class="grow" />
        <UserMenu />
      </header>
      <main class="shell__content">
        <AnnouncementsPanel />
        <NotFoundPage v-if="notFound" />
        <RouterView v-else />
      </main>
    </div>

    <FeedbackDialog v-model:open="feedbackOpen" />
    <AppToast />
    <div class="visually-hidden" aria-live="polite" aria-atomic="true">{{ announcement }}</div>
  </div>
</template>

<style scoped>
.shell {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr);
  min-block-size: 100dvh;
}

.shell__sidebar {
  position: sticky;
  top: 0;
  inline-size: var(--sidebar-width);
  block-size: 100dvh;
  overflow-y: auto;
  background: var(--color-nav-bg);
}

.shell__main {
  display: flex;
  flex-direction: column;
  min-inline-size: 0;
}

.shell__header {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  min-block-size: var(--header-height);
  padding: var(--space-2) var(--space-4);
  border-block-end: 1px solid var(--color-border);
  background: var(--color-surface);
}

.shell__content {
  flex-grow: 1;
  display: flex;
  flex-direction: column;
  min-inline-size: 0;
  padding: var(--space-5) var(--space-4);
}

@media (min-width: 1024px) {
  .shell__header { padding-inline: var(--space-6) var(--space-5); }
  .shell__content { padding: var(--space-5) var(--space-6) var(--space-6); }
}

.breadcrumb { min-inline-size: 0; }

.breadcrumb__list {
  overflow: hidden;
  font-size: var(--text-sm);
  text-overflow: ellipsis;
  white-space: nowrap;
}

.breadcrumb__item { display: inline; }
.breadcrumb__separator { color: var(--color-subtle); white-space: pre; }

.breadcrumb__link {
  color: var(--color-muted);
  text-decoration: none;

  &:hover { color: var(--color-primary); text-decoration: underline; }
}

.breadcrumb__current { color: var(--color-text); font-weight: 500; }

.feedback-button {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  min-block-size: var(--target-size);
  padding: var(--space-1) var(--space-3);
  border: none;
  border-radius: var(--radius);
  background: none;
  color: var(--color-nav-text);
  text-align: start;

  &:hover { background: var(--color-nav-raised); color: var(--color-nav-strong); }
  &:focus-visible { outline-color: var(--color-nav-text); outline-offset: 0; }
}

.progress {
  position: fixed;
  inset: 0 0 auto;
  z-index: 10;
  block-size: 3px;
  background: linear-gradient(90deg, transparent, var(--color-primary), transparent);
  background-size: 50% 100%;
  background-repeat: no-repeat;
  animation: progress 1.2s linear infinite;
}

@keyframes progress {
  from { background-position: -50% 0; }
  to { background-position: 150% 0; }
}

@media (prefers-reduced-motion: reduce) {
  .progress { animation: none; background: var(--color-primary); }
}
</style>
