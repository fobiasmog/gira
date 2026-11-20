<script setup lang="ts">
import { computed } from "vue"
import AppIcon from "../ui/AppIcon.vue"
import ProgressBar from "../ProgressBar.vue"
import type { ChangeReference, Column, TaskCard } from "../../api/types.ts"
import { boardProgress } from "../../composables/changes.ts"
import { changeLocation } from "../../router/routes.ts"
import { t } from "../../i18n/index.ts"

// Above the board of a change (spec web-client, "Board change summary"): a
// link that opens the change's page, and how many of the board's
// cards are in the done column. Changes are archived from their page and
// from the changes screen.
const props = defineProps<{ projectId: number; change: ChangeReference; columns: Column[]; tasks: TaskCard[] }>()

const progress = computed(() => boardProgress(props.columns, props.tasks))
const progressText = computed(() => t("board.summary.progress", { done: progress.value.done, total: progress.value.total }))
</script>

<template>
  <section class="change-summary" :aria-label="t('board.summary.label')">
    <AppIcon name="flag" :size="18" class="change-summary__icon" />
    <!-- The tab names the change; the hidden name tells it to assistive technology. -->
    <RouterLink :to="changeLocation(projectId, { ...change, archived_at: null })" class="change-summary__name ellipsis">
      {{ t("board.summary.open") }}<span class="visually-hidden"> {{ change.name }}</span>
    </RouterLink>
    <span class="change-summary__progress">
      <ProgressBar :done="progress.done" :total="progress.total" :label="progressText" class="change-summary__bar" />
      <span>{{ progressText }}</span>
    </span>
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
</style>
