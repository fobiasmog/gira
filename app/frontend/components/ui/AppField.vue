<script setup lang="ts">
import { computed, useId } from "vue"

// A labelled form field. The slot receives the attributes its control needs
// to be linked to the label and the error message.
const props = defineProps<{ label: string; errors?: string[]; hint?: string; hideLabel?: boolean }>()
defineSlots<{ default(props: { control: Record<string, string | boolean | undefined> }): unknown }>()

const id = useId()
const errorId = `${id}-error`
const hintId = `${id}-hint`
const error = computed(() => props.errors?.join(" ") || "")
const control = computed(() => ({
  id,
  "aria-invalid": error.value ? "true" : undefined,
  "aria-describedby": [error.value && errorId, props.hint && hintId].filter(Boolean).join(" ") || undefined,
}))
</script>

<template>
  <div class="field">
    <label :for="id" class="field__label" :class="{ 'visually-hidden': hideLabel }">{{ label }}</label>
    <slot :control="control" />
    <p v-if="hint" :id="hintId" class="small muted">{{ hint }}</p>
    <p v-if="error" :id="errorId" class="field__error">{{ error }}</p>
  </div>
</template>
