<script setup lang="ts">
import { storeToRefs } from "pinia"
import AppIcon from "../ui/AppIcon.vue"
import CallControls from "./CallControls.vue"
import { useCallStore } from "../../stores/call.ts"
import { t, tc } from "../../i18n/index.ts"

// The shrunk call, docked at the bottom of the screen: its project, the
// number of participants and the main controls. The shell keeps page content
// clear of it (--call-dock-height).
const call = useCallStore()
const { projectId, projectTitle, participants, status } = storeToRefs(call)
</script>

<template>
  <section class="call-bar" :aria-label="t('call.callIn', { project: projectTitle })">
    <div class="call-bar__info">
      <RouterLink :to="{ name: 'board', params: { pid: projectId } }" class="call-bar__project ellipsis">{{ projectTitle }}</RouterLink>
      <span class="call-bar__count">
        {{ status === "reconnecting" ? t("call.reconnecting") : tc("call.participantCount", participants.length) }}
      </span>
    </div>
    <CallControls compact />
    <button type="button" class="call-bar__button" :aria-label="t('call.expand')" :title="t('call.expand')" @click="call.setView('expand')">
      <AppIcon name="open_in_full" :size="20" />
    </button>
    <button type="button" class="call-bar__button" :aria-label="t('call.hide')" :title="t('call.hide')" @click="call.setView('hide')">
      <AppIcon name="keyboard_arrow_down" :size="20" />
    </button>
  </section>
</template>

<style scoped>
.call-bar {
  position: fixed;
  inset: auto 0 0;
  z-index: 5;
  display: flex;
  align-items: center;
  gap: var(--space-2);
  block-size: calc(var(--call-bar-height) + env(safe-area-inset-bottom));
  padding: 0 var(--space-3) env(safe-area-inset-bottom);
  background: var(--color-nav-bg);
  color: var(--color-nav-text);
  box-shadow: var(--shadow-popover);
}

.call-bar__info {
  display: grid;
  flex-grow: 1;
  min-inline-size: 0;
  font-size: var(--text-sm);
  line-height: 1.3;
}

.call-bar__project {
  color: var(--color-nav-strong);
  font-weight: 500;
  text-decoration: none;

  &:hover { text-decoration: underline; }
  &:focus-visible { outline-color: var(--color-nav-text); }
}

.call-bar__count { color: var(--color-nav-muted); font-size: var(--text-xs); }

.call-bar__button {
  display: inline-grid;
  place-items: center;
  flex: none;
  inline-size: 40px;
  block-size: 40px;
  border: none;
  border-radius: var(--radius);
  background: none;
  color: var(--color-nav-text);

  &:hover { background: var(--color-nav-raised); color: var(--color-nav-strong); }
  &:focus-visible { outline-color: var(--color-nav-text); }
}

@media (min-width: 1024px) {
  .call-bar { padding-inline: var(--space-5); }
}
</style>
