<script setup lang="ts">
import { computed } from "vue"
import { storeToRefs } from "pinia"
import AppIcon from "../ui/AppIcon.vue"
import { useCallStore } from "../../stores/call.ts"
import { t, tc } from "../../i18n/index.ts"

// The hidden call: a small tab at the bottom edge that says the member is in
// a call, how many take part and whether their microphone is off. It brings
// the bar back.
const call = useCallStore()
const { participants, micOn } = storeToRefs(call)
const label = computed(() =>
  [t("call.show"), tc("call.participantCount", participants.value.length), ...(micOn.value ? [] : [t("call.micOff")])].join(", "))
</script>

<template>
  <button type="button" class="call-tab" :aria-label="label" :title="label" @click="call.setView('show')">
    <AppIcon name="call" :size="18" />
    <span>{{ participants.length }}</span>
    <AppIcon v-if="!micOn" name="mic_off" :size="18" class="call-tab__muted" />
  </button>
</template>

<style scoped>
.call-tab {
  position: fixed;
  inset: auto var(--space-5) 0 auto;
  z-index: 5;
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
  block-size: calc(var(--call-tab-height) + env(safe-area-inset-bottom));
  padding: 0 var(--space-4) env(safe-area-inset-bottom);
  border: none;
  border-radius: var(--radius) var(--radius) 0 0;
  background: var(--color-nav-bg);
  color: var(--color-nav-strong);
  font-size: var(--text-sm);
  font-weight: 500;
  box-shadow: var(--shadow-popover);

  &:hover { background: var(--color-nav-raised); }
  &:focus-visible { outline-color: var(--color-main-dark); }
}

.call-tab__muted { color: var(--color-accent); }
</style>
