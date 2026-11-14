<script setup lang="ts">
import { ref, watch } from "vue"
import AppDialog from "../ui/AppDialog.vue"
import UserAvatar from "../UserAvatar.vue"
import { addableAgents, agentsApi } from "../../api/agents.ts"
import type { VisibleAgent } from "../../api/types.ts"
import { useUiStore } from "../../stores/ui.ts"
import { t } from "../../i18n/index.ts"

// Adds an agent from another of the user's projects to this one (spec
// web-client, "Agents screen"). It joins at once, without an invitation.
const props = defineProps<{ projectId: number }>()
const open = defineModel<boolean>("open", { required: true })
const emit = defineEmits<{ added: [agent: VisibleAgent] }>()
const ui = useUiStore()

const agents = ref<VisibleAgent[]>([])
const loaded = ref(false)
const busy = ref(false)

watch(open, async (value) => {
  if (!value) return
  loaded.value = false
  const visible = await ui.load(agentsApi.visible())
  if (!visible) return
  agents.value = addableAgents(visible, props.projectId)
  loaded.value = true
})

async function add(agent: VisibleAgent) {
  busy.value = true
  try {
    await agentsApi.addToProject(props.projectId, agent.id)
    agents.value = agents.value.filter((other) => other.id !== agent.id)
    ui.toast(t("agents.added", { name: agent.name }))
    emit("added", agent)
  } catch (error) {
    ui.fail(error)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <AppDialog v-model:open="open" :title="t('agents.addExisting')">
    <p class="muted">{{ t("agents.addExistingIntro") }}</p>
    <template v-if="loaded">
      <ul v-if="agents.length" role="list" class="addable">
        <li v-for="agent in agents" :key="agent.id" class="addable__agent">
          <UserAvatar :user="agent" :size="32" />
          <div class="grow">
            <p class="addable__name break-word">{{ agent.name }}</p>
            <p class="small muted break-word">{{ t("agents.inProjects", { projects: agent.projects.map((project) => project.title).join(", ") }) }}</p>
          </div>
          <button type="button" class="button button--secondary" :disabled="busy" :aria-label="t('agents.add', { name: agent.name })" @click="add(agent)">
            {{ t("agents.addAction") }}
          </button>
        </li>
      </ul>
      <p v-else>{{ t("agents.addExistingEmpty") }}</p>
    </template>
    <template #actions>
      <button type="button" class="button button--text" @click="open = false">{{ t("common.close") }}</button>
    </template>
  </AppDialog>
</template>

<style scoped>
.addable { display: grid; }

.addable__agent {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  padding-block: var(--space-2);

  & + & { border-block-start: 1px solid var(--color-border); }
}

.addable__name { font-weight: 500; }
</style>
