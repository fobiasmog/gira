<script setup lang="ts">
import { ref } from "vue"
import AppDialog from "../ui/AppDialog.vue"
import type { ChangeReference } from "../../api/types.ts"
import { useUiStore } from "../../stores/ui.ts"
import { t, tc } from "../../i18n/index.ts"

// Confirms archiving a change (spec web-client, "Archiving a change"). When
// root tasks are not in the done column, it says how many and what happens to
// them; archiving stays possible either way.
const props = defineProps<{ change: ChangeReference | null; unfinished: number; onConfirm: () => Promise<unknown> }>()
const open = defineModel<boolean>("open", { required: true })
const ui = useUiStore()
const busy = ref(false)

// The dialog stays open when archiving fails.
async function confirm() {
  busy.value = true
  try {
    await props.onConfirm()
    open.value = false
  } catch (error) {
    ui.fail(error)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <AppDialog v-model:open="open" :title="t('changes.archiveTitle', { name: change?.name ?? '' })">
    <div class="stack">
      <div v-if="unfinished > 0" class="unfinished-warning" role="note">
        <p><strong>{{ tc("changes.unfinished", unfinished) }}</strong></p>
        <p>{{ t("changes.unfinishedNote") }}</p>
      </div>
      <p>{{ t("changes.archiveConfirm", { name: change?.name ?? "" }) }}</p>
    </div>
    <template #actions>
      <button type="button" class="button button--text" @click="open = false">{{ t("common.cancel") }}</button>
      <button type="button" class="button" :disabled="busy" @click="confirm">{{ t("changes.archive") }}</button>
    </template>
  </AppDialog>
</template>

<style scoped>
.unfinished-warning {
  display: grid;
  gap: var(--space-1);
  padding: var(--space-3);
  border-radius: var(--radius);
  background: var(--tone-3-bg);
  color: var(--tone-3-text);
}

.unfinished-warning p { margin: 0; }
</style>
