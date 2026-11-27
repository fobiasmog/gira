<script setup lang="ts">
import { computed, ref, useId } from "vue"
import AppDialog from "../components/ui/AppDialog.vue"
import AppField from "../components/ui/AppField.vue"
import AppIcon from "../components/ui/AppIcon.vue"
import ConfirmDialog from "../components/ui/ConfirmDialog.vue"
import RunnerSecretReveal from "../components/runners/RunnerSecretReveal.vue"
import SettingsTabs from "../components/settings/SettingsTabs.vue"
import { ApiError } from "../api/client.ts"
import { runnersApi } from "../api/runners.ts"
import type { FieldErrors, NewRunner, Runner } from "../api/types.ts"
import { useUiStore } from "../stores/ui.ts"
import { language, t } from "../i18n/index.ts"
import { formatDate, formatDateTime } from "../i18n/format.ts"

// Spec web-client, "Runners screen": the user's runners, the machines that
// run agents with bin/goalner-worker, each with the agents it runs now.
// Creating one and rotating its secret ask for the current password and show
// the secret once, with the command that registers the machine.
const ui = useUiStore()

const runners = ref<Runner[]>([])
const loaded = ref(false)
async function reload() {
  const result = await ui.load(runnersApi.list())
  if (!result) return
  runners.value = result
  loaded.value = true
}
void reload()

const name = ref("")
const password = ref("")
const errors = ref<FieldErrors>({})
const busy = ref(false)
const canCreate = computed(() => !busy.value && name.value.trim() !== "" && password.value !== "")

// A new secret lives only here: leaving the page drops it.
const created = ref<NewRunner | null>(null)

async function create() {
  busy.value = true
  errors.value = {}
  try {
    created.value = await runnersApi.create(name.value.trim(), password.value)
    name.value = password.value = ""
    await reload()
  } catch (error) {
    if (error instanceof ApiError && error.status === 422) errors.value = error.fields
    else ui.fail(error)
  } finally {
    busy.value = false
  }
}

const agentNames = (runner: Runner | null) => (runner?.agents ?? []).map((agent) => agent.name).join(", ")

// Rotating: the current password, then the new secret in the same dialog.
const rotating = ref<Runner | null>(null)
const rotated = ref<NewRunner | null>(null)
const rotatePassword = ref("")
const rotateErrors = ref<FieldErrors>({})
const rotateFormId = useId()
const rotateOpen = computed({ get: () => rotating.value !== null, set: (open) => { if (!open) rotating.value = null } })

function startRotating(runner: Runner) {
  rotating.value = runner
  rotated.value = null
  rotatePassword.value = ""
  rotateErrors.value = {}
}

async function rotate() {
  const runner = rotating.value
  if (!runner) return
  rotateErrors.value = {}
  try {
    rotated.value = await runnersApi.rotate(runner.id, rotatePassword.value)
    rotatePassword.value = ""
    await reload()
  } catch (error) {
    if (error instanceof ApiError && error.status === 422) rotateErrors.value = error.fields
    else ui.fail(error)
  }
}

function closedRotation() {
  rotated.value = null
  rotatePassword.value = ""
}

const revoking = ref<Runner | null>(null)
const revokeOpen = computed({ get: () => revoking.value !== null, set: (open) => { if (!open) revoking.value = null } })

async function revoke() {
  const runner = revoking.value
  if (!runner) return
  try {
    await runnersApi.revoke(runner.id)
    if (created.value?.id === runner.id) created.value = null
    ui.toast(t("runners.revoked", { name: runner.name }))
    await reload()
  } catch (error) {
    ui.fail(error)
  }
}

function stopsText(runner: Runner | null): string {
  return runner?.agents.length ? t("runners.stops", { agents: agentNames(runner) }) : t("runners.stopsNothing")
}
</script>

<template>
  <section class="page settings">
    <header class="page__header">
      <h1 class="grow">{{ t("settings.title") }}</h1>
      <SettingsTabs />
    </header>

    <p class="muted">{{ t("runners.intro") }}</p>

    <div v-if="created" class="panel stack settings__section">
      <h2>{{ t("runners.newRunner", { name: created.name }) }}</h2>
      <RunnerSecretReveal :runner="created" />
    </div>

    <form class="panel stack settings__section" novalidate @submit.prevent="create">
      <h2>{{ t("runners.create") }}</h2>
      <p v-if="errors.base" class="field__error">{{ errors.base.join(" ") }}</p>
      <AppField :label="t('runners.name')" :hint="t('runners.nameHint')" :errors="errors.name">
        <template #default="{ control }"><input v-model="name" v-bind="control" class="input" maxlength="100" autocomplete="off"></template>
      </AppField>
      <AppField :label="t('settings.currentPassword')" :errors="errors.current_password">
        <template #default="{ control }"><input v-model="password" v-bind="control" class="input" type="password" autocomplete="current-password"></template>
      </AppField>
      <p><button type="submit" class="button" :disabled="!canCreate">{{ t("runners.submit") }}</button></p>
    </form>

    <section v-if="loaded" class="stack" aria-labelledby="runners-heading">
      <h2 id="runners-heading">{{ t("runners.yours") }}</h2>
      <ul v-if="runners.length" role="list" class="runners panel">
        <li v-for="runner in runners" :key="runner.id" class="runner">
          <div class="grow">
            <p class="runner__name break-word">{{ runner.name }}</p>
            <p class="small muted">
              {{ t("runners.details", { last: runner.last_characters, date: formatDate(language, runner.created_at) }) }} ·
              {{ runner.last_contact_at ? t("runners.lastContact", { date: formatDateTime(language, runner.last_contact_at) }) : t("runners.neverContacted") }}
            </p>
            <p class="small break-word runner__agents">{{ runner.agents.length ? t("runners.runs", { agents: agentNames(runner) }) : t("runners.runsNothing") }}</p>
          </div>
          <button type="button" class="button button--text" :aria-label="t('runners.rotate', { name: runner.name })" @click="startRotating(runner)">
            {{ t("runners.rotateAction") }}
          </button>
          <button type="button" class="icon-button" :aria-label="t('runners.revoke', { name: runner.name })" @click="revoking = runner">
            <AppIcon name="delete" :size="20" />
          </button>
        </li>
      </ul>
      <p v-else class="muted">{{ t("runners.empty") }}</p>
    </section>

    <AppDialog v-model:open="rotateOpen" :title="t('runners.rotate', { name: rotating?.name ?? '' })" wide @closed="closedRotation">
      <RunnerSecretReveal v-if="rotated" :runner="rotated" />
      <form v-else :id="rotateFormId" class="stack" novalidate @submit.prevent="rotate">
        <p>{{ t("runners.rotateConfirm") }} {{ stopsText(rotating) }}</p>
        <AppField :label="t('settings.currentPassword')" :errors="rotateErrors.current_password">
          <template #default="{ control }"><input v-model="rotatePassword" v-bind="control" class="input" type="password" autocomplete="current-password"></template>
        </AppField>
      </form>
      <template #actions>
        <button v-if="rotated" type="button" class="button" @click="rotateOpen = false">{{ t("agents.done") }}</button>
        <template v-else>
          <button type="button" class="button button--text" @click="rotateOpen = false">{{ t("common.cancel") }}</button>
          <button type="submit" class="button" :form="rotateFormId" :disabled="rotatePassword === ''">{{ t("runners.rotateAction") }}</button>
        </template>
      </template>
    </AppDialog>

    <ConfirmDialog
      v-model:open="revokeOpen"
      :title="t('runners.revoke', { name: revoking?.name ?? '' })"
      :message="`${t('runners.revokeConfirm', { name: revoking?.name ?? '' })} ${stopsText(revoking)}`"
      :confirm-label="t('runners.revokeAction')"
      danger
      :on-confirm="revoke"
    />
  </section>
</template>

<style scoped>
.settings { max-inline-size: 640px; }
.settings__section { padding: var(--space-4); }
.runners { display: grid; padding: var(--space-1) 0; }

.runner {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  padding: var(--space-2) var(--space-4);

  & + & { border-block-start: 1px solid var(--color-border); }
}

.runner__name { font-weight: 500; }
</style>
