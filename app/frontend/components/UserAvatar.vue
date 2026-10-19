<script setup lang="ts">
import { computed } from "vue"
import type { UserCard } from "../api/types.ts"

// Decorative: wherever the person matters, their name is shown or used as the
// control's accessible name.
const props = withDefaults(defineProps<{ user: Pick<UserCard, "name" | "avatar_url"> | null; size?: number }>(), { size: 32 })
const initials = computed(() => props.user?.name.split(/\s+/).map((word) => word[0]).join("").slice(0, 2).toUpperCase() ?? "")
</script>

<template>
  <img v-if="user?.avatar_url" class="avatar" :src="user.avatar_url" alt="" :width="size" :height="size">
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
  background: var(--color-main-lighter);
  color: var(--color-main-dark);
  font-size: calc(v-bind(size) * 0.4px);
  font-weight: 500;
}

.avatar--empty {
  background: none;
  border: 1px dashed var(--color-subtle);
}
</style>
