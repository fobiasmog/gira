<script setup lang="ts">
import { computed, onBeforeUnmount, ref } from "vue"
import { storeToRefs } from "pinia"
import AppField from "../components/ui/AppField.vue"
import AppIcon from "../components/ui/AppIcon.vue"
import UserAvatar from "../components/UserAvatar.vue"
import SettingsTabs from "../components/settings/SettingsTabs.vue"
import { ApiError } from "../api/client.ts"
import { CONTACT_SERVICES, type ContactLinks, type ContactService, type FieldErrors, type Language } from "../api/types.ts"
import { useMeStore } from "../stores/me.ts"
import { useUiStore } from "../stores/ui.ts"
import { t } from "../i18n/index.ts"

const me = useMeStore()
const { profile } = storeToRefs(me)
const ui = useUiStore()
const LANGUAGES: Language[] = ["en", "ru"]

// A failed save keeps the input; 422 messages go under the fields.
async function save(change: () => Promise<void>, errors: { value: FieldErrors }) {
  errors.value = {}
  try {
    await change()
    ui.toast(t("settings.saved"))
    return true
  } catch (error) {
    if (error instanceof ApiError && error.status === 422) errors.value = error.fields
    else ui.fail(error)
    return false
  }
}

const name = ref(profile.value?.name ?? "")
const nameErrors = ref<FieldErrors>({})
const saveName = () => save(() => me.update({ name: name.value.trim() }), nameErrors)

const languageErrors = ref<FieldErrors>({})
function changeLanguage(event: Event) {
  void save(() => me.update({ lang: (event.target as HTMLSelectElement).value as Language }), languageErrors)
}

const links = ref<ContactLinks>({ ...profile.value?.contact_links })
const linkErrors = ref<FieldErrors>({})
const invalidLinks = computed(() => CONTACT_SERVICES.filter((service) => {
  const value = links.value[service]?.trim()
  return value && !/^https:\/\/\S+$/i.test(value)
}))
function linkError(service: ContactService): string[] {
  return invalidLinks.value.includes(service) ? [t("settings.httpsOnly")] : []
}
function saveLinks() {
  if (invalidLinks.value.length) return
  const contact_links = Object.fromEntries(CONTACT_SERVICES.map((service) => [service, links.value[service]?.trim() ?? ""]))
  void save(() => me.update({ contact_links }), linkErrors)
}

const avatarInput = ref<HTMLInputElement>()
const avatarFile = ref<File | null>(null)
const avatarPreview = ref<string | null>(null)
const avatarErrors = ref<FieldErrors>({})
function setAvatarFile(file: File | null) {
  if (avatarPreview.value) URL.revokeObjectURL(avatarPreview.value)
  avatarFile.value = file
  avatarPreview.value = file ? URL.createObjectURL(file) : null
}
async function uploadAvatar() {
  const file = avatarFile.value
  if (!file || !(await save(() => me.updateAvatar(file), avatarErrors))) return
  setAvatarFile(null)
  if (avatarInput.value) avatarInput.value.value = ""
}
onBeforeUnmount(() => { if (avatarPreview.value) URL.revokeObjectURL(avatarPreview.value) })
</script>

<template>
  <section v-if="profile" class="page settings">
    <header class="page__header">
      <h1 class="grow">{{ t("settings.title") }}</h1>
      <SettingsTabs />
    </header>

    <form class="panel stack settings__section" novalidate @submit.prevent="saveName">
      <AppField :label="t('settings.name')" :errors="nameErrors.name">
        <template #default="{ control }"><input v-model="name" v-bind="control" class="input" maxlength="100" autocomplete="name"></template>
      </AppField>
      <p><button type="submit" class="button" :disabled="!name.trim() || name.trim() === profile.name">{{ t("settings.saveName") }}</button></p>
    </form>

    <div class="panel stack settings__section">
      <AppField :label="t('settings.language')" :errors="languageErrors.lang">
        <template #default="{ control }">
          <select v-bind="control" class="input" :value="profile.lang" @change="changeLanguage">
            <option v-for="lang in LANGUAGES" :key="lang" :value="lang" :lang="lang">{{ t(`settings.languages.${lang}`) }}</option>
          </select>
        </template>
      </AppField>
    </div>

    <form class="panel stack settings__section" novalidate @submit.prevent="saveLinks">
      <h2>{{ t("settings.contacts") }}</h2>
      <p class="small muted">{{ t("settings.contactsHint") }}</p>
      <AppField v-for="service in CONTACT_SERVICES" :key="service" :label="t(`settings.services.${service}`)" :errors="linkError(service)">
        <template #default="{ control }">
          <input v-model="links[service]" v-bind="control" class="input" type="url" inputmode="url" placeholder="https://" autocomplete="off">
        </template>
      </AppField>
      <p v-if="linkErrors.contact_links" class="field__error">{{ linkErrors.contact_links.join(" ") }}</p>
      <p><button type="submit" class="button" :disabled="invalidLinks.length > 0">{{ t("settings.saveContacts") }}</button></p>
    </form>

    <form class="panel stack settings__section" @submit.prevent="uploadAvatar">
      <h2>{{ t("settings.avatar") }}</h2>
      <div class="row row--wrap avatar-row">
        <UserAvatar :user="profile" :size="72" />
        <template v-if="avatarPreview">
          <AppIcon name="chevron_right" />
          <img :src="avatarPreview" :alt="t('settings.avatarPreview')" class="avatar-preview" width="72" height="72">
        </template>
      </div>
      <AppField :label="t('settings.chooseAvatar')" :hint="t('settings.avatarHint')" :errors="avatarErrors.avatar">
        <template #default="{ control }">
          <input ref="avatarInput" v-bind="control" type="file" accept="image/png,image/jpeg,image/webp" @change="setAvatarFile(($event.target as HTMLInputElement).files?.[0] ?? null)">
        </template>
      </AppField>
      <p><button type="submit" class="button" :disabled="!avatarFile">{{ t("settings.uploadAvatar") }}</button></p>
    </form>
  </section>
</template>

<style scoped>
.settings { max-inline-size: 640px; }
.settings__section { padding: var(--space-4); }
.avatar-preview { inline-size: 72px; block-size: 72px; border-radius: 50%; object-fit: cover; }
</style>
