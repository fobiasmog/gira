<script setup lang="ts">
import { computed } from "vue"
import AppIcon from "../ui/AppIcon.vue"
import ProgressBar from "../ProgressBar.vue"
import PhasePill from "./PhasePill.vue"
import type { ChangePhase, ChangeReference, Column, TaskCard } from "../../api/types.ts"
import { boardProgress } from "../../composables/changes.ts"
import { changeLocation } from "../../router/routes.ts"
import { t } from "../../i18n/index.ts"

// Above the board of a change (spec web-client, "Board change summary"): its
// name, linking to the change's page, its phase, how many of the board's
// cards are in the done column, and its archive action.
const props = defineProps<{ projectId: number; change: ChangeReference; phase: ChangePhase | null; columns: Column[]; tasks: TaskCard[] }>()
const emit = defineEmits<{ archive: [] }>()

const progress = computed(() => boardProgress(props.columns, props.tasks))
const progressText = computed(() => t("board.summary.progress", { done: progress.value.done, total: progress.value.total }))
</script>

<template>
  <section class="change-summary" :aria-label="t('board.summary.label')">
    <AppIcon name="flag" :size="18" class="change-summary__icon" />
    <RouterLink :to="changeLocation(projectId, { ...change, archived_at: null })" class="change-summary__name ellipsis">{{ change.name }}</RouterLink>
    <PhasePill v-if="phase" :phase="phase" />
    <span class="change-summary__progress">
      <ProgressBar :done="progress.done" :total="progress.total" :label="progressText" class="change-summary__bar" />
      <span>{{ progressText }}</span>
    </span>
    <button type="button" class="button button--text change-summary__archive" @click="emit('archive')">
      <AppIcon name="archive" :size="18" />{{ t("board.summary.archive") }}
    </button>
  </section>
</template>

<style scoped>
.change-summary {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-1) var(--space-3);
  color: var(--color-muted);
  font-size: var(--text-sm);
}

.change-summary__icon { color: var(--color-primary); }

.change-summary__name {
  max-inline-size: 24rem;
  color: var(--color-text);
  font-weight: 500;
  text-decoration: none;

  &:hover { color: var(--color-primary); text-decoration: underline; }
}

.change-summary__progress { display: inline-flex; align-items: center; gap: var(--space-2); }
.change-summary__bar { inline-size: 120px; }
.change-summary__archive { --target-size: 32px; padding-inline: var(--space-2); }
</style>
