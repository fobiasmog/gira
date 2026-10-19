<script setup lang="ts">
import { computed } from "vue"
import type { Column } from "../../api/types.ts"
import { columnDot } from "../../styles/tones.ts"

// A column's decorative colour dot; the column's title carries the meaning.
const props = defineProps<{ column: Pick<Column, "id" | "done"> & { color?: string | null } }>()
const dot = computed(() => columnDot(props.column))
</script>

<template>
  <span
    class="dot"
    aria-hidden="true"
    :data-tone="dot.kind === 'tone' ? dot.tone : undefined"
    :data-done="dot.kind === 'done' ? '' : undefined"
    :style="dot.kind === 'color' ? { '--dot-color': dot.color } : undefined"
  />
</template>
