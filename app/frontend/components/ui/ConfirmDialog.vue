<script setup lang="ts">
import { ref } from "vue"
import AppDialog from "./AppDialog.vue"
import { t } from "../../i18n/index.ts"

const props = defineProps<{ title: string; message: string; confirmLabel: string; danger?: boolean; onConfirm: () => Promise<unknown> | void }>()
const open = defineModel<boolean>("open", { required: true })
const busy = ref(false)

async function confirm() {
  busy.value = true
  try {
    await props.onConfirm()
    open.value = false
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <AppDialog v-model:open="open" :title="title">
    <p>{{ message }}</p>
    <template #actions>
      <button type="button" class="button button--text" @click="open = false">{{ t("common.cancel") }}</button>
      <button type="button" class="button" :class="{ 'button--danger': danger }" :disabled="busy" @click="confirm">{{ confirmLabel }}</button>
    </template>
  </AppDialog>
</template>
