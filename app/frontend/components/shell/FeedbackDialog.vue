<script setup lang="ts">
import { ref } from "vue"
import AppDialog from "../ui/AppDialog.vue"
import AppField from "../ui/AppField.vue"
import AppTextarea from "../ui/AppTextarea.vue"
import { accountApi } from "../../api/account.ts"
import { ApiError } from "../../api/client.ts"
import type { FieldErrors } from "../../api/types.ts"
import { useUiStore } from "../../stores/ui.ts"
import { t, type MessageKey } from "../../i18n/index.ts"

const open = defineModel<boolean>("open", { required: true })
const ui = useUiStore()
const reasons: MessageKey[] = ["feedback.reasons.problem", "feedback.reasons.idea", "feedback.reasons.question", "feedback.reasons.misc"]
const reason = ref<MessageKey>("feedback.reasons.problem")
const message = ref("")
const errors = ref<FieldErrors>({})
const busy = ref(false)

async function send() {
  busy.value = true
  errors.value = {}
  try {
    await accountApi.sendFeedback(t(reason.value), message.value.trim())
    message.value = ""
    open.value = false
    ui.toast(t("feedback.thanks"))
  } catch (error) {
    if (error instanceof ApiError && error.status === 422) errors.value = error.fields
    else ui.fail(error)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <AppDialog v-model:open="open" :title="t('feedback.title')">
    <form id="feedback-form" class="stack" @submit.prevent="send">
      <AppField :label="t('feedback.reason')" :errors="errors.reason">
        <template #default="{ control }">
          <select v-model="reason" v-bind="control" class="input">
            <option v-for="key in reasons" :key="key" :value="key">{{ t(key) }}</option>
          </select>
        </template>
      </AppField>
      <AppField :label="t('feedback.message')" :errors="errors.message">
        <template #default="{ control }">
          <AppTextarea v-model="message" v-bind="control" maxlength="5000" />
        </template>
      </AppField>
    </form>
    <template #actions>
      <button type="button" class="button button--text" @click="open = false">{{ t("common.cancel") }}</button>
      <button type="submit" form="feedback-form" class="button" :disabled="busy || !message.trim()">{{ t("feedback.send") }}</button>
    </template>
  </AppDialog>
</template>
