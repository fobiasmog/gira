<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from "vue"
import { storeToRefs } from "pinia"
import CallControls from "./CallControls.vue"
import CallHeader from "./CallHeader.vue"
import CallTiles from "./CallTiles.vue"
import { useCallStore } from "../../stores/call.ts"
import { t } from "../../i18n/index.ts"

// The expanded call on narrow screens: a modal <dialog> over the whole
// screen. The browser contains focus and makes the page inert. Escape shrinks
// the call to the bar instead of closing the dialog; AppDialog is not used
// because it closes on Escape.
const call = useCallStore()
const { projectTitle } = storeToRefs(call)
const dialog = ref<HTMLDialogElement>()

function onCancel(event: Event) {
  event.preventDefault()
  call.setView("shrink")
}

onMounted(() => dialog.value?.showModal())
onBeforeUnmount(() => dialog.value?.close())
</script>

<template>
  <dialog ref="dialog" class="call-overlay" :aria-label="t('call.callIn', { project: projectTitle })" @cancel="onCancel">
    <!-- Following the project link shows its board, so the call shrinks. -->
    <CallHeader @navigate="call.setView('shrink')" />
    <CallTiles />
    <CallControls />
  </dialog>
</template>

<style scoped>
.call-overlay {
  inline-size: 100vw;
  max-inline-size: none;
  block-size: 100dvh;
  max-block-size: none;
  margin: 0;
  padding: var(--space-3) var(--space-4) calc(var(--space-4) + env(safe-area-inset-bottom));
  border: none;
  background: var(--color-nav-bg);
  color: var(--color-nav-text);

  &[open] {
    display: grid;
    grid-template-rows: auto minmax(0, 1fr) auto;
    gap: var(--space-3);
  }

  &::backdrop { background: var(--color-nav-bg); }
}
</style>
