<script setup lang="ts">
import { ref } from "vue"
import AppIcon from "../ui/AppIcon.vue"
import AppTextarea from "../ui/AppTextarea.vue"
import ConfirmDialog from "../ui/ConfirmDialog.vue"
import MarkdownView from "../MarkdownView.vue"
import UserAvatar from "../UserAvatar.vue"
import type { Comment } from "../../api/types.ts"
import { language, t } from "../../i18n/index.ts"
import { formatDateTime, formatNumber } from "../../i18n/format.ts"

const props = defineProps<{ comment: Comment; editable: boolean; save?: (body: string) => Promise<void>; remove?: () => Promise<void> }>()
const editing = ref(false)
const draft = ref("")
const confirmingDelete = ref(false)
const busy = ref(false)

function edit() {
  draft.value = props.comment.body
  editing.value = true
}

async function submit() {
  if (!draft.value.trim() || !props.save) return
  busy.value = true
  try {
    await props.save(draft.value)
    editing.value = false
  } finally {
    busy.value = false
  }
}

const size = (bytes: number) => `${formatNumber(language.value, Math.max(1, Math.round(bytes / 1024)))} KB`
</script>

<template>
  <li class="comment">
    <header class="row small">
      <UserAvatar :user="comment.author" :size="24" />
      <strong>{{ comment.author.name }}</strong>
      <time class="muted" :datetime="comment.created_at">{{ formatDateTime(language, comment.created_at) }}</time>
      <span v-if="comment.updated_at !== comment.created_at" class="muted">· {{ t("task.edited") }}</span>
      <span class="grow" />
      <template v-if="editable && !editing">
        <button type="button" class="icon-button" :aria-label="t('task.editComment')" @click="edit"><AppIcon name="edit" :size="18" /></button>
        <button type="button" class="icon-button" :aria-label="t('task.deleteComment')" @click="confirmingDelete = true"><AppIcon name="delete" :size="18" /></button>
      </template>
    </header>

    <form v-if="editing" class="stack" @submit.prevent="submit">
      <AppTextarea v-model="draft" :aria-label="t('task.editComment')" />
      <div class="row">
        <button type="submit" class="button" :disabled="busy">{{ t("common.save") }}</button>
        <button type="button" class="button button--text" @click="editing = false">{{ t("common.cancel") }}</button>
      </div>
    </form>
    <MarkdownView v-else :source="comment.body" />

    <ul v-if="comment.attachments.length" role="list" class="attachments" :aria-label="t('task.attachments')">
      <li v-for="file in comment.attachments" :key="file.url">
        <a :href="file.url" class="attachment">
          <img v-if="file.preview_url" :src="file.preview_url" alt="" class="attachment__preview">
          <AppIcon v-else name="description" />
          <span class="ellipsis">{{ file.filename }}</span>
          <span class="small muted">{{ size(file.byte_size) }}</span>
        </a>
      </li>
    </ul>

    <ConfirmDialog
      v-model:open="confirmingDelete"
      :title="t('task.deleteComment')"
      :message="t('task.deleteCommentConfirm')"
      :confirm-label="t('common.delete')"
      danger
      :on-confirm="() => remove?.()"
    />
  </li>
</template>

<style scoped>
.comment {
  display: grid;
  gap: var(--space-2);
  padding: var(--space-3);
  border-radius: var(--radius);
  background: var(--color-surface);
}

.attachments { display: flex; flex-wrap: wrap; gap: var(--space-2); }

.attachment {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  max-inline-size: 280px;
  padding: var(--space-1) var(--space-2);
  border: 1px solid var(--color-border);
  border-radius: var(--radius);
  text-decoration: none;
}

.attachment__preview { inline-size: 40px; block-size: 40px; object-fit: cover; border-radius: var(--radius-sm); }
</style>
