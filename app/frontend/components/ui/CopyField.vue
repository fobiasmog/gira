<script setup lang="ts">
import { ref } from "vue"
import AppField from "./AppField.vue"
import { useUiStore } from "../../stores/ui.ts"
import { t } from "../../i18n/index.ts"

// A read-only value to copy, such as a secret or a command: the whole of it
// is selected on focus, and the button copies it. When the clipboard is
// refused, the value is selected for the person to copy.
const props = defineProps<{ label: string; value: string; copyLabel: string; hideLabel?: boolean; multiline?: boolean }>()
const ui = useUiStore()
const field = ref<HTMLInputElement | HTMLTextAreaElement>()

async function copy() {
  try {
    await navigator.clipboard.writeText(props.value)
    ui.toast(t("common.copied"))
  } catch {
    field.value?.select()
    ui.toast(t("common.copyFailed"), "error")
  }
}

const select = (event: FocusEvent) => (event.target as HTMLInputElement | HTMLTextAreaElement).select()
</script>

<template>
  <div class="row copy-field">
    <AppField class="grow" :label="label" :hide-label="hideLabel">
      <template #default="{ control }">
        <textarea v-if="multiline" ref="field" v-bind="control" class="input copy-field__value copy-field__value--wrap" rows="2" readonly spellcheck="false" :value="value" @focus="select" />
        <input v-else ref="field" v-bind="control" class="input copy-field__value" :value="value" readonly spellcheck="false" @focus="select">
      </template>
    </AppField>
    <button type="button" class="button button--secondary" @click="copy">{{ copyLabel }}</button>
  </div>
</template>

<style scoped>
.copy-field { align-items: flex-end; }

.copy-field__value {
  font-family: var(--font-mono, monospace);
  font-size: var(--text-sm);
}

/* One long line, wrapped, so the whole of it can be read before copying. */
textarea.copy-field__value--wrap { resize: vertical; white-space: pre-wrap; overflow-wrap: anywhere; }
</style>
