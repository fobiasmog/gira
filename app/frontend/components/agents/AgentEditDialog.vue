<script setup lang="ts">
import { computed, ref, useId, watch } from "vue"
import AppDialog from "../ui/AppDialog.vue"
import AppField from "../ui/AppField.vue"
import AgentSettingsFields from "./AgentSettingsFields.vue"
import { ApiError } from "../../api/client.ts"
import { agentsApi, settingValue } from "../../api/agents.ts"
import type { Agent, FieldErrors } from "../../api/types.ts"
import { useUiStore } from "../../stores/ui.ts"
import { t } from "../../i18n/index.ts"

// Edits an agent's name, model and instructions (spec web-client, "Agents
// screen"; spec agents, "Agent settings"). Cleared settings are unset.
const props = defineProps<{ agent: Agent | null }>()
const open = defineModel<boolean>("open", { required: true })
const emit = defineEmits<{ saved: [agent: Agent] }>()
const ui = useUiStore()
const formId = useId()

const name = ref("")
const model = ref("")
const instructions = ref("")
const errors = ref<FieldErrors>({})
const busy = ref(false)
const canSave = computed(() => !busy.value && name.value.trim() !== "")

watch(open, (value) => {
  if (!value || !props.agent) return
  name.value = props.agent.name
  model.value = props.agent.model ?? ""
  instructions.value = props.agent.instructions ?? ""
  errors.value = {}
})

async function save() {
  if (!props.agent) return
  busy.value = true
  errors.value = {}
  try {
    const agent = await agentsApi.update(props.agent.id, {
      name: name.value.trim(), model: settingValue(model.value.trim()), instructions: settingValue(instructions.value),
    })
    open.value = false
    emit("saved", agent)
  } catch (error) {
    if (error instanceof ApiError && error.status === 422) errors.value = error.fields
    else ui.fail(error)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <AppDialog v-model:open="open" :title="t('agents.editTitle', { name: agent?.name ?? '' })" wide>
    <form :id="formId" class="stack" novalidate @submit.prevent="save">
      <AppField :label="t('agents.name')" :errors="errors.name">
        <template #default="{ control }"><input v-model="name" v-bind="control" class="input" maxlength="100" autocomplete="off"></template>
      </AppField>
      <AgentSettingsFields v-model:model="model" v-model:instructions="instructions" :errors="errors" />
    </form>
    <template #actions>
      <button type="button" class="button button--text" @click="open = false">{{ t("common.cancel") }}</button>
      <button type="submit" class="button" :form="formId" :disabled="!canSave">{{ t("common.save") }}</button>
    </template>
  </AppDialog>
</template>
