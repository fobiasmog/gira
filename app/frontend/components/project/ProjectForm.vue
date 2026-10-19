<script setup lang="ts">
import { computed, ref } from "vue"
import AppField from "../ui/AppField.vue"
import { ApiError } from "../../api/client.ts"
import type { ProjectFields } from "../../api/projects.ts"
import type { FieldErrors } from "../../api/types.ts"
import { useUiStore } from "../../stores/ui.ts"
import { t } from "../../i18n/index.ts"

// Title and short name. A 422 shows the server's messages under the fields
// and keeps what was typed.
const props = defineProps<{ initial?: ProjectFields; submitLabel: string; submit: (fields: ProjectFields) => Promise<void> }>()
const title = ref(props.initial?.title ?? "")
const shortName = ref(props.initial?.short_name ?? "")
const errors = ref<FieldErrors>({})
const busy = ref(false)
const ui = useUiStore()
const example = computed(() => `${shortName.value || "GOAL"}-1`)

async function onSubmit() {
  busy.value = true
  errors.value = {}
  try {
    await props.submit({ title: title.value.trim(), short_name: shortName.value.trim() })
  } catch (error) {
    if (error instanceof ApiError && error.status === 422) errors.value = error.fields
    else ui.fail(error)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <form class="stack project-form" novalidate @submit.prevent="onSubmit">
    <AppField :label="t('projects.name')" :errors="errors.title">
      <template #default="{ control }">
        <input v-model="title" v-bind="control" class="input" maxlength="100" required autocomplete="off">
      </template>
    </AppField>
    <AppField :label="t('projects.shortName')" :errors="errors.short_name" :hint="t('projects.shortNameHint', { example })">
      <template #default="{ control }">
        <input
          v-model="shortName"
          v-bind="control"
          class="input"
          maxlength="10"
          required
          autocomplete="off"
          autocapitalize="characters"
          spellcheck="false"
          @input="shortName = shortName.toUpperCase()"
        >
      </template>
    </AppField>
    <p><button type="submit" class="button" :disabled="busy">{{ submitLabel }}</button></p>
  </form>
</template>

<style scoped>
.project-form { max-inline-size: 480px; }
</style>
