<script setup lang="ts">
import { computed, ref } from "vue"
import AppField from "../ui/AppField.vue"
import { mcpCommand, mcpConfig, worksOn } from "../../api/agents.ts"
import { MCP_GUIDE_URL } from "../../api/connections.ts"
import type { NewAgentToken } from "../../api/types.ts"
import { useUiStore } from "../../stores/ui.ts"
import { t } from "../../i18n/index.ts"

// A token that was just issued (spec web-client, "Agents screen"): its value,
// shown this once, with what its channels need. For MCP, a ready-to-copy
// client configuration; for the API, where to read about it. The value lives
// only in the parent's state: closing the dialog drops it.
const props = defineProps<{ token: NewAgentToken; agentName: string }>()
const ui = useUiStore()

const command = computed(() => mcpCommand(props.token.mcp_url, props.token.token))
const config = computed(() => mcpConfig(props.token.mcp_url, props.token.token))
const valueInput = ref<HTMLInputElement>()

async function copy(text: string, message: string, fallback?: HTMLInputElement | HTMLTextAreaElement | null) {
  try {
    await navigator.clipboard.writeText(text)
    ui.toast(message)
  } catch {
    fallback?.select()
    ui.toast(t("agents.copyFailed"), "error")
  }
}

const select = (event: FocusEvent) => (event.target as HTMLInputElement | HTMLTextAreaElement).select()
</script>

<template>
  <div class="stack reveal" role="status">
    <h3>{{ t("agents.newToken", { name: token.name, agent: agentName }) }}</h3>
    <p class="reveal__warning">{{ t("apiTokens.showOnce") }}</p>
    <div class="row reveal__row">
      <AppField class="grow" :label="t('apiTokens.value')" hide-label>
        <template #default="{ control }">
          <input ref="valueInput" v-bind="control" class="input reveal__code" :value="token.token" readonly spellcheck="false" @focus="select">
        </template>
      </AppField>
      <button type="button" class="button button--secondary" @click="copy(token.token, t('apiTokens.copied'), valueInput)">{{ t("apiTokens.copy") }}</button>
    </div>

    <!-- A server-rendered page outside the SPA, so a plain link. -->
    <p v-if="worksOn(token, 'api')" class="small muted">{{ t("agents.apiHint") }} <a href="/api/docs">{{ t("apiTokens.reference") }}</a></p>

    <template v-if="worksOn(token, 'mcp')">
      <AppField :label="t('agents.mcpCommand')">
        <template #default="{ control }">
          <textarea v-bind="control" class="input reveal__code reveal__code--wrap" rows="3" readonly spellcheck="false" :value="command" @focus="select" />
        </template>
      </AppField>
      <p><button type="button" class="button button--secondary" @click="copy(command, t('agents.copied'))">{{ t("agents.copyCommand") }}</button></p>
      <AppField :label="t('agents.mcpConfig')">
        <template #default="{ control }">
          <textarea v-bind="control" class="input reveal__code" rows="11" readonly spellcheck="false" :value="config" @focus="select" />
        </template>
      </AppField>
      <p class="small muted">{{ t("agents.mcpNote", { agent: agentName }) }}</p>
      <p class="row row--wrap">
        <button type="button" class="button button--secondary" @click="copy(config, t('agents.copied'))">{{ t("agents.copyConfig") }}</button>
        <!-- The server redirects to the guide, outside the SPA. -->
        <a :href="MCP_GUIDE_URL" class="small">{{ t("connectedApps.guide") }}</a>
      </p>
    </template>
  </div>
</template>

<style scoped>
.reveal__warning { font-weight: 500; }
.reveal__row { align-items: flex-end; }

.reveal__code {
  font-family: var(--font-mono, monospace);
  font-size: var(--text-sm);
}

textarea.reveal__code { resize: vertical; white-space: pre; }
/* One long line: wrapped, so the whole command can be read before copying. */
textarea.reveal__code--wrap { white-space: pre-wrap; overflow-wrap: anywhere; }
</style>
