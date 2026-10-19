<script setup lang="ts">
import { ref } from "vue"
import AppDialog from "../components/ui/AppDialog.vue"
import AppField from "../components/ui/AppField.vue"
import AppMenu from "../components/ui/AppMenu.vue"
import AppTextarea from "../components/ui/AppTextarea.vue"
import AppToast from "../components/ui/AppToast.vue"
import AppIcon from "../components/ui/AppIcon.vue"
import { useMediaQuery } from "../composables/useMediaQuery.ts"
import { useUiStore } from "../stores/ui.ts"

// Test-only page (built with --mode test) for system tests of the shared UI
// components.
const ui = useUiStore()
const dialogOpen = ref(false)
const sprintName = ref("")
const picked = ref("nothing")
const notes = ref("")
const wide = useMediaQuery("(min-width: 800px)")
</script>

<template>
  <main class="stack fixture">
    <h1>Component fixtures</h1>

    <section class="row">
      <button type="button" class="button" @click="dialogOpen = true">New sprint</button>
      <AppDialog v-model:open="dialogOpen" title="New sprint">
        <AppField label="Sprint name">
          <template #default="{ control }">
            <input v-model="sprintName" v-bind="control" class="input">
          </template>
        </AppField>
        <template #actions>
          <button type="button" class="button button--text" @click="dialogOpen = false">Cancel</button>
          <button type="button" class="button" @click="dialogOpen = false">Create</button>
        </template>
      </AppDialog>
    </section>

    <section class="row">
      <AppMenu label="Options">
        <template #trigger="{ id, expanded }">
          <button type="button" class="button button--secondary" :popovertarget="id" :aria-expanded="expanded">Options</button>
        </template>
        <template #default="{ close }">
          <button type="button" class="menu__item" @click="picked = 'first'; close()">First option</button>
          <button type="button" class="menu__item" @click="picked = 'second'; close()">Second option</button>
        </template>
      </AppMenu>
      <span>Picked: {{ picked }}</span>
    </section>

    <section class="row">
      <button type="button" class="button" @click="ui.toast('Changes saved')">Show toast</button>
      <button type="button" class="button button--danger" @click="ui.toast('Could not save', 'error')">Show error</button>
    </section>

    <AppField label="Notes" :errors="notes.length > 200 ? ['Too long'] : []">
      <template #default="{ control }">
        <AppTextarea v-model="notes" v-bind="control" />
      </template>
    </AppField>

    <p class="row"><AppIcon name="settings" /> Wide: {{ wide ? "yes" : "no" }}</p>
    <AppToast />
  </main>
</template>

<style scoped>
.fixture { max-inline-size: 640px; margin: var(--space-6) auto; padding: var(--space-4); }
</style>
