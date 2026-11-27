<script setup lang="ts">
import { computed } from "vue"
import CopyField from "../ui/CopyField.vue"
import { registerCloneCommand, startCommand } from "../../api/agents.ts"
import type { Agent } from "../../api/types.ts"
import { t } from "../../i18n/index.ts"

// How to start an agent on a machine registered as a runner (spec
// web-client, "Agents screen"): registering a clone of the project, once
// per machine, then the command that starts the agent, naming it by its
// name, or by its id when another of the project's agents shares it.
const props = defineProps<{ agent: Pick<Agent, "id" | "name">; agents: Pick<Agent, "id" | "name">[]; project: string }>()
const register = computed(() => registerCloneCommand(props.project))
const command = computed(() => startCommand(props.agent, props.agents))
</script>

<template>
  <div class="stack">
    <p>{{ t("agents.registerCloneHint", { project }) }}</p>
    <CopyField :label="t('agents.registerClone', { project })" :value="register" :copy-label="t('agents.copyCommand')" />
    <p>{{ t("agents.startHint", { name: agent.name }) }}</p>
    <CopyField :label="t('agents.startCommand')" :value="command" :copy-label="t('agents.copyCommand')" />
    <p class="small muted">
      {{ t("agents.startNoRunner") }}
      <RouterLink :to="{ name: 'settings-runners' }">{{ t("runners.title") }}</RouterLink>
    </p>
  </div>
</template>
