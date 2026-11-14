<script setup lang="ts">
import { computed, ref, useId } from "vue"
import AppDialog from "../ui/AppDialog.vue"
import AppField from "../ui/AppField.vue"
import TokenFieldset from "./TokenFieldset.vue"
import TokenReveal from "./TokenReveal.vue"
import { ApiError } from "../../api/client.ts"
import { agentsApi, channelsOf, type ChannelChoice } from "../../api/agents.ts"
import type { ApiTokenAccess, FieldErrors, NewAgent } from "../../api/types.ts"
import { useUiStore } from "../../stores/ui.ts"
import { t } from "../../i18n/index.ts"

// Creates an agent in the project together with its first token (spec
// web-client, "Agents screen"). Once created, the dialog shows the token's
// value, this once, until it is closed.
const props = defineProps<{ projectId: number }>()
const open = defineModel<boolean>("open", { required: true })
const emit = defineEmits<{ created: [agent: NewAgent] }>()
const ui = useUiStore()
const formId = useId()

const name = ref("")
const tokenName = ref("")
const access = ref<ApiTokenAccess>("read_write")
const channel = ref<ChannelChoice>("mcp")
const password = ref("")
const errors = ref<FieldErrors>({})
const busy = ref(false)
const created = ref<NewAgent | null>(null)
const canCreate = computed(() => !busy.value && name.value.trim() !== "" && tokenName.value.trim() !== "" && password.value !== "")

async function create() {
  busy.value = true
  errors.value = {}
  try {
    const agent = await agentsApi.create(
      props.projectId, name.value.trim(), { name: tokenName.value.trim(), access: access.value, channels: channelsOf(channel.value) }, password.value,
    )
    created.value = agent
    password.value = ""
    emit("created", agent)
  } catch (error) {
    if (error instanceof ApiError && error.status === 422) errors.value = error.fields
    else ui.fail(error)
  } finally {
    busy.value = false
  }
}

// The value is dropped, and the form starts empty next time.
function reset() {
  created.value = null
  name.value = tokenName.value = password.value = ""
  access.value = "read_write"
  channel.value = "mcp"
  errors.value = {}
}
</script>

<template>
  <AppDialog v-model:open="open" :title="t('agents.new')" wide @closed="reset">
    <template v-if="created">
      <p>{{ t("agents.created", { name: created.name }) }} <span class="muted break-word">{{ created.email_address }}</span></p>
      <TokenReveal :token="created.first_token" :agent-name="created.name" />
    </template>
    <form v-else :id="formId" class="stack" novalidate @submit.prevent="create">
      <p v-if="errors.base" class="field__error">{{ errors.base.join(" ") }}</p>
      <AppField :label="t('agents.name')" :hint="t('agents.nameHint')" :errors="errors.name">
        <template #default="{ control }"><input v-model="name" v-bind="control" class="input" maxlength="100" autocomplete="off"></template>
      </AppField>
      <h3>{{ t("agents.firstToken") }}</h3>
      <p v-if="errors['token.base']" class="field__error">{{ errors["token.base"].join(" ") }}</p>
      <TokenFieldset v-model:name="tokenName" v-model:access="access" v-model:channel="channel" :errors="errors" prefix="token." />
      <AppField :label="t('settings.currentPassword')" :errors="errors.current_password">
        <template #default="{ control }"><input v-model="password" v-bind="control" class="input" type="password" autocomplete="current-password"></template>
      </AppField>
    </form>

    <template #actions>
      <button v-if="created" type="button" class="button" @click="open = false">{{ t("agents.done") }}</button>
      <template v-else>
        <button type="button" class="button button--text" @click="open = false">{{ t("common.cancel") }}</button>
        <button type="submit" class="button" :form="formId" :disabled="!canCreate">{{ t("agents.submit") }}</button>
      </template>
    </template>
  </AppDialog>
</template>
