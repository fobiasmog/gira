<script setup lang="ts">
import { ref, watch } from "vue"
import { storeToRefs } from "pinia"
import { useRoute } from "vue-router"
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
import { t } from "../../i18n/index.ts"

const route = useRoute()
const projects = useProjectsStore()
const { loading, notFound, announcement } = storeToRefs(useUiStore())
const wide = useMediaQuery("(min-width: 1024px)")
const drawerOpen = ref(false)
const feedbackOpen = ref(false)

watch(() => route.params.pid, (pid) => { projects.currentId = parseId(pid) }, { immediate: true })
watch(wide, (isWide) => { if (isWide) drawerOpen.value = false })
</script>

<template>
  <div class="shell">
    <div v-if="loading" class="progress" role="progressbar" :aria-label="t('common.loading')" />

    <aside v-if="wide" class="shell__sidebar">
      <SideNav>
        <template #footer>
          <button type="button" class="feedback-button" @click="feedbackOpen = true"><AppIcon name="mail" />{{ t("navigation.feedback") }}</button>
        </template>
      </SideNav>
    </aside>
    <AppDialog v-else v-model:open="drawerOpen" :title="t('navigation.menu')" drawer>
      <SideNav @navigate="drawerOpen = false">
        <template #footer>
          <button type="button" class="feedback-button" @click="drawerOpen = false; feedbackOpen = true"><AppIcon name="mail" />{{ t("navigation.feedback") }}</button>
        </template>
      </SideNav>
    </AppDialog>

    <div class="shell__main">
      <header class="shell__header">
        <button v-if="!wide" type="button" class="icon-button" :aria-label="t('navigation.menu')" @click="drawerOpen = true">
          <AppIcon name="menu" />
        </button>
        <div class="grow" />
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
}

.shell__main {
  display: flex;
  flex-direction: column;
  min-inline-size: 0;
}

.shell__header {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  min-block-size: var(--header-height);
  padding: var(--space-2) var(--space-4);
}

.shell__content {
  flex-grow: 1;
  display: flex;
  flex-direction: column;
  min-inline-size: 0;
  padding: 0 var(--space-4) var(--space-5);
}

.feedback-button {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  min-block-size: var(--target-size);
  padding: var(--space-1) var(--space-3);
  border: none;
  border-radius: var(--radius);
  background: none;
  color: #fff;

  &:hover { background: rgb(255 255 255 / 0.12); }
  &:focus-visible { outline-color: #fff; }
}

.progress {
  position: fixed;
  inset: 0 0 auto;
  z-index: 10;
  block-size: 3px;
  background: linear-gradient(90deg, transparent, var(--color-accent), transparent);
  background-size: 50% 100%;
  background-repeat: no-repeat;
  animation: progress 1.2s linear infinite;
}

@keyframes progress {
  from { background-position: -50% 0; }
  to { background-position: 150% 0; }
}

@media (prefers-reduced-motion: reduce) {
  .feedback-button {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  min-block-size: var(--target-size);
  padding: var(--space-1) var(--space-3);
  border: none;
  border-radius: var(--radius);
  background: none;
  color: #fff;

  &:hover { background: rgb(255 255 255 / 0.12); }
  &:focus-visible { outline-color: #fff; }
}

.progress { animation: none; background: var(--color-accent); }
}
</style>
