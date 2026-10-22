<script setup lang="ts">
import { storeToRefs } from "pinia"
import AppIcon from "../ui/AppIcon.vue"
import { useCallStore } from "../../stores/call.ts"
import { t } from "../../i18n/index.ts"

// The expanded call's heading: its project, linked to the project's board,
// the connection state, and the control that shrinks the call to the bar.
const emit = defineEmits<{ navigate: [] }>()
const call = useCallStore()
const { projectId, projectTitle, status } = storeToRefs(call)
</script>

<template>
  <header class="call-header">
    <h2 class="call-header__title">
      <AppIcon name="call" :size="20" />
      <RouterLink :to="{ name: 'board', params: { pid: projectId } }" class="call-header__link ellipsis" @click="emit('navigate')">
        {{ projectTitle }}
      </RouterLink>
    </h2>
    <button type="button" class="icon-button call-header__shrink" :aria-label="t('call.shrink')" :title="t('call.shrink')" @click="call.setView('shrink')">
      <AppIcon name="close_fullscreen" :size="20" />
    </button>
    <p v-if="status === 'connecting' || status === 'reconnecting'" class="call-header__status" role="status">
      {{ status === "connecting" ? t("call.connecting") : t("call.reconnecting") }}
    </p>
  </header>
</template>

<style scoped>
.call-header {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  align-items: center;
  gap: 0 var(--space-2);
}

.call-header__title {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  min-inline-size: 0;
  color: var(--color-nav-strong);
  font-size: var(--text-md);
}

.call-header__link {
  color: inherit;
  text-decoration: none;

  &:hover { text-decoration: underline; }
  &:focus-visible { outline-color: var(--color-nav-text); }
}

.call-header__shrink {
  color: var(--color-nav-text);

  &:hover:not(:disabled) { background: var(--color-nav-raised); color: var(--color-nav-strong); }
  &:focus-visible { outline-color: var(--color-nav-text); }
}

.call-header__status { grid-column: 1 / -1; color: var(--color-nav-muted); font-size: var(--text-sm); }
</style>
