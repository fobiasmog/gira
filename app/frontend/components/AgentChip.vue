<script setup lang="ts">
import type { UserCard } from "../api/types.ts"
import { t } from "../i18n/index.ts"

// The agent marker in words, next to a name that is shown as text (spec
// web-client, "Agent marker"). Nothing for a person.
defineProps<{ user: Partial<Pick<UserCard, "agent" | "deleted">> | null }>()
</script>

<template>
  <span v-if="user?.agent" class="chip agent-chip" :class="{ 'agent-chip--deleted': user.deleted }">
    {{ user.deleted ? t("agents.deletedAgent") : t("agents.agent") }}
  </span>
</template>

<style scoped>
.agent-chip { flex: none; }

.agent-chip--deleted {
  background: none;
  border: 1px dashed var(--color-control-border);
  color: var(--color-muted);
}
</style>
