<script setup lang="ts">
import AppField from "../ui/AppField.vue"
import AppTextarea from "../ui/AppTextarea.vue"
import type { FieldErrors } from "../../api/types.ts"
import { t } from "../../i18n/index.ts"

// An agent's settings (spec agents, "Agent settings"): the model and the
// instructions its worker passes to every run. Both are optional.
const model = defineModel<string>("model", { required: true })
const instructions = defineModel<string>("instructions", { required: true })
defineProps<{ errors: FieldErrors }>()
</script>

<template>
  <AppField :label="t('agents.model')" :hint="t('agents.modelHint')" :errors="errors.model">
    <template #default="{ control }"><input v-model="model" v-bind="control" class="input" maxlength="100" autocomplete="off" spellcheck="false"></template>
  </AppField>
  <AppField :label="t('agents.instructions')" :hint="t('agents.instructionsHint')" :errors="errors.instructions">
    <template #default="{ control }"><AppTextarea v-model="instructions" v-bind="control" maxlength="10000" /></template>
  </AppField>
</template>
