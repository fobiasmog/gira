<script setup lang="ts">
import { computed, ref, useId } from "vue"
import AppDialog from "../ui/AppDialog.vue"
import AppField from "../ui/AppField.vue"
import CopyField from "../ui/CopyField.vue"
import AgentSettingsFields from "./AgentSettingsFields.vue"
import { ApiError } from "../../api/client.ts"
import { agentsApi, settingValue, startCommand } from "../../api/agents.ts"
import type { FieldErrors, ProjectAgent } from "../../api/types.ts"
import { useUiStore } from "../../stores/ui.ts"
import { t } from "../../i18n/index.ts"

// Creates an agent in the project from a name and, optionally, its model and
// instructions, with no token and no password (spec web-client, "Agents
// screen"). Once created, the dialog shows how to start it on a runner.
const props = defineProps<{ projectId: number }>()
const open = defineModel<boolean>("open", { required: true })
const emit = defineEmits<{ created: [agent: ProjectAgent] }>()
const ui = useUiStore()
const formId = useId()

const name = ref("")
const model = ref("")
const instructions = ref("")
const errors = ref<FieldErrors>({})
const busy = ref(false)
const created = ref<ProjectAgent | null>(null)
const canCreate = computed(() => !busy.value && name.value.trim() !== "")

async function create() {
  busy.value = true
  errors.value = {}
  try {
    const agent = await agentsApi.create(props.projectId, {
      name: name.value.trim(), model: settingValue(model.value.trim()), instructions: settingValue(instructions.value),
    })
    created.value = agent
    emit("created", agent)
  } catch (error) {
    if (error instanceof ApiError && error.status === 422) errors.value = error.fields
    else ui.fail(error)
  } finally {
    busy.value = false
  }
}

// The form starts empty next time.
function reset() {
  created.value = null
  name.value = model.value = instructions.value = ""
  errors.value = {}
}
</script>

<template>
  <AppDialog v-model:open="open" :title="t('agents.new')" wide @closed="reset">
    <div v-if="created" class="stack" role="status">
      <p>{{ t("agents.created", { name: created.name }) }} <span class="muted break-word">{{ created.email_address }}</span></p>
      <p>{{ t("agents.startHint", { name: created.name }) }}</p>
      <CopyField :label="t('agents.startCommand')" :value="startCommand(created.id)" :copy-label="t('agents.copyCommand')" />
      <p class="small muted">
        {{ t("agents.startNoRunner") }}
        <RouterLink :to="{ name: 'settings-runners' }">{{ t("runners.title") }}</RouterLink>
      </p>
    </div>
    <form v-else :id="formId" class="stack" novalidate @submit.prevent="create">
      <p v-if="errors.base" class="field__error">{{ errors.base.join(" ") }}</p>
      <AppField :label="t('agents.name')" :hint="t('agents.nameHint')" :errors="errors.name">
        <template #default="{ control }"><input v-model="name" v-bind="control" class="input" maxlength="100" autocomplete="off"></template>
      </AppField>
      <AgentSettingsFields v-model:model="model" v-model:instructions="instructions" :errors="errors" />
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
