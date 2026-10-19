<script setup lang="ts">
import { computed, ref, watch } from "vue"
import { storeToRefs } from "pinia"
import AppIcon from "../components/ui/AppIcon.vue"
import ConfirmDialog from "../components/ui/ConfirmDialog.vue"
import ProgressBar from "../components/ProgressBar.vue"
import type { Milestone } from "../api/types.ts"
import { useMilestonesStore } from "../stores/milestones.ts"
import { useUiStore } from "../stores/ui.ts"
import { t } from "../i18n/index.ts"

const props = defineProps<{ projectId: number }>()
const store = useMilestonesStore()
const { milestones, deleted } = storeToRefs(store)
const ui = useUiStore()
const loaded = ref(false)
const title = ref("")
const deleting = ref<Milestone | null>(null)
const deleteOpen = computed({ get: () => deleting.value !== null, set: (open) => { if (!open) deleting.value = null } })

watch(() => props.projectId, async (id) => {
  loaded.value = false
  await ui.load(store.load(id))
  loaded.value = store.projectId === id
}, { immediate: true })

async function create() {
  const value = title.value.trim()
  if (!value) return
  try {
    await store.create(props.projectId, value)
    title.value = ""
  } catch (error) {
    ui.fail(error)
  }
}

async function remove() {
  const milestone = deleting.value
  if (!milestone) return
  try {
    await store.remove(props.projectId, milestone.id)
    ui.toast(t("milestones.deleted", { title: milestone.title }))
  } catch (error) {
    ui.fail(error)
  }
}

async function recover(milestone: Milestone) {
  try {
    await store.recover(props.projectId, milestone.id)
    ui.toast(t("milestones.recovered", { title: milestone.title }))
  } catch (error) {
    ui.fail(error)
  }
}
</script>

<template>
  <section v-if="loaded" class="page milestones-page">
    <h1>{{ t("milestones.title") }}</h1>
    <p class="muted">{{ t("milestones.info") }}</p>

    <form class="row" @submit.prevent="create">
      <input v-model="title" class="input grow" maxlength="100" :aria-label="t('milestones.new')" :placeholder="t('milestones.new')">
      <button type="submit" class="button"><AppIcon name="add" />{{ t("milestones.create") }}</button>
    </form>

    <ul v-if="milestones.length" role="list" class="milestones">
      <li v-for="milestone in milestones" :key="milestone.id" class="milestone panel">
        <div class="row">
          <RouterLink :to="{ name: 'milestone', params: { pid: projectId, mid: milestone.id } }" class="grow milestone__title break-word">{{ milestone.title }}</RouterLink>
          <button type="button" class="icon-button" :aria-label="`${t('milestones.delete')}: ${milestone.title}`" @click="deleting = milestone">
            <AppIcon name="delete" :size="20" />
          </button>
        </div>
        <ProgressBar :done="milestone.done" :total="milestone.total" :label="t('milestones.progress', { done: milestone.done, total: milestone.total })" />
        <p class="small muted">{{ t("milestones.progress", { done: milestone.done, total: milestone.total }) }}</p>
      </li>
    </ul>
    <p v-else class="empty-state panel">{{ t("milestones.empty") }}</p>

    <section v-if="deleted.length" class="stack" aria-labelledby="deleted-milestones">
      <h2 id="deleted-milestones">{{ t("milestones.deletedTitle") }}</h2>
      <ul role="list" class="stack">
        <li v-for="milestone in deleted" :key="milestone.id" class="row">
          <span class="grow muted">{{ milestone.title }}</span>
          <button type="button" class="button button--text" :aria-label="t('milestones.recover', { title: milestone.title })" @click="recover(milestone)">
            <AppIcon name="restore_from_trash" :size="20" />{{ t("milestones.recover", { title: "" }).trim() }}
          </button>
        </li>
      </ul>
    </section>

    <ConfirmDialog
      v-model:open="deleteOpen"
      :title="t('milestones.delete')"
      :message="t('milestones.deleteConfirm', { title: deleting?.title ?? '' })"
      :confirm-label="t('common.delete')"
      danger
      :on-confirm="remove"
    />
  </section>
</template>

<style scoped>
.milestones-page { max-inline-size: 840px; }
.milestones { display: grid; gap: var(--space-3); }
.milestone { display: grid; gap: var(--space-2); padding: var(--space-4); }
.milestone__title { font-size: var(--text-lg); font-weight: 500; text-decoration: none; }
</style>
