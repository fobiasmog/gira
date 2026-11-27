<script setup lang="ts">
import { computed } from "vue"
import CopyField from "../ui/CopyField.vue"
import type { Workspace } from "../../api/types.ts"
import { language, t } from "../../i18n/index.ts"
import { formatDateTime } from "../../i18n/format.ts"

// The workspace of a change (spec web-client, "Workspace on the change
// page"): the runner whose machine holds it, its path to copy, its branch,
// its state and its latest checkpoint.
const props = defineProps<{ workspace: Workspace }>()

const state = computed(() => t(`changePage.workspaceStates.${props.workspace.state}`))
const checkpoint = computed(() => {
  const latest = props.workspace.checkpoint
  if (!latest) return t("changePage.noCheckpoint")
  return t(latest.uncommitted ? "changePage.checkpointUncommitted" : "changePage.checkpointClean", {
    commit: latest.head_commit.slice(0, 7), date: formatDateTime(language.value, latest.at),
  })
})
</script>

<template>
  <section class="change-workspace panel" aria-labelledby="change-workspace">
    <h2 id="change-workspace" class="change-workspace__title">{{ t("changePage.workspace", { runner: workspace.runner.name }) }}</h2>
    <p class="small change-workspace__facts">
      <span>{{ t("changePage.workspaceBranch", { branch: workspace.branch }) }}</span>
      <span class="change-workspace__state" :class="`change-workspace__state--${workspace.state}`">{{ state }}</span>
      <span>{{ checkpoint }}</span>
    </p>
    <CopyField :label="t('changePage.workspacePath')" :value="workspace.path" :copy-label="t('changePage.copyPath')" />
  </section>
</template>

<style scoped>
.change-workspace {
  grid-column: 1 / -1;
  display: grid;
  gap: var(--space-2);
  padding: var(--space-3) var(--space-5);
}

.change-workspace__title { font-size: var(--text-md, 1rem); }
.change-workspace__facts { display: flex; flex-wrap: wrap; gap: var(--space-1) var(--space-3); }
.change-workspace__state { font-weight: 500; }
.change-workspace__state--kept { color: var(--tone-3-text); }
</style>
