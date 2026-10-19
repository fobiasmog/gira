<script setup lang="ts">
import { computed, ref, watch } from "vue"
import { storeToRefs } from "pinia"
import { useRouter } from "vue-router"
import AppField from "../components/ui/AppField.vue"
import AppIcon from "../components/ui/AppIcon.vue"
import ConfirmDialog from "../components/ui/ConfirmDialog.vue"
import UserAvatar from "../components/UserAvatar.vue"
import { ApiError } from "../api/client.ts"
import { projectsApi } from "../api/projects.ts"
import type { FieldErrors, Invitation, UserCard } from "../api/types.ts"
import { useMeStore } from "../stores/me.ts"
import { useProjectsStore } from "../stores/projects.ts"
import { useUiStore } from "../stores/ui.ts"
import { language, t } from "../i18n/index.ts"
import { formatDate } from "../i18n/format.ts"

const props = defineProps<{ projectId: number }>()
const router = useRouter()
const ui = useUiStore()
const projects = useProjectsStore()
const { profile } = storeToRefs(useMeStore())
const project = computed(() => projects.list.find((p) => p.id === props.projectId) ?? null)

const members = ref<UserCard[]>([])
const invitations = ref<Invitation[]>([])
const loaded = ref(false)
const email = ref("")
const emailErrors = ref<FieldErrors>({})
const removing = ref<UserCard | null>(null)
const removeOpen = computed({ get: () => removing.value !== null, set: (open) => { if (!open) removing.value = null } })
const confirmingLeave = ref(false)

async function load(id: number) {
  const result = await ui.load(Promise.all([projectsApi.members(id), projectsApi.invitations(id)]))
  if (!result) return
  ;[members.value, invitations.value] = result
  loaded.value = true
}

watch(() => props.projectId, (id) => {
  loaded.value = false
  void load(id)
}, { immediate: true })

const canRevoke = (invitation: Invitation) => project.value?.owned_by_me || invitation.inviter_id === profile.value?.id

async function invite() {
  emailErrors.value = {}
  try {
    const { message } = await projectsApi.invite(props.projectId, email.value.trim())
    ui.toast(message)
    email.value = ""
    invitations.value = await projectsApi.invitations(props.projectId)
  } catch (error) {
    if (error instanceof ApiError && error.status === 422) emailErrors.value = error.fields
    else ui.fail(error)
  }
}

async function revoke(invitation: Invitation) {
  try {
    await projectsApi.revokeInvitation(props.projectId, invitation.id)
    invitations.value = invitations.value.filter((i) => i.id !== invitation.id)
    ui.toast(t("members.revoked", { email: invitation.email }))
  } catch (error) {
    ui.fail(error)
  }
}

async function remove() {
  const member = removing.value
  if (!member) return
  try {
    await projectsApi.removeMember(props.projectId, member.id)
    members.value = members.value.filter((m) => m.id !== member.id)
    ui.toast(t("members.removed", { name: member.name }))
  } catch (error) {
    ui.fail(error)
  }
}

async function leave() {
  const title = project.value?.title ?? ""
  try {
    await projects.leave(props.projectId)
    ui.toast(t("members.left", { title }))
    await router.push({ name: "projects" })
  } catch (error) {
    ui.fail(error)
  }
}
</script>

<template>
  <section v-if="loaded && project" class="page members-page">
    <header class="page__header">
      <h1 class="grow">{{ t("members.title") }}</h1>
      <button v-if="!project.owned_by_me" type="button" class="button button--secondary" @click="confirmingLeave = true">
        <AppIcon name="logout" :size="20" />{{ t("members.leave") }}
      </button>
    </header>

    <ul role="list" class="members panel">
      <li v-for="member in members" :key="member.id" class="member">
        <UserAvatar :user="member" :size="36" />
        <div class="grow">
          <p class="member__name">
            {{ member.name }}
            <span v-if="member.id === profile?.id" class="muted">({{ t("members.you") }})</span>
          </p>
          <p class="small muted break-word">{{ member.email_address }}</p>
        </div>
        <span v-if="member.id === project.owner_id" class="chip">{{ t("members.owner") }}</span>
        <button
          v-else-if="project.owned_by_me"
          type="button"
          class="icon-button"
          :aria-label="t('members.remove', { name: member.name })"
          @click="removing = member"
        >
          <AppIcon name="delete" :size="20" />
        </button>
      </li>
    </ul>

    <section class="stack" aria-labelledby="invite-heading">
      <h2 id="invite-heading">{{ t("members.invite") }}</h2>
      <form class="row row--wrap invite-form" novalidate @submit.prevent="invite">
        <AppField class="grow" :label="t('members.email')" :errors="emailErrors.email" hide-label>
          <template #default="{ control }">
            <input v-model="email" v-bind="control" class="input" type="email" autocomplete="off" :placeholder="t('members.email')">
          </template>
        </AppField>
        <button type="submit" class="button" :disabled="!email.trim()"><AppIcon name="mail" :size="20" />{{ t("members.send") }}</button>
      </form>
    </section>

    <section class="stack" aria-labelledby="pending-heading">
      <h2 id="pending-heading">{{ t("members.pending") }}</h2>
      <ul v-if="invitations.length" role="list" class="members panel">
        <li v-for="invitation in invitations" :key="invitation.id" class="member">
          <AppIcon name="mail" />
          <div class="grow">
            <p class="break-word">{{ invitation.email }}</p>
            <p class="small muted">{{ t("members.expires", { date: formatDate(language, invitation.expires_at) }) }}</p>
          </div>
          <button
            v-if="canRevoke(invitation)"
            type="button"
            class="icon-button"
            :aria-label="t('members.revoke', { email: invitation.email })"
            @click="revoke(invitation)"
          >
            <AppIcon name="close" :size="20" />
          </button>
        </li>
      </ul>
      <p v-else class="muted">{{ t("members.noPending") }}</p>
    </section>

    <ConfirmDialog
      v-model:open="removeOpen"
      :title="t('members.remove', { name: removing?.name ?? '' })"
      :message="t('members.removeConfirm', { name: removing?.name ?? '' })"
      :confirm-label="t('common.delete')"
      danger
      :on-confirm="remove"
    />
    <ConfirmDialog
      v-model:open="confirmingLeave"
      :title="t('members.leave')"
      :message="t('members.leaveConfirm', { title: project.title })"
      :confirm-label="t('members.leave')"
      danger
      :on-confirm="leave"
    />
  </section>
</template>

<style scoped>
.members-page { max-inline-size: 720px; }
.members { display: grid; padding: var(--space-1) 0; }

.member {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  padding: var(--space-2) var(--space-4);

  & + & { border-block-start: 1px solid var(--color-border); }
}

.member__name { font-weight: 500; }
.invite-form { align-items: flex-start; }
</style>
