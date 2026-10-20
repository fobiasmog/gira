<script setup lang="ts">
import { nextTick, onBeforeUnmount, ref, useId, watch } from "vue"
import AppIcon from "./AppIcon.vue"
import { t } from "../../i18n/index.ts"

// A modal <dialog>: the browser contains focus, makes the page inert and
// closes it on Escape. Focus goes back to whatever opened it.
defineProps<{ title: string; wide?: boolean; drawer?: boolean }>()
const open = defineModel<boolean>("open", { required: true })
const emit = defineEmits<{ closed: [] }>()

const dialog = ref<HTMLDialogElement>()
const titleId = useId()
let opener: HTMLElement | null = null

function show() {
  if (!dialog.value || dialog.value.open) return
  opener = document.activeElement instanceof HTMLElement ? document.activeElement : null
  dialog.value.showModal()
}

watch(open, async (value) => {
  await nextTick()
  if (value) show()
  else if (dialog.value?.open) dialog.value.close()
}, { immediate: true })

function onClose() {
  open.value = false
  opener?.focus()
  opener = null
  emit("closed")
}

// A click whose target is the <dialog> itself landed on the backdrop.
function onClick(event: MouseEvent) {
  if (event.target === dialog.value) dialog.value?.close()
}

onBeforeUnmount(() => {
  if (dialog.value?.open) dialog.value.close()
})
</script>

<template>
  <dialog
    ref="dialog"
    class="dialog"
    :class="{ 'dialog--wide': wide, 'dialog--drawer': drawer }"
    :aria-labelledby="titleId"
    @close="onClose"
    @click="onClick"
  >
    <div class="dialog__body">
      <header class="dialog__header">
        <h2 :id="titleId" class="dialog__title">{{ title }}</h2>
        <button type="button" class="icon-button" :aria-label="t('common.close')" @click="dialog?.close()">
          <AppIcon name="close" />
        </button>
      </header>
      <slot />
      <footer v-if="$slots.actions" class="dialog__actions">
        <slot name="actions" />
      </footer>
    </div>
  </dialog>
</template>

<style scoped>
.dialog {
  inline-size: min(480px, 100vw - 2 * var(--space-4));
  max-block-size: calc(100dvh - 2 * var(--space-4));
  border-radius: var(--radius-lg);
  background: var(--color-surface);
  box-shadow: var(--shadow-popover);

  &::backdrop { background: rgb(43 29 63 / 0.4); }
}

.dialog--wide { inline-size: min(720px, 100vw - 2 * var(--space-4)); }

.dialog--drawer {
  inline-size: min(300px, 85vw);
  block-size: 100dvh;
  max-block-size: none;
  margin: 0;
  border-radius: 0;
}

/* The navigation drawer takes the sidebar's colours. */
.dialog--drawer { background: var(--color-nav-bg); color: var(--color-nav-text); }
.dialog--drawer .icon-button { color: var(--color-nav-text); }
.dialog--drawer .icon-button:hover { background: var(--color-nav-raised); color: var(--color-nav-strong); }
.dialog--drawer .icon-button:focus-visible { outline-color: var(--color-nav-text); }

.dialog--drawer .dialog__body { block-size: 100%; grid-template-rows: auto 1fr; padding: var(--space-2) 0 0; }
.dialog--drawer .dialog__header { margin: 0; padding-inline: var(--space-4) var(--space-2); color: var(--color-nav-strong); }

@media (prefers-reduced-motion: no-preference) {
  .dialog[open] {
    transition: opacity 0.15s, translate 0.15s;

    @starting-style {
      opacity: 0;
      translate: 0 8px;
    }
  }
}

.dialog__body {
  display: grid;
  gap: var(--space-4);
  padding: var(--space-5);
}

.dialog__header {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  margin-block: calc(-1 * var(--space-2));
}

.dialog__title { flex-grow: 1; }

.dialog__actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: var(--space-2);
}
</style>
