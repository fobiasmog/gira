<script setup lang="ts">
import { computed, ref, useId } from "vue"
import AppField from "../ui/AppField.vue"
import AppIcon from "../ui/AppIcon.vue"
import AppTextarea from "../ui/AppTextarea.vue"
import { ACCEPT, attachmentProblems, MAX_ATTACHMENTS, type AttachmentProblem } from "../../api/attachments.ts"
import { ApiError } from "../../api/client.ts"
import { useUiStore } from "../../stores/ui.ts"
import { t } from "../../i18n/index.ts"

const props = defineProps<{ post: (body: string, files: File[]) => Promise<void> }>()
const body = ref("")
const files = ref<File[]>([])
const serverErrors = ref<string[]>([])
const busy = ref(false)
const ui = useUiStore()
const fileInputId = useId()

function describe(problem: AttachmentProblem): string {
  switch (problem.kind) {
    case "tooMany": return t("task.tooManyFiles", { count: problem.count })
    case "tooLarge": return t("task.fileTooLarge", { name: problem.name })
    case "type": return t("task.fileType", { name: problem.name })
  }
}

const problems = computed(() => attachmentProblems(files.value).map(describe))
const errors = computed(() => [...problems.value, ...serverErrors.value])

function onFiles(event: Event) {
  const input = event.target as HTMLInputElement
  files.value = [...files.value, ...(input.files ?? [])]
  input.value = ""
}

function removeFile(index: number) {
  files.value = files.value.filter((_, i) => i !== index)
}

async function submit() {
  if (!body.value.trim() || problems.value.length) return
  busy.value = true
  serverErrors.value = []
  try {
    await props.post(body.value, files.value)
    body.value = ""
    files.value = []
  } catch (error) {
    if (error instanceof ApiError && error.status === 422) serverErrors.value = Object.values(error.fields).flat()
    else ui.fail(error)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <form class="stack comment-form" @submit.prevent="submit">
    <AppField :label="t('task.newComment')" :hint="t('task.commentHint')" :errors="errors">
      <template #default="{ control }">
        <AppTextarea v-model="body" v-bind="control" />
      </template>
    </AppField>

    <ul v-if="files.length" role="list" class="row row--wrap">
      <li v-for="(file, index) in files" :key="`${file.name}-${index}`" class="chip file-chip">
        <span class="ellipsis">{{ file.name }}</span>
        <button type="button" class="icon-button" :aria-label="t('task.removeFile', { name: file.name })" @click="removeFile(index)">
          <AppIcon name="close" :size="16" />
        </button>
      </li>
    </ul>

    <div class="row row--wrap">
      <label :for="fileInputId" class="button button--secondary">
        <AppIcon name="attach_file" :size="20" />{{ t("task.attachFiles") }}
      </label>
      <input :id="fileInputId" type="file" multiple :accept="ACCEPT" class="visually-hidden" @change="onFiles">
      <span class="small muted grow">{{ t("task.attachmentsHint", { count: MAX_ATTACHMENTS }) }}</span>
      <button type="submit" class="button" :disabled="busy || !body.trim() || problems.length > 0">{{ t("task.postComment") }}</button>
    </div>
  </form>
</template>

<style scoped>
.file-chip { display: inline-flex; align-items: center; gap: var(--space-1); max-inline-size: 16rem; padding-inline-end: 0; }
.file-chip .icon-button { --target-size: 24px; }
label.button:has(+ input:focus-visible) { outline: 2px solid var(--color-focus); outline-offset: 2px; }
</style>
