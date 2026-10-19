<script setup lang="ts">
import { onMounted, ref, watch } from "vue"
import { storeToRefs } from "pinia"
import AppIcon from "./AppIcon.vue"
import { useUiStore } from "../../stores/ui.ts"
import { t } from "../../i18n/index.ts"

// A manual popover so toasts sit above open dialogs, and a polite live region
// that stays in the top layer for the app's lifetime, so screen readers
// announce messages as they are added.
const ui = useUiStore()
const { toasts } = storeToRefs(ui)
const region = ref<HTMLElement>()

onMounted(() => region.value?.showPopover())

// Re-showing moves the region to the top of the top layer, above any modal
// dialog opened since.
watch(() => toasts.value.length, (count, previous) => {
  if (count > previous && region.value) {
    region.value.hidePopover()
    region.value.showPopover()
  }
}, { flush: "pre" })
</script>

<template>
  <div ref="region" popover="manual" class="toasts" role="status" aria-live="polite">
    <p v-for="toast in toasts" :key="toast.id" class="toast" :class="`toast--${toast.kind}`">
      <span class="grow">{{ toast.message }}</span>
      <button type="button" class="icon-button toast__close" :aria-label="t('common.close')" @click="ui.dismiss(toast.id)">
        <AppIcon name="close" :size="20" />
      </button>
    </p>
  </div>
</template>

<style scoped>
.toasts {
  position: fixed;
  inset: auto var(--space-4) var(--space-4) auto;
  display: grid;
  gap: var(--space-2);
  inline-size: min(400px, 100vw - 2 * var(--space-4));
  overflow: visible;
  background: none;
  pointer-events: none;
}

.toast {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  padding: var(--space-2) var(--space-2) var(--space-2) var(--space-4);
  border-radius: var(--radius);
  background: var(--color-main-darker);
  color: #fff;
  box-shadow: var(--shadow-popover);
  pointer-events: auto;
}

.toast--error { background: var(--color-danger); }

.toast__close { color: inherit; }
.toast__close:hover:not(:disabled) { background: rgb(255 255 255 / 0.15); color: inherit; }
</style>
