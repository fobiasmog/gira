<script setup lang="ts">
import { computed } from "vue"

const props = defineProps<{ done: number; total: number; label: string }>()
const percent = computed(() => (props.total ? Math.round((props.done / props.total) * 100) : 0))
</script>

<template>
  <div class="progress-bar" role="progressbar" :aria-label="label" aria-valuemin="0" :aria-valuemax="total" :aria-valuenow="done" :aria-valuetext="label">
    <div class="progress-bar__fill" :style="{ inlineSize: `${percent}%` }" />
  </div>
</template>

<style scoped>
.progress-bar { block-size: 6px; border-radius: 3px; background: var(--color-border); overflow: hidden; }
.progress-bar__fill { block-size: 100%; background: var(--color-success); transition: inline-size 0.3s; }
</style>
