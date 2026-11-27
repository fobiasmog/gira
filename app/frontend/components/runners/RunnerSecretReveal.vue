<script setup lang="ts">
import { computed } from "vue"
import CopyField from "../ui/CopyField.vue"
import { registerCommand } from "../../api/runners.ts"
import type { NewRunner } from "../../api/types.ts"
import { t } from "../../i18n/index.ts"

// A runner's secret, just created or rotated (spec web-client, "Runners
// screen"): shown this once with a warning, and with the command that
// registers the machine with it. It lives only in the parent's state.
const props = defineProps<{ runner: NewRunner }>()
const command = computed(() => registerCommand(props.runner.goalner_url, props.runner.secret))
</script>

<template>
  <div class="stack" role="status">
    <p class="reveal__warning">{{ t("runners.showOnce") }}</p>
    <CopyField :label="t('runners.secret')" :value="runner.secret" :copy-label="t('runners.copySecret')" />
    <p>{{ t("runners.registerHint") }}</p>
    <CopyField :label="t('runners.registerCommand')" :value="command" :copy-label="t('runners.copyCommand')" multiline />
    <p class="small muted">{{ t("runners.cloneHint") }}</p>
  </div>
</template>

<style scoped>
.reveal__warning { font-weight: 500; }
</style>
