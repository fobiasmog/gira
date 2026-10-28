<script setup lang="ts">
import { ref } from "vue"
import AppDialog from "../components/ui/AppDialog.vue"
import AppField from "../components/ui/AppField.vue"
import AppMenu from "../components/ui/AppMenu.vue"
import AppTextarea from "../components/ui/AppTextarea.vue"
import AppToast from "../components/ui/AppToast.vue"
import AppIcon, { type IconName } from "../components/ui/AppIcon.vue"
import ProgressBar from "../components/ProgressBar.vue"
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
const callIcons: IconName[] = [
  "call", "call_end", "mic", "mic_off", "videocam", "videocam_off", "open_in_full", "close_fullscreen",
  "keyboard_arrow_down", "volume_up",
]
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

    <ul role="list" class="row row--wrap" aria-label="Call icons">
      <li v-for="name in callIcons" :key="name" :data-icon="name"><AppIcon :name="name" /></li>
    </ul>

    <section class="panel stack styles" aria-label="Styles">
      <p class="row row--wrap">
        <span class="chip">Plain</span>
        <span v-for="tone in 6" :key="tone" class="chip" :data-tone="tone">Tone {{ tone }}</span>
      </p>
      <p class="row row--wrap">
        <span class="section-title">Subtasks <span class="badge">5</span></span>
        <span v-for="tone in 6" :key="tone" class="marker" :data-tone="tone" />
        <span class="dot" data-done />
        <button type="button" class="button button--secondary">Secondary</button>
        <button type="button" class="button button--text">Text</button>
        <button type="button" class="icon-button" aria-label="Add"><AppIcon name="add" /></button>
      </p>
      <nav class="segmented" aria-label="Layout">
        <button type="button" aria-pressed="true">Board</button>
        <button type="button" aria-pressed="false">List</button>
      </nav>
      <input class="input" aria-label="Sample field" placeholder="Sample field">
      <ProgressBar :done="3" :total="12" label="3 of 12 done" />
    </section>
    <AppToast />
  </main>
</template>

<style scoped>
.fixture { max-inline-size: 640px; margin: var(--space-6) auto; padding: var(--space-4); }
.styles { padding: var(--space-4); }
</style>
