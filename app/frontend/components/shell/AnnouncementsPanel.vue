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
    <h2 id="announcements-title" class="announcements__title">{{ t("announcements.title") }}</h2>
    <div class="announcements__items">
      <MarkdownView v-for="announcement in announcements" :key="announcement.id" :source="announcement.body" class="announcement" />
    </div>
    <button type="button" class="button button--text announcements__dismiss" @click="dismiss">{{ t("announcements.dismiss") }}</button>
  </section>
</template>

<style scoped>
.announcements {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-start;
  gap: var(--space-2) var(--space-3);
  margin-block-end: var(--space-5);
  padding: var(--space-3) var(--space-3) var(--space-3) var(--space-4);
  border: 1px solid var(--color-main-light);
  border-radius: var(--radius-lg);
  background: var(--color-main-lighter);
}

.announcements__title {
  flex: none;
  margin-block-start: 6px;
  padding: 0 var(--space-2);
  border-radius: 999px;
  background: var(--color-primary);
  color: #fff;
  font-size: var(--text-xs);
  font-weight: 500;
  line-height: 1.8;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

.announcements__items {
  display: grid;
  flex: 1 1 20rem;
  gap: var(--space-2);
  min-inline-size: 0;
  padding-block: var(--space-1);
}

.announcements__dismiss { flex: none; margin-inline-start: auto; }
.announcement + .announcement { padding-block-start: var(--space-2); border-block-start: 1px solid var(--color-main-light); }
</style>
