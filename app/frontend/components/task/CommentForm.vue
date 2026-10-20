<script setup lang="ts">
import { computed, ref, useId } from "vue"
import AppField from "../ui/AppField.vue"
import AppIcon from "../ui/AppIcon.vue"
import AppTextarea from "../ui/AppTextarea.vue"
import UserAvatar from "../UserAvatar.vue"
import { ACCEPT, attachmentProblems, MAX_ATTACHMENTS, type AttachmentProblem } from "../../api/attachments.ts"
import { ApiError } from "../../api/client.ts"
import { useMeStore } from "../../stores/me.ts"
import { useUiStore } from "../../stores/ui.ts"
import { t } from "../../i18n/index.ts"

const props = defineProps<{ post: (body: string, files: File[]) => Promise<void> }>()
const body = ref("")
const files = ref<File[]>([])
const serverErrors = ref<string[]>([])
const busy = ref(false)
const ui = useUiStore()
const me = useMeStore()
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
  <form class="comment-form" @submit.prevent="submit">
    <UserAvatar :user="me.profile" :size="32" class="comment-form__avatar" />
    <div class="comment-form__body">
      <AppField :label="t('task.newComment')" :hint="t('task.commentHint')" :errors="errors" hide-label>
        <template #default="{ control }">
          <div class="composer">
            <AppTextarea v-model="body" v-bind="control" class="composer__text" :placeholder="t('task.newComment')" />

            <ul v-if="files.length" role="list" class="composer__files">
              <li v-for="(file, index) in files" :key="`${file.name}-${index}`" class="chip file-chip">
                <span class="ellipsis">{{ file.name }}</span>
                <button type="button" class="icon-button" :aria-label="t('task.removeFile', { name: file.name })" @click="removeFile(index)">
                  <AppIcon name="close" :size="16" />
                </button>
              </li>
            </ul>

            <div class="composer__bar">
              <label :for="fileInputId" class="button button--text composer__attach">
                <AppIcon name="attach_file" :size="20" />{{ t("task.attachFiles") }}
              </label>
              <input :id="fileInputId" type="file" multiple :accept="ACCEPT" class="visually-hidden" @change="onFiles">
              <span class="composer__hint grow">{{ t("task.attachmentsHint", { count: MAX_ATTACHMENTS }) }}</span>
              <button type="submit" class="button" :disabled="busy || !body.trim() || problems.length > 0">{{ t("task.postComment") }}</button>
            </div>
          </div>
        </template>
      </AppField>
    </div>
  </form>
</template>

<style scoped>
.comment-form { display: flex; align-items: flex-start; gap: var(--space-3); }
.comment-form__avatar { margin-block-start: var(--space-1); }
.comment-form__body { flex-grow: 1; min-inline-size: 0; }

/* The text and its actions share one bordered box; the box is the field's
   visible boundary, so it takes the control border and the focus ring. */
.composer {
  display: grid;
  border: 1px solid var(--color-control-border);
  border-radius: var(--radius-card);
  background: var(--color-surface);

  &:hover { border-color: var(--color-main-dark); }
  &:has(.composer__text:focus-visible) { outline: 2px solid var(--color-focus); outline-offset: 0; border-color: var(--color-primary); }
  &:has([aria-invalid="true"]) { border-color: var(--color-danger); }
}

.composer__text,
.composer__text:hover,
.composer__text:focus-visible,
.composer__text:focus-within {
  border: none;
  border-radius: var(--radius-card) var(--radius-card) 0 0;
  outline: none;
  background: none;
}

.composer__files { display: flex; flex-wrap: wrap; gap: var(--space-2); padding: 0 var(--space-3) var(--space-2); }

.composer__bar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-2) var(--space-3);
  padding: var(--space-2);
  border-block-start: 1px solid var(--color-border);
  border-radius: 0 0 var(--radius-card) var(--radius-card);
  background: var(--color-surface-raised);
}

.composer__attach { color: var(--color-text); }
.composer__hint { color: var(--color-muted); font-size: var(--text-xs); }

.file-chip { display: inline-flex; align-items: center; gap: var(--space-1); max-inline-size: 16rem; padding-inline-end: 0; }
.file-chip .icon-button { --target-size: 24px; }
label.button:has(+ input:focus-visible) { outline: 2px solid var(--color-focus); outline-offset: 2px; }
</style>
