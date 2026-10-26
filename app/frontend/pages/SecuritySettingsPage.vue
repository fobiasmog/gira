<script setup lang="ts">
import { ref } from "vue"
import AppField from "../components/ui/AppField.vue"
import SettingsTabs from "../components/settings/SettingsTabs.vue"
import { ApiError } from "../api/client.ts"
import { meApi } from "../api/me.ts"
import type { FieldErrors } from "../api/types.ts"
import { useUiStore } from "../stores/ui.ts"
import { t } from "../i18n/index.ts"

const ui = useUiStore()
const current = ref("")
const password = ref("")
const errors = ref<FieldErrors>({})
const busy = ref(false)

async function change() {
  busy.value = true
  errors.value = {}
  try {
    await meApi.updatePassword(current.value, password.value)
    current.value = ""
    password.value = ""
    ui.toast(t("settings.passwordChanged"))
  } catch (error) {
    if (error instanceof ApiError && error.status === 422) errors.value = error.fields
    else ui.fail(error)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <section class="page settings">
    <header class="page__header">
      <h1 class="grow">{{ t("settings.title") }}</h1>
      <SettingsTabs />
    </header>
    <form class="panel stack settings__section" novalidate @submit.prevent="change">
      <h2>{{ t("settings.changePassword") }}</h2>
      <p class="small muted">{{ t("settings.passwordRevokesTokens") }}</p>
      <AppField :label="t('settings.currentPassword')" :errors="errors.current_password">
        <template #default="{ control }"><input v-model="current" v-bind="control" class="input" type="password" autocomplete="current-password"></template>
      </AppField>
      <AppField :label="t('settings.newPassword')" :hint="t('settings.passwordHint')" :errors="errors.password">
        <template #default="{ control }"><input v-model="password" v-bind="control" class="input" type="password" autocomplete="new-password" minlength="12"></template>
      </AppField>
      <p><button type="submit" class="button" :disabled="busy || !current || !password">{{ t("settings.changePassword") }}</button></p>
    </form>
  </section>
</template>

<style scoped>
.settings { max-inline-size: 640px; }
.settings__section { padding: var(--space-4); }
</style>
