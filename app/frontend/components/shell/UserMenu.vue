<script setup lang="ts">
import { computed } from "vue"
import { storeToRefs } from "pinia"
import AppMenu from "../ui/AppMenu.vue"
import AppIcon from "../ui/AppIcon.vue"
import UserAvatar from "../UserAvatar.vue"
import { useMeStore } from "../../stores/me.ts"
import { t } from "../../i18n/index.ts"

const { profile } = storeToRefs(useMeStore())
const firstName = computed(() => profile.value?.name.trim().split(/\s+/)[0] ?? "")
const csrfToken = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""
</script>

<template>
  <AppMenu v-if="profile" :label="profile.name" align="end">
    <template #trigger="{ id, expanded }">
      <button type="button" class="user-button" :popovertarget="id" :aria-expanded="expanded" :aria-label="profile.name">
        <UserAvatar :user="profile" :size="32" />
        <span class="user-button__name ellipsis" aria-hidden="true">{{ firstName }}</span>
        <AppIcon name="expand_more" :size="20" />
      </button>
    </template>
    <template #default="{ close }">
      <p class="user-menu__name ellipsis">{{ profile.name }}</p>
      <RouterLink :to="{ name: 'settings-profile' }" class="menu__item" @click="close">
        <AppIcon name="settings" />{{ t("navigation.settings") }}
      </RouterLink>
      <hr class="menu__separator">
      <form method="post" action="/session">
        <input type="hidden" name="_method" value="delete">
        <input type="hidden" name="authenticity_token" :value="csrfToken">
        <button type="submit" class="menu__item"><AppIcon name="logout" />{{ t("navigation.signOut") }}</button>
      </form>
    </template>
  </AppMenu>
</template>

<style scoped>
.user-button {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  min-block-size: var(--target-size);
  padding: 2px var(--space-1) 2px 2px;
  border: none;
  border-radius: 999px;
  background: none;
  color: var(--color-muted);

  &:hover { background: var(--color-main-tint); color: var(--color-text); }
}

.user-button__name { max-inline-size: 10rem; color: var(--color-text); font-size: var(--text-sm); font-weight: 500; }

@media (max-width: 480px) {
  .user-button__name { display: none; }
}

.user-menu__name {
  padding: var(--space-2) var(--space-3);
  font-weight: 500;
}
</style>
