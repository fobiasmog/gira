<script setup lang="ts">
import { computed, ref, watch } from "vue"
import AppDialog from "../ui/AppDialog.vue"
import AppField from "../ui/AppField.vue"
import AppIcon from "../ui/AppIcon.vue"
import ConfirmDialog from "../ui/ConfirmDialog.vue"
import TokenFieldset from "./TokenFieldset.vue"
import TokenReveal from "./TokenReveal.vue"
import { ApiError } from "../../api/client.ts"
import { agentsApi, channelsOf, type ChannelChoice } from "../../api/agents.ts"
import type { Agent, AgentToken, ApiTokenAccess, FieldErrors, NewAgentToken } from "../../api/types.ts"
import { useUiStore } from "../../stores/ui.ts"
import { language, t } from "../../i18n/index.ts"
import { formatDate } from "../../i18n/format.ts"
import { accessLabel, channelsLabel } from "./labels.ts"

// An agent's tokens (spec web-client, "Agents screen"): everyone who can see
// the agent lists them, issues one with their own password, and revokes any,
// whoever issued it. A new token's value is shown this once.
const props = defineProps<{ agent: Agent | null }>()
const open = defineModel<boolean>("open", { required: true })
const emit = defineEmits<{ changed: [] }>()
const ui = useUiStore()

const tokens = ref<AgentToken[]>([])
const loaded = ref(false)
const issued = ref<NewAgentToken | null>(null)

const name = ref("")
const access = ref<ApiTokenAccess>("read_write")
const channel = ref<ChannelChoice>("mcp")
const password = ref("")
const errors = ref<FieldErrors>({})
const busy = ref(false)
const canIssue = computed(() => !busy.value && name.value.trim() !== "" && password.value !== "")

watch(open, async (value) => {
  if (!value || !props.agent) return
  loaded.value = false
  const result = await ui.load(agentsApi.tokens(props.agent.id))
  if (!result) return
  tokens.value = result
  loaded.value = true
})

async function issue() {
  if (!props.agent) return
  busy.value = true
  errors.value = {}
  try {
    const token = await agentsApi.issueToken(
      props.agent.id, { name: name.value.trim(), access: access.value, channels: channelsOf(channel.value) }, password.value,
    )
    issued.value = token
    tokens.value = [token, ...tokens.value]
    name.value = password.value = ""
    emit("changed")
  } catch (error) {
    if (error instanceof ApiError && error.status === 422) errors.value = error.fields
    else ui.fail(error)
  } finally {
    busy.value = false
  }
}

const revoking = ref<AgentToken | null>(null)
const revokeOpen = computed({ get: () => revoking.value !== null, set: (value) => { if (!value) revoking.value = null } })

async function revoke() {
  const token = revoking.value
  if (!token || !props.agent) return
  try {
    await agentsApi.revokeToken(props.agent.id, token.id)
    tokens.value = tokens.value.filter((other) => other.id !== token.id)
    if (issued.value?.id === token.id) issued.value = null
    ui.toast(t("agents.revoked", { name: token.name }))
    emit("changed")
  } catch (error) {
    ui.fail(error)
  }
}

// The value is dropped, and the form starts empty next time.
function reset() {
  issued.value = null
  tokens.value = []
  loaded.value = false
  name.value = password.value = ""
  access.value = "read_write"
  channel.value = "mcp"
  errors.value = {}
}
</script>

<template>
  <AppDialog v-model:open="open" :title="t('agents.tokensTitle', { name: agent?.name ?? '' })" wide @closed="reset">
    <TokenReveal v-if="issued && agent" :token="issued" :agent-name="agent.name" />

    <template v-if="loaded">
      <ul v-if="tokens.length" role="list" class="tokens">
        <li v-for="token in tokens" :key="token.id" class="token">
          <div class="grow">
            <p class="token__name break-word">{{ token.name }}</p>
            <p class="small muted">
              {{ t("agents.tokenDetails", { access: accessLabel(token.access), channels: channelsLabel(token.channels), last: token.last_characters }) }}
            </p>
            <p class="small muted break-word">
              {{ t("agents.tokenIssued", { name: token.issuer.name, date: formatDate(language, token.created_at) }) }} ·
              {{ token.last_used_at ? t("apiTokens.lastUsed", { date: formatDate(language, token.last_used_at) }) : t("apiTokens.neverUsed") }}
            </p>
          </div>
          <button type="button" class="icon-button" :aria-label="t('apiTokens.revoke', { name: token.name })" @click="revoking = token">
            <AppIcon name="delete" :size="20" />
          </button>
        </li>
      </ul>
      <p v-else class="muted">{{ t("agents.noTokens") }}</p>
    </template>

    <form class="stack issue" novalidate @submit.prevent="issue">
      <h3>{{ t("agents.issue") }}</h3>
      <p v-if="errors.base" class="field__error">{{ errors.base.join(" ") }}</p>
      <TokenFieldset v-model:name="name" v-model:access="access" v-model:channel="channel" :errors="errors" />
      <AppField :label="t('settings.currentPassword')" :errors="errors.current_password">
        <template #default="{ control }"><input v-model="password" v-bind="control" class="input" type="password" autocomplete="current-password"></template>
      </AppField>
      <p><button type="submit" class="button" :disabled="!canIssue">{{ t("agents.issueSubmit") }}</button></p>
    </form>

    <ConfirmDialog
      v-model:open="revokeOpen"
      :title="t('apiTokens.revoke', { name: revoking?.name ?? '' })"
      :message="t('apiTokens.revokeConfirm', { name: revoking?.name ?? '' })"
      :confirm-label="t('apiTokens.revokeAction')"
      danger
      :on-confirm="revoke"
    />
  </AppDialog>
</template>

<style scoped>
.tokens { display: grid; }

.token {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  padding-block: var(--space-2);

  & + & { border-block-start: 1px solid var(--color-border); }
}

.token__name { font-weight: 500; }
.issue { padding-block-start: var(--space-4); border-block-start: 1px solid var(--color-border); }
</style>
