<script setup lang="ts">
import { computed, ref, watch } from "vue"
import AppIcon from "../components/ui/AppIcon.vue"
import AppMenu from "../components/ui/AppMenu.vue"
import ConfirmDialog from "../components/ui/ConfirmDialog.vue"
import AgentAddDialog from "../components/agents/AgentAddDialog.vue"
import AgentCreateDialog from "../components/agents/AgentCreateDialog.vue"
import AgentEditDialog from "../components/agents/AgentEditDialog.vue"
import AgentStartHint from "../components/agents/AgentStartHint.vue"
import AppDialog from "../components/ui/AppDialog.vue"
import AgentTokensDialog from "../components/agents/AgentTokensDialog.vue"
import UserAvatar from "../components/UserAvatar.vue"
import { activeAgents, agentsApi, deletedAgents } from "../api/agents.ts"
import type { Agent, ProjectAgent } from "../api/types.ts"
import { useProjectsStore } from "../stores/projects.ts"
import { useUiStore } from "../stores/ui.ts"
import { language, t, tc } from "../i18n/index.ts"
import { formatDate, formatDateTime } from "../i18n/format.ts"
import { agentState } from "../composables/changes.ts"

// Spec web-client, "Agents screen": the project's agents, for every member,
// each online or offline with its last check-in and the change it is on, and
// where it runs. Agents are created here without a token, added from other
// projects, given a name, model and instructions, given tokens, removed,
// deleted and restored.
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

// One agent at a time is shown its start command, edited, shown its
// tokens, removed or deleted.
type Action = "start" | "edit" | "tokens" | "remove" | "delete"
const acting = ref<{ action: Action; agent: ProjectAgent } | null>(null)
const subject = computed(() => acting.value?.agent ?? null)
const dialog = (action: Action) => computed({
  get: () => acting.value?.action === action,
  set: (open) => { if (!open && acting.value?.action === action) acting.value = null },
})
const startOpen = dialog("start")
const editOpen = dialog("edit")
const tokensOpen = dialog("tokens")
const removeOpen = dialog("remove")
const deleteOpen = dialog("delete")

function start(action: Action, agent: ProjectAgent) {
  acting.value = { action, agent }
}

async function saved(agent: Agent) {
  ui.toast(t("agents.saved", { name: agent.name }))
  await reload()
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

// Online and free or on a change, or offline with its last check-in.
function stateText(agent: ProjectAgent): string {
  const state = agentState(agent)
  if (state.kind === "free") return t("agents.stateFree")
  if (state.kind === "busy") return state.change ? t("agents.stateOn", { change: state.change }) : t("agents.stateOnElsewhere")
  return agent.checked_in_at ? t("agents.stateOffline", { date: formatDateTime(language.value, agent.checked_in_at) }) : t("agents.stateNever")
}

// The runner it is leased to, its owner and since when, or that it runs nowhere.
function runsText(agent: ProjectAgent): string {
  const lease = agent.lease
  if (!lease) return t("agents.notRunning")
  return t("agents.runsOn", { runner: lease.runner.name, owner: lease.owner.name, date: formatDateTime(language.value, lease.since) })
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
          <p class="small break-word agent__state" :class="{ 'agent__state--online': agent.online }">{{ stateText(agent) }}</p>
          <p class="small break-word agent__runs" :class="{ 'agent__runs--running': agent.lease }">{{ runsText(agent) }}</p>
          <p v-if="agent.model" class="small muted break-word">{{ t("agents.modelLine", { model: agent.model }) }}</p>
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
            <button type="button" class="menu__item" @click="close(); start('start', agent)"><AppIcon name="robot" :size="20" />{{ t("agents.howToStart") }}</button>
            <button type="button" class="menu__item" @click="close(); start('tokens', agent)"><AppIcon name="code" :size="20" />{{ t("agents.tokens") }}</button>
            <button type="button" class="menu__item" @click="close(); start('edit', agent)"><AppIcon name="edit" :size="20" />{{ t("agents.edit") }}</button>
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

    <AgentCreateDialog v-model:open="creating" :project-id="projectId" :agents="active" @created="reload" />
    <AgentAddDialog v-model:open="adding" :project-id="projectId" @added="reload" />
    <AgentTokensDialog v-model:open="tokensOpen" :agent="subject" @changed="reload" />

    <AgentEditDialog v-model:open="editOpen" :agent="subject" @saved="saved" />
    <AppDialog v-model:open="startOpen" :title="t('agents.startTitle', { name: subject?.name ?? '' })" wide>
      <AgentStartHint v-if="subject" :agent="subject" :agents="active" />
      <template #actions>
        <button type="button" class="button" @click="startOpen = false">{{ t("agents.done") }}</button>
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
.agent__state { color: var(--color-muted); }
.agent__state--online { color: var(--color-text); font-weight: 500; }
.agent__runs { color: var(--color-muted); }
.agent__runs--running { color: var(--color-text); }
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
