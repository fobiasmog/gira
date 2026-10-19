<script setup lang="ts">
import { nextTick, onMounted, ref, watch } from "vue"

// Grows with its content: CSS field-sizing where supported, otherwise the
// height is set from scrollHeight on input.
const model = defineModel<string>({ required: true })
const textarea = ref<HTMLTextAreaElement>()
const supportsFieldSizing = typeof CSS !== "undefined" && CSS.supports("field-sizing: content")

function resize() {
  const el = textarea.value
  if (supportsFieldSizing || !el) return
  el.style.height = "auto"
  el.style.height = `${el.scrollHeight + el.offsetHeight - el.clientHeight}px`
}

watch(model, () => nextTick(resize))
onMounted(resize)

defineExpose({ focus: () => textarea.value?.focus() })
</script>

<template>
  <textarea ref="textarea" v-model="model" class="input" rows="2" />
</template>
