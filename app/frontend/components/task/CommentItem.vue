<script setup lang="ts">
import { ref } from "vue"
import AppIcon from "../ui/AppIcon.vue"
import AppMenu from "../ui/AppMenu.vue"
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
    <UserAvatar :user="comment.author" :size="32" class="comment__avatar" />
    <div class="comment__body">
      <header class="comment__header">
        <strong class="comment__author">{{ comment.author.name }}</strong>
        <time class="comment__meta" :datetime="comment.created_at">{{ formatDateTime(language, comment.created_at) }}</time>
        <span v-if="comment.updated_at !== comment.created_at" class="comment__meta">· {{ t("task.edited") }}</span>
        <span class="grow" />
        <AppMenu v-if="editable && !editing" :label="t('task.commentActions')" align="end">
          <template #trigger="{ id, expanded }">
            <button type="button" class="icon-button comment__actions" :popovertarget="id" :aria-expanded="expanded" :aria-label="t('task.commentActions')">
              <AppIcon name="more_vert" :size="20" />
            </button>
          </template>
          <template #default="{ close }">
            <button type="button" class="menu__item" @click="close(); edit()"><AppIcon name="edit" :size="20" />{{ t("task.editComment") }}</button>
            <button type="button" class="menu__item" @click="close(); confirmingDelete = true"><AppIcon name="delete" :size="20" />{{ t("task.deleteComment") }}</button>
          </template>
        </AppMenu>
      </header>

      <form v-if="editing" class="stack" @submit.prevent="submit">
        <AppTextarea v-model="draft" :aria-label="t('task.editComment')" />
        <div class="row">
          <button type="submit" class="button" :disabled="busy">{{ t("common.save") }}</button>
          <button type="button" class="button button--text" @click="editing = false">{{ t("common.cancel") }}</button>
        </div>
      </form>
      <MarkdownView v-else :source="comment.body" class="comment__text" />

      <ul v-if="comment.attachments.length" role="list" class="attachments" :aria-label="t('task.attachments')">
        <li v-for="file in comment.attachments" :key="file.url">
          <a :href="file.url" class="attachment">
            <img v-if="file.preview_url" :src="file.preview_url" alt="" class="attachment__preview">
            <span v-else class="attachment__icon"><AppIcon name="description" :size="20" /></span>
            <span class="attachment__text">
              <span class="attachment__name ellipsis">{{ file.filename }}</span>
              <span class="attachment__size">{{ size(file.byte_size) }}</span>
            </span>
          </a>
        </li>
      </ul>
    </div>

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
.comment { display: flex; align-items: flex-start; gap: var(--space-3); }
.comment__avatar { margin-block-start: 2px; }
.comment__body { display: grid; flex-grow: 1; gap: var(--space-2); min-inline-size: 0; }

.comment__header {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-1) var(--space-2);
  min-block-size: 32px;
  font-size: var(--text-sm);
}

.comment__author { font-weight: 500; }
.comment__meta { color: var(--color-muted); font-size: var(--text-xs); }
.comment__actions { --target-size: 32px; }

.comment__text {
  padding: var(--space-3) var(--space-4);
  border: 1px solid var(--color-border);
  border-radius: 0 var(--radius-card) var(--radius-card);
  background: var(--color-surface-raised);
}

.attachments { display: flex; flex-wrap: wrap; gap: var(--space-2); }

.attachment {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  inline-size: 240px;
  max-inline-size: 100%;
  padding: var(--space-2);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-card);
  background: var(--color-surface);
  color: var(--color-text);
  text-decoration: none;

  &:hover { border-color: var(--color-main-light); color: var(--color-text); }
}

.attachment__preview,
.attachment__icon {
  flex: none;
  inline-size: 40px;
  block-size: 40px;
  border-radius: var(--radius);
  object-fit: cover;
}

.attachment__icon { display: grid; place-items: center; background: var(--color-badge); color: var(--color-badge-text); }
.attachment__text { display: grid; min-inline-size: 0; font-size: var(--text-sm); line-height: 1.35; }
.attachment__name { font-weight: 500; }
.attachment__size { color: var(--color-muted); font-size: var(--text-xs); }
</style>
