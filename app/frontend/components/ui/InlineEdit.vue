<script setup lang="ts">
import { nextTick, ref, watch } from "vue"

// A text input that commits on Enter or blur and cancels on Escape. Rendered
// while `editing` is true; the parent shows the plain text otherwise.
const props = defineProps<{ value: string; label: string; maxlength?: number }>()
const editing = defineModel<boolean>("editing", { required: true })
const emit = defineEmits<{ commit: [value: string] }>()

const input = ref<HTMLInputElement>()
const draft = ref(props.value)
let done = false

watch(editing, async (value) => {
  if (!value) return
  draft.value = props.value
  done = false
  await nextTick()
  input.value?.focus()
  input.value?.select()
}, { immediate: true })

function finish(save: boolean) {
  if (done) return
  done = true
  const value = draft.value.trim()
  editing.value = false
  if (save && value && value !== props.value) emit("commit", value)
}
</script>

<template>
  <input
    v-if="editing"
    ref="input"
    v-model="draft"
    class="input"
    :aria-label="label"
    :maxlength="maxlength ?? 255"
    @keydown.enter.prevent="finish(true)"
    @keydown.esc.stop.prevent="finish(false)"
    @blur="finish(true)"
  >
</template>
