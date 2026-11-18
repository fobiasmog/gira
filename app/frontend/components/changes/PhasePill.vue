<script lang="ts">
import type { ChangePhase } from "../../api/types.ts"
import { t } from "../../i18n/index.ts"

// A phase's name in the viewer's language.
export function phaseName(phase: ChangePhase): string {
  return t(`changes.phases.${phase}`)
}
</script>

<script setup lang="ts">
// A change's phase as a small outlined tag (spec web-client, "Board change
// tabs", "Board change summary" and "Changes screen").
defineProps<{ phase: ChangePhase }>()
</script>

<template>
  <span class="phase-pill" :data-phase="phase">{{ phaseName(phase) }}</span>
</template>

<style scoped>
.phase-pill {
  display: inline-block;
  flex: none;
  padding: 0 6px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  color: var(--color-muted);
  font-size: var(--text-xs);
  font-weight: 500;
  line-height: 1.6;
  white-space: nowrap;
}
</style>
