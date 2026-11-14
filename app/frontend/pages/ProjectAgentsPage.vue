<script setup lang="ts">
import { computed, ref, useId, watch } from "vue"
import AppDialog from "../components/ui/AppDialog.vue"
import AppField from "../components/ui/AppField.vue"
import AppIcon from "../components/ui/AppIcon.vue"
import AppMenu from "../components/ui/AppMenu.vue"
import ConfirmDialog from "../components/ui/ConfirmDialog.vue"
import AgentAddDialog from "../components/agents/AgentAddDialog.vue"
import AgentCreateDialog from "../components/agents/AgentCreateDialog.vue"
import AgentTokensDialog from "../components/agents/AgentTokensDialog.vue"
import UserAvatar from "../components/UserAvatar.vue"
import { ApiError } from "../api/client.ts"
import { activeAgents, agentsApi, deletedAgents } from "../api/agents.ts"
import type { FieldErrors, ProjectAgent } from "../api/types.ts"
import { useProjectsStore } from "../stores/projects.ts"
import { useUiStore } from "../stores/ui.ts"
import { language, t, tc } from "../i18n/index.ts"
import { formatDate } from "../i18n/format.ts"

// Spec web-client, "Agents screen": the project's agents, for every member.
// Agents are created here with their first token, added from other projects,
// renamed, given tokens, removed, deleted and restored.
const props = defineProps<{ projectId: number }>()
const ui = useUiStore()
const projects = useProjectsStore()
const project = computed(() => projects.list.find((p) => p.id === props.projectId) ?? null)

const agents = ref<ProjectAgent[]>([])
const loaded = ref(false)
const active = computed(() => activeAgents(agents.value))
const deleted = computed(() => deletedAgents(agents.value))

// The list as the server has it: token counts, and which agents belong to
// another project too and so can be removed from this one.
async function reload() {
  const result = await ui.load(agentsApi.inProject(props.projectId))
  if (!result) return
  agents.value = result
  loaded.value = true
}

watch(() => props.projectId, () => {
  loaded.value = false
  void reload()
}, { immediate: true })

const creating = ref(false)
const adding = ref(false)

// One agent at a time is renamed, shown its tokens, removed or deleted.
type Action = "rename" | "tokens" | "remove" | "delete"
const acting = ref<{ action: Action; agent: ProjectAgent } | null>(null)
const subject = computed(() => acting.value?.agent ?? null)
const dialog = (action: Action) => computed({
  get: () => acting.value?.action === action,
  set: (open) => { if (!open && acting.value?.action === action) acting.value = null },
})
const renameOpen = dialog("rename")
const tokensOpen = dialog("tokens")
const removeOpen = dialog("remove")
const deleteOpen = dialog("delete")

const renameFormId = useId()
const newName = ref("")
const renameErrors = ref<FieldErrors>({})

function start(action: Action, agent: ProjectAgent) {
  if (action === "rename") {
    newName.value = agent.name
    renameErrors.value = {}
  }
  acting.value = { action, agent }
}

async function rename() {
  const agent = subject.value
  if (!agent) return
  renameErrors.value = {}
  try {
    const renamed = await agentsApi.rename(agent.id, newName.value.trim())
    acting.value = null
    ui.toast(t("agents.renamed", { name: renamed.name }))
    await reload()
  } catch (error) {
    if (error instanceof ApiError && error.status === 422) renameErrors.value = error.fields
    else ui.fail(error)
  }
}

async function remove() {
  const agent = subject.value
  if (!agent) return
  try {
    await agentsApi.removeFromProject(props.projectId, agent.id)
    ui.toast(t("agents.removed", { name: agent.name }))
    await reload()
  } catch (error) {
    ui.fail(error)
  }
}

async function destroy() {
  const agent = subject.value
  if (!agent) return
  try {
    await agentsApi.delete(agent.id)
    ui.toast(t("agents.deleted", { name: agent.name }))
    await reload()
  } catch (error) {
    ui.fail(error)
  }
}

async function restore(agent: ProjectAgent) {
  try {
    await agentsApi.restore(agent.id)
    ui.toast(t("agents.restored", { name: agent.name }))
    await reload()
  } catch (error) {
    ui.fail(error)
  }
}
</script>

<template>
  <section v-if="loaded && project" class="page agents-page">
    <header class="page__header">
      <h1 class="grow">{{ t("agents.title") }}</h1>
      <button type="button" class="button button--secondary" @click="adding = true">{{ t("agents.addExisting") }}</button>
      <button type="button" class="button" @click="creating = true"><AppIcon name="add" :size="20" />{{ t("agents.new") }}</button>
    </header>

    <p class="muted">{{ t("agents.intro") }}</p>

    <ul v-if="active.length" role="list" class="agents panel">
      <li v-for="agent in active" :key="agent.id" class="agent">
        <UserAvatar :user="agent" :size="36" />
        <div class="grow">
          <p class="agent__name break-word">{{ agent.name }}</p>
          <p class="small muted break-word">{{ agent.email_address }}</p>
          <p class="small muted break-word">
            {{ t("agents.createdBy", { name: agent.created_by.name, date: formatDate(language, agent.created_at) }) }} ·
            {{ tc("agents.tokenCount", agent.token_count) }}
          </p>
        </div>
        <AppMenu :label="t('agents.actions', { name: agent.name })" align="end">
          <template #trigger="{ id, expanded }">
            <button type="button" class="icon-button" :popovertarget="id" :aria-expanded="expanded" :aria-label="t('agents.actions', { name: agent.name })">
              <AppIcon name="more_vert" :size="20" />
            </button>
          </template>
          <template #default="{ close }">
            <button type="button" class="menu__item" @click="close(); start('tokens', agent)"><AppIcon name="code" :size="20" />{{ t("agents.tokens") }}</button>
            <button type="button" class="menu__item" @click="close(); start('rename', agent)"><AppIcon name="edit" :size="20" />{{ t("agents.rename") }}</button>
            <!-- Not from its only project, where nobody could see it afterwards: it is deleted instead. -->
            <button v-if="agent.removable" type="button" class="menu__item" @click="close(); start('remove', agent)">
              <AppIcon name="logout" :size="20" />{{ t("agents.remove") }}
            </button>
            <button type="button" class="menu__item" @click="close(); start('delete', agent)"><AppIcon name="delete" :size="20" />{{ t("common.delete") }}</button>
          </template>
        </AppMenu>
      </li>
    </ul>
    <p v-else class="muted">{{ t("agents.empty") }}</p>

    <details v-if="deleted.length" class="deleted">
      <summary class="deleted__summary">{{ t("agents.deletedGroup") }} <span class="badge">{{ deleted.length }}</span></summary>
      <ul role="list" class="agents panel">
        <li v-for="agent in deleted" :key="agent.id" class="agent">
          <UserAvatar :user="agent" :size="36" />
          <div class="grow">
            <p class="agent__name break-word">{{ agent.name }}</p>
            <p class="small muted break-word">{{ agent.email_address }}</p>
            <p v-if="agent.deleted_at" class="small muted">{{ t("agents.deletedOn", { date: formatDate(language, agent.deleted_at) }) }}</p>
          </div>
          <button type="button" class="button button--secondary" :aria-label="t('agents.restore', { name: agent.name })" @click="restore(agent)">
            <AppIcon name="restore_from_trash" :size="20" />{{ t("agents.restoreAction") }}
          </button>
        </li>
      </ul>
    </details>

    <AgentCreateDialog v-model:open="creating" :project-id="projectId" @created="reload" />
    <AgentAddDialog v-model:open="adding" :project-id="projectId" @added="reload" />
    <AgentTokensDialog v-model:open="tokensOpen" :agent="subject" @changed="reload" />

    <AppDialog v-model:open="renameOpen" :title="t('agents.renameTitle', { name: subject?.name ?? '' })">
      <form :id="renameFormId" novalidate @submit.prevent="rename">
        <AppField :label="t('agents.name')" :errors="renameErrors.name">
          <template #default="{ control }"><input v-model="newName" v-bind="control" class="input" maxlength="100" autocomplete="off"></template>
        </AppField>
      </form>
      <template #actions>
        <button type="button" class="button button--text" @click="renameOpen = false">{{ t("common.cancel") }}</button>
        <button type="submit" class="button" :form="renameFormId" :disabled="!newName.trim()">{{ t("common.save") }}</button>
      </template>
    </AppDialog>

    <ConfirmDialog
      v-model:open="removeOpen"
      :title="t('agents.removeTitle', { name: subject?.name ?? '' })"
      :message="t('agents.removeConfirm', { name: subject?.name ?? '' })"
      :confirm-label="t('agents.remove')"
      danger
      :on-confirm="remove"
    />
    <ConfirmDialog
      v-model:open="deleteOpen"
      :title="t('agents.deleteTitle', { name: subject?.name ?? '' })"
      :message="t('agents.deleteConfirm', { name: subject?.name ?? '' })"
      :confirm-label="t('common.delete')"
      danger
      :on-confirm="destroy"
    />
  </section>
</template>

<style scoped>
.agents-page { max-inline-size: 720px; }
.agents { display: grid; padding: var(--space-1) 0; }

.agent {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  padding: var(--space-2) var(--space-4);

  & + & { border-block-start: 1px solid var(--color-border); }
}

.agent__name { font-weight: 500; }
.deleted { display: grid; gap: var(--space-3); }

.deleted__summary {
  inline-size: fit-content;
  padding: var(--space-1) var(--space-2);
  border-radius: var(--radius-sm, 4px);
  cursor: pointer;
  font-weight: 500;
}

.deleted[open] .deleted__summary { margin-block-end: var(--space-3); }
</style>
