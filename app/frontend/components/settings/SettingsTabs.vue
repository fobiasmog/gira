<script setup lang="ts">
import { useRoute } from "vue-router"
import { t } from "../../i18n/index.ts"

const route = useRoute()
</script>

<template>
  <nav class="segmented" :aria-label="t('settings.sections')">
    <RouterLink :to="{ name: 'settings-profile' }" :aria-current="route.name === 'settings-profile' ? 'page' : undefined">{{ t("settings.profile") }}</RouterLink>
    <RouterLink :to="{ name: 'settings-security' }" :aria-current="route.name === 'settings-security' ? 'page' : undefined">{{ t("settings.security") }}</RouterLink>
  </nav>
</template>
