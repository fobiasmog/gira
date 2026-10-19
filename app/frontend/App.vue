<script setup lang="ts">
import { onMounted, ref } from "vue"
import { storeToRefs } from "pinia"
import AppShell from "./components/shell/AppShell.vue"
import { useMeStore } from "./stores/me.ts"
import { useProjectsStore } from "./stores/projects.ts"
import { t } from "./i18n/index.ts"

const me = useMeStore()
const { profile } = storeToRefs(me)
const projects = useProjectsStore()
const failed = ref(false)

async function boot() {
  failed.value = false
  try {
    await Promise.all([me.load(), projects.load()])
  } catch {
    failed.value = true
  }
}

onMounted(boot)
</script>

<template>
  <AppShell v-if="profile" />
  <div v-else-if="failed" class="loading stack" role="alert">
    <p>{{ t("app.loadFailed") }}</p>
    <p><button type="button" class="button" @click="boot">{{ t("app.retry") }}</button></p>
  </div>
  <p v-else class="loading">{{ t("common.loading") }}</p>
</template>
