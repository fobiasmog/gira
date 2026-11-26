<script setup lang="ts">
import { ref, watch } from "vue"
import AppDialog from "../ui/AppDialog.vue"
import AppField from "../ui/AppField.vue"
import AppTextarea from "../ui/AppTextarea.vue"
import { ApiError } from "../../api/client.ts"
import type { Change, FieldErrors } from "../../api/types.ts"
import { typedChangeName } from "../../composables/changes.ts"
import { useUiStore } from "../../stores/ui.ts"
import { t } from "../../i18n/index.ts"

// Asks for a new change's name and its idea (spec web-client, "New change
// dialog"). The name is lowercased and spaces become hyphens as it is typed;
// the server's validation errors are shown at their fields, and the dialog
// stays open.
const props = defineProps<{ create: (name: string, idea: string) => Promise<Change> }>()
const open = defineModel<boolean>("open", { required: true })
const emit = defineEmits<{ created: [change: Change] }>()

const ui = useUiStore()
const name = ref("")
const idea = ref("")
const errors = ref<FieldErrors>({})
const busy = ref(false)

watch(open, (value) => {
  if (!value) return
  name.value = ""
  idea.value = ""
  errors.value = {}
})

// Keeps the caret where it was: the typed name has as many characters.
function onInput(event: Event) {
  const input = event.target as HTMLInputElement
  const { selectionStart, selectionEnd } = input
  name.value = typedChangeName(input.value)
  if (input.value !== name.value) {
    input.value = name.value
    input.setSelectionRange(selectionStart, selectionEnd)
  }
}

async function submit() {
  if (busy.value) return
  busy.value = true
  errors.value = {}
  try {
    const change = await props.create(name.value.trim(), idea.value)
    open.value = false
    emit("created", change)
  } catch (error) {
    if (error instanceof ApiError && error.status === 422) errors.value = error.fields
    else ui.fail(error)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <AppDialog v-model:open="open" :title="t('changes.new')">
    <form id="new-change" class="stack" novalidate @submit.prevent="submit">
      <AppField :label="t('changes.name')" :hint="t('changes.nameHint')" :errors="errors.name">
        <template #default="{ control }">
          <input
            :value="name"
            v-bind="control"
            class="input"
            maxlength="100"
            required
            autocomplete="off"
            autocapitalize="none"
            spellcheck="false"
            @input="onInput"
          >
        </template>
      </AppField>
      <AppField :label="t('changes.idea')" :hint="t('changes.ideaHint')" :errors="errors.idea">
        <template #default="{ control }">
          <AppTextarea v-model="idea" v-bind="control" />
        </template>
      </AppField>
    </form>
    <template #actions>
      <button type="button" class="button button--text" @click="open = false">{{ t("common.cancel") }}</button>
      <button type="submit" form="new-change" class="button" :disabled="busy">{{ t("changes.create") }}</button>
    </template>
  </AppDialog>
</template>
