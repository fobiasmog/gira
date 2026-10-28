<script setup lang="ts">
import { computed, ref, watch } from "vue"
import { storeToRefs } from "pinia"
import AppField from "../components/ui/AppField.vue"
import AppIcon from "../components/ui/AppIcon.vue"
import ConfirmDialog from "../components/ui/ConfirmDialog.vue"
import SettingsTabs from "../components/settings/SettingsTabs.vue"
import { ApiError } from "../api/client.ts"
import { apiTokensApi } from "../api/apiTokens.ts"
import type { ApiToken, ApiTokenAccess, FieldErrors, Id, NewApiToken } from "../api/types.ts"
import { useProjectsStore } from "../stores/projects.ts"
import { useUiStore } from "../stores/ui.ts"
import { language, t, tc } from "../i18n/index.ts"
import { formatDate } from "../i18n/format.ts"

const EXPIRY_DAYS = [7, 30, 90, 365]

const ui = useUiStore()
const { list: projects } = storeToRefs(useProjectsStore())

const tokens = ref<ApiToken[]>([])
const loaded = ref(false)
void ui.load(apiTokensApi.list()).then((result) => {
  if (!result) return
  tokens.value = result
  loaded.value = true
})

const name = ref("")
const projectId = ref<Id | null>(null)
const access = ref<ApiTokenAccess>("read")
const expiresInDays = ref(30)
const password = ref("")
const errors = ref<FieldErrors>({})
const busy = ref(false)
// The projects may still be loading when the page opens.
watch(projects, (list) => { projectId.value ??= list[0]?.id ?? null }, { immediate: true })
const canCreate = computed(() => !busy.value && name.value.trim() !== "" && projectId.value !== null && password.value !== "")

// The new token's value lives only here: leaving the page drops it.
const created = ref<NewApiToken | null>(null)
const valueInput = ref<HTMLInputElement>()

async function create() {
  if (projectId.value === null) return
  busy.value = true
  errors.value = {}
  try {
    const token = await apiTokensApi.create({
      name: name.value.trim(),
      project_id: projectId.value,
      access: access.value,
      expires_in_days: expiresInDays.value,
      current_password: password.value,
    })
    created.value = token
    tokens.value = [token, ...tokens.value]
    name.value = ""
    password.value = ""
  } catch (error) {
    if (error instanceof ApiError && error.status === 422) errors.value = error.fields
    else ui.fail(error)
  } finally {
    busy.value = false
  }
}

async function copy() {
  if (!created.value) return
  try {
    await navigator.clipboard.writeText(created.value.token)
    ui.toast(t("apiTokens.copied"))
  } catch {
    valueInput.value?.select()
    ui.toast(t("apiTokens.copyFailed"), "error")
  }
}

const revoking = ref<ApiToken | null>(null)
const revokeOpen = computed({ get: () => revoking.value !== null, set: (open) => { if (!open) revoking.value = null } })

async function revoke() {
  const token = revoking.value
  if (!token) return
  try {
    await apiTokensApi.revoke(token.id)
    tokens.value = tokens.value.filter((other) => other.id !== token.id)
    if (created.value?.id === token.id) created.value = null
    ui.toast(t("apiTokens.revoked", { name: token.name }))
  } catch (error) {
    ui.fail(error)
  }
}

const accessLabel = (value: ApiTokenAccess) => t(value === "read" ? "apiTokens.read" : "apiTokens.readWrite")
</script>

<template>
  <section class="page settings">
    <header class="page__header">
      <h1 class="grow">{{ t("settings.title") }}</h1>
      <SettingsTabs />
    </header>

    <!-- A server-rendered page outside the SPA, so a plain link. -->
    <p class="muted">{{ t("apiTokens.intro") }} <a href="/api/docs">{{ t("apiTokens.reference") }}</a></p>

    <div v-if="created" class="panel stack settings__section new-token" role="status">
      <h2>{{ t("apiTokens.newToken", { name: created.name }) }}</h2>
      <p class="new-token__warning">{{ t("apiTokens.showOnce") }}</p>
      <div class="row">
        <AppField class="grow" :label="t('apiTokens.value')" hide-label>
          <template #default="{ control }">
            <input ref="valueInput" v-bind="control" class="input new-token__value" :value="created.token" readonly spellcheck="false" @focus="($event.target as HTMLInputElement).select()">
          </template>
        </AppField>
        <button type="button" class="button button--secondary" @click="copy">{{ t("apiTokens.copy") }}</button>
      </div>
    </div>

    <form class="panel stack settings__section" novalidate @submit.prevent="create">
      <h2>{{ t("apiTokens.create") }}</h2>
      <p v-if="errors.base" class="field__error">{{ errors.base.join(" ") }}</p>
      <AppField :label="t('apiTokens.name')" :hint="t('apiTokens.nameHint')" :errors="errors.name">
        <template #default="{ control }"><input v-model="name" v-bind="control" class="input" maxlength="100" autocomplete="off"></template>
      </AppField>
      <AppField :label="t('apiTokens.project')" :errors="errors.project_id">
        <template #default="{ control }">
          <select v-model="projectId" v-bind="control" class="input">
            <option v-for="project in projects" :key="project.id" :value="project.id">{{ project.title }}</option>
          </select>
        </template>
      </AppField>
      <fieldset class="field">
        <legend class="field__label">{{ t("apiTokens.access") }}</legend>
        <label class="row"><input v-model="access" type="radio" name="access" value="read">{{ t("apiTokens.read") }}</label>
        <label class="row"><input v-model="access" type="radio" name="access" value="read_write">{{ t("apiTokens.readWrite") }}</label>
        <p v-if="errors.access" class="field__error">{{ errors.access.join(" ") }}</p>
      </fieldset>
      <AppField :label="t('apiTokens.expiry')" :errors="errors.expires_in_days">
        <template #default="{ control }">
          <select v-model="expiresInDays" v-bind="control" class="input">
            <option v-for="days in EXPIRY_DAYS" :key="days" :value="days">{{ tc("apiTokens.days", days) }}</option>
          </select>
        </template>
      </AppField>
      <AppField :label="t('settings.currentPassword')" :errors="errors.current_password">
        <template #default="{ control }"><input v-model="password" v-bind="control" class="input" type="password" autocomplete="current-password"></template>
      </AppField>
      <p><button type="submit" class="button" :disabled="!canCreate">{{ t("apiTokens.submit") }}</button></p>
    </form>

    <section v-if="loaded" class="stack" aria-labelledby="tokens-heading">
      <h2 id="tokens-heading">{{ t("apiTokens.yours") }}</h2>
      <ul v-if="tokens.length" role="list" class="tokens panel">
        <li v-for="token in tokens" :key="token.id" class="token">
          <div class="grow">
            <p class="token__name break-word">{{ token.name }}</p>
            <p class="small muted">
              {{ t("apiTokens.details", { project: token.project.title, access: accessLabel(token.access), last: token.last_characters }) }}
            </p>
            <p class="small muted">
              {{ t("apiTokens.expires", { date: formatDate(language, token.expires_at) }) }} ·
              {{ token.last_used_at ? t("apiTokens.lastUsed", { date: formatDate(language, token.last_used_at) }) : t("apiTokens.neverUsed") }}
            </p>
          </div>
          <button type="button" class="icon-button" :aria-label="t('apiTokens.revoke', { name: token.name })" @click="revoking = token">
            <AppIcon name="delete" :size="20" />
          </button>
        </li>
      </ul>
      <p v-else class="muted">{{ t("apiTokens.empty") }}</p>
    </section>

    <ConfirmDialog
      v-model:open="revokeOpen"
      :title="t('apiTokens.revoke', { name: revoking?.name ?? '' })"
      :message="t('apiTokens.revokeConfirm', { name: revoking?.name ?? '' })"
      :confirm-label="t('apiTokens.revokeAction')"
      danger
      :on-confirm="revoke"
    />
  </section>
</template>

<style scoped>
.settings { max-inline-size: 640px; }
.settings__section { padding: var(--space-4); }
fieldset.field { border: 0; padding: 0; margin: 0; }
.new-token__warning { font-weight: 500; }
.new-token__value { font-family: var(--font-mono, monospace); }
.tokens { display: grid; padding: var(--space-1) 0; }

.token {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  padding: var(--space-2) var(--space-4);

  & + & { border-block-start: 1px solid var(--color-border); }
}

.token__name { font-weight: 500; }
</style>
