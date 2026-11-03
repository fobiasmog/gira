<script setup lang="ts">
import { computed, ref } from "vue"
import ConfirmDialog from "../components/ui/ConfirmDialog.vue"
import SettingsTabs from "../components/settings/SettingsTabs.vue"
import { MCP_GUIDE_URL, connectionsApi, withoutConnection } from "../api/connections.ts"
import type { Connection } from "../api/types.ts"
import { useUiStore } from "../stores/ui.ts"
import { language, t } from "../i18n/index.ts"
import { formatDate, formatDateTime } from "../i18n/format.ts"

// Spec web-client, "Connected apps screen"; spec mcp-authorization,
// "Connected apps".
const ui = useUiStore()

const connections = ref<Connection[]>([])
const loaded = ref(false)
void ui.load(connectionsApi.list()).then((result) => {
  if (!result) return
  connections.value = result
  loaded.value = true
})

const disconnecting = ref<Connection | null>(null)
const disconnectOpen = computed({ get: () => disconnecting.value !== null, set: (open) => { if (!open) disconnecting.value = null } })

async function disconnect() {
  const connection = disconnecting.value
  if (!connection) return
  try {
    await connectionsApi.disconnect(connection.id)
    connections.value = withoutConnection(connections.value, connection.id)
    ui.toast(t("connectedApps.disconnected", { name: connection.client_name }))
  } catch (error) {
    ui.fail(error)
  }
}

// In production nginx serves the MCP server on this origin.
const mcpUrl = `${location.origin}/mcp`

const accessLabel = (connection: Connection) => t(connection.access === "read" ? "apiTokens.read" : "apiTokens.readWrite")
</script>

<template>
  <section class="page settings">
    <header class="page__header">
      <h1 class="grow">{{ t("settings.title") }}</h1>
      <SettingsTabs />
    </header>

    <p class="muted">{{ t("connectedApps.intro") }}</p>

    <section v-if="loaded" class="stack" aria-labelledby="connections-heading">
      <h2 id="connections-heading">{{ t("connectedApps.yours") }}</h2>
      <ul v-if="connections.length" role="list" class="connections panel">
        <li v-for="connection in connections" :key="connection.id" class="connection">
          <div class="grow">
            <p class="connection__name break-word">{{ connection.client_name }}</p>
            <p class="small muted break-word">
              {{ t("connectedApps.details", { host: connection.redirect_host ?? "—", access: accessLabel(connection) }) }}
            </p>
            <p class="small muted">
              {{ t("connectedApps.connected", { date: formatDate(language, connection.connected_at) }) }} ·
              {{ t("connectedApps.lastActive", { date: formatDateTime(language, connection.last_active_at) }) }}
            </p>
          </div>
          <button type="button" class="button button--secondary" :aria-label="t('connectedApps.disconnect', { name: connection.client_name })" @click="disconnecting = connection">
            {{ t("connectedApps.disconnectAction") }}
          </button>
        </li>
      </ul>
      <div v-else class="panel settings__section stack">
        <p>{{ t("connectedApps.empty") }}</p>
        <p class="muted break-word">{{ t("connectedApps.howTo", { url: mcpUrl }) }}</p>
        <p><a :href="MCP_GUIDE_URL" target="_blank" rel="noopener noreferrer">{{ t("connectedApps.guide") }}</a></p>
      </div>
    </section>

    <ConfirmDialog
      v-model:open="disconnectOpen"
      :title="t('connectedApps.disconnect', { name: disconnecting?.client_name ?? '' })"
      :message="t('connectedApps.disconnectConfirm', { name: disconnecting?.client_name ?? '' })"
      :confirm-label="t('connectedApps.disconnectAction')"
      danger
      :on-confirm="disconnect"
    />
  </section>
</template>

<style scoped>
.settings { max-inline-size: 640px; }
.settings__section { padding: var(--space-4); }
.connections { display: grid; padding: var(--space-1) 0; }

.connection {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  padding: var(--space-2) var(--space-4);

  & + & { border-block-start: 1px solid var(--color-border); }
}

.connection__name { font-weight: 500; }
</style>
