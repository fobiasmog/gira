<script setup lang="ts">
import { onMounted } from "vue"
import { storeToRefs } from "pinia"
import MarkdownView from "../MarkdownView.vue"
import { useAnnouncementsStore } from "../../stores/announcements.ts"
import { useUiStore } from "../../stores/ui.ts"
import { t } from "../../i18n/index.ts"

const store = useAnnouncementsStore()
const { announcements } = storeToRefs(store)
const ui = useUiStore()

onMounted(() => store.load().catch(() => {}))

async function dismiss() {
  await store.dismissAll().catch(ui.fail)
}
</script>

<template>
  <section v-if="announcements.length" class="announcements" aria-labelledby="announcements-title">
    <header class="row">
      <h2 id="announcements-title" class="grow">{{ t("announcements.title") }}</h2>
      <button type="button" class="button button--text" @click="dismiss">{{ t("announcements.dismiss") }}</button>
    </header>
    <MarkdownView v-for="announcement in announcements" :key="announcement.id" :source="announcement.body" class="announcement" />
  </section>
</template>

<style scoped>
.announcements {
  display: grid;
  gap: var(--space-2);
  margin-block-end: var(--space-4);
  padding: var(--space-3) var(--space-4);
  border-radius: var(--radius);
  border-inline-start: 3px solid var(--color-main);
  background: var(--color-main-lighter);
}

.announcements h2 { font-size: var(--text-md); }
.announcement + .announcement { padding-block-start: var(--space-2); border-block-start: 1px solid var(--color-main-light); }
</style>
