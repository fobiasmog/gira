<script setup lang="ts">
import { useId } from "vue"
import AppField from "../ui/AppField.vue"
import { CHANNEL_CHOICES, type ChannelChoice } from "../../api/agents.ts"
import type { ApiTokenAccess, FieldErrors } from "../../api/types.ts"
import { t } from "../../i18n/index.ts"
import { channelLabel } from "./labels.ts"

// The fields of an agent token: its name, its access and where it works.
// prefix names the fields in the API's errors ("token." when the token is
// issued together with a new agent).
const props = defineProps<{ errors: FieldErrors; prefix?: string }>()
const name = defineModel<string>("name", { required: true })
const access = defineModel<ApiTokenAccess>("access", { required: true })
const channel = defineModel<ChannelChoice>("channel", { required: true })

const id = useId()
const errorsOf = (field: string) => props.errors[`${props.prefix ?? ""}${field}`]
</script>

<template>
  <AppField :label="t('agents.tokenName')" :hint="t('agents.tokenNameHint')" :errors="errorsOf('name')">
    <template #default="{ control }"><input v-model="name" v-bind="control" class="input" maxlength="100" autocomplete="off"></template>
  </AppField>
  <fieldset class="field token-fieldset">
    <legend class="field__label">{{ t("apiTokens.access") }}</legend>
    <label class="row"><input v-model="access" type="radio" :name="`${id}-access`" value="read">{{ t("apiTokens.read") }}</label>
    <label class="row"><input v-model="access" type="radio" :name="`${id}-access`" value="read_write">{{ t("apiTokens.readWrite") }}</label>
    <p v-if="errorsOf('access')" class="field__error">{{ errorsOf("access")!.join(" ") }}</p>
  </fieldset>
  <fieldset class="field token-fieldset">
    <legend class="field__label">{{ t("agents.channels") }}</legend>
    <label v-for="choice in CHANNEL_CHOICES" :key="choice" class="row">
      <input v-model="channel" type="radio" :name="`${id}-channel`" :value="choice">{{ channelLabel(choice) }}
    </label>
    <p v-if="errorsOf('channels')" class="field__error">{{ errorsOf("channels")!.join(" ") }}</p>
  </fieldset>
</template>

<style scoped>
.token-fieldset { border: 0; padding: 0; margin: 0; }
</style>
