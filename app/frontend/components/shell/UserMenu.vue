<script setup lang="ts">
import { storeToRefs } from "pinia"
import AppMenu from "../ui/AppMenu.vue"
import AppIcon from "../ui/AppIcon.vue"
import UserAvatar from "../UserAvatar.vue"
import { useMeStore } from "../../stores/me.ts"
import { t } from "../../i18n/index.ts"

const { profile } = storeToRefs(useMeStore())
const csrfToken = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""
</script>

<template>
  <AppMenu v-if="profile" :label="profile.name" align="end">
    <template #trigger="{ id, expanded }">
      <button type="button" class="user-button" :popovertarget="id" :aria-expanded="expanded" :aria-label="profile.name">
        <UserAvatar :user="profile" :size="36" />
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
  display: grid;
  place-items: center;
  padding: 2px;
  border: none;
  border-radius: 50%;
  background: none;
}

.user-menu__name {
  padding: var(--space-2) var(--space-4);
  font-weight: 500;
}
</style>
