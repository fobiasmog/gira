<script setup lang="ts">
import { computed } from "vue"
import AppIcon from "./ui/AppIcon.vue"
import type { UserCard } from "../api/types.ts"

// Decorative: wherever the person matters, their name is shown or used as the
// control's accessible name.
//
// An agent's avatar carries a robot badge, and a deleted agent's is dashed
// and faded as well (spec web-client, "Agent marker"). The badge is the
// visible marker; its accessible name is in the text beside it: AgentChip or
// personName(), which say "agent" in words.
type AvatarUser = Pick<UserCard, "name" | "avatar_url"> & Partial<Pick<UserCard, "agent" | "deleted">>
const props = withDefaults(defineProps<{ user: AvatarUser | null; size?: number }>(), { size: 32 })
const initials = computed(() => props.user?.name.split(/\s+/).map((word) => word[0]).join("").slice(0, 2).toUpperCase() ?? "")
const badgeSize = computed(() => Math.max(12, Math.round(props.size * 0.5)))
</script>

<template>
  <span v-if="user?.agent" class="avatar-frame" :class="{ 'avatar-frame--deleted': user.deleted }" data-agent>
    <img v-if="user.avatar_url" class="avatar" :src="user.avatar_url" alt="" :width="size" :height="size">
    <span v-else class="avatar avatar--initials" aria-hidden="true">{{ initials }}</span>
    <span class="avatar__badge" aria-hidden="true"><AppIcon name="robot" :size="badgeSize" /></span>
  </span>
  <img v-else-if="user?.avatar_url" class="avatar" :src="user.avatar_url" alt="" :width="size" :height="size">
  <span v-else class="avatar avatar--initials" :class="{ 'avatar--empty': !user }" aria-hidden="true">{{ initials }}</span>
</template>

<style scoped>
.avatar {
  flex: none;
  inline-size: calc(v-bind(size) * 1px);
  block-size: calc(v-bind(size) * 1px);
  border-radius: 50%;
  object-fit: cover;
}

.avatar--initials {
  display: inline-grid;
  place-items: center;
  background: var(--color-badge);
  color: var(--color-badge-text);
  font-size: calc(v-bind(size) * 0.4px);
  font-weight: 500;
}

.avatar--empty {
  background: none;
  border: 1.5px dashed var(--color-control-border);
}

.avatar-frame {
  position: relative;
  display: inline-flex;
  flex: none;
}

.avatar__badge {
  position: absolute;
  inset-block-end: -3px;
  inset-inline-end: -3px;
  display: grid;
  place-items: center;
  border-radius: 50%;
  background: var(--color-surface);
  color: var(--color-text);
  box-shadow: 0 0 0 1px var(--color-control-border);
}

.avatar-frame--deleted .avatar {
  opacity: 0.5;
  outline: 1.5px dashed var(--color-control-border);
  outline-offset: 1px;
}
</style>
