<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from "vue"
import { EditorContent, useEditor } from "@tiptap/vue-3"
import type { EditorView } from "@tiptap/pm/view"
import AppDialog from "./ui/AppDialog.vue"
import AppField from "./ui/AppField.vue"
import AppIcon, { type IconName } from "./ui/AppIcon.vue"
import { isAllowedUrl, markdownExtensions } from "../editor/extensions.ts"
import { useAutosave } from "../composables/useAutosave.ts"
import { t, type MessageKey } from "../i18n/index.ts"

// Edits Markdown in a formatting editor and saves it on blur and after a
// second without typing (spec markdown-content, "Description editor").
const props = defineProps<{ markdown: string; label: string; save: (markdown: string) => Promise<void>; onError: (error: unknown) => void }>()

let lastSaved = props.markdown
const autosave = useAutosave(async () => {
  const markdown = editor.value?.getMarkdown() ?? lastSaved
  if (markdown === lastSaved) return
  // Set first: the save updates the markdown prop, which must not be loaded
  // back into the editor.
  const previous = lastSaved
  lastSaved = markdown
  try {
    await props.save(markdown)
  } catch (error) {
    lastSaved = previous
    throw error
  }
}, props.onError)

// Plain-text clipboard content (no HTML flavour) is read as Markdown, except
// inside a code block, where it stays literal.
function handlePaste(_view: EditorView, event: ClipboardEvent): boolean {
  const data = event.clipboardData
  const text = data?.getData("text/plain")
  if (!editor.value || !text || data?.types.includes("text/html") || editor.value.isActive("codeBlock")) return false
  editor.value.chain().focus().insertContent(text, { contentType: "markdown" }).run()
  return true
}

const editor = useEditor({
  extensions: markdownExtensions({ placeholder: t("editor.placeholder") }),
  content: props.markdown,
  contentType: "markdown",
  injectCSS: false,
  editorProps: {
    attributes: { "aria-label": props.label, "aria-multiline": "true", role: "textbox", class: "description-editor__content markdown" },
    handlePaste,
  },
  onUpdate: () => autosave.schedule(),
  onBlur: () => { void autosave.flush() },
})

// A different task (or a reload from the server) replaces the content
// without saving it back.
watch(() => props.markdown, (markdown) => {
  if (!editor.value || markdown === lastSaved || autosave.pending.value) return
  lastSaved = markdown
  editor.value.commands.setContent(markdown, { contentType: "markdown", emitUpdate: false })
})

onBeforeUnmount(() => { void autosave.flush() })

interface Tool { label: MessageKey; icon: IconName; run: () => void; active?: () => boolean; enabled?: () => boolean }
const chain = () => editor.value!.chain().focus()
const tools = computed<Tool[][]>(() => [
  [
    { label: "editor.heading1", icon: "format_h1", run: () => chain().toggleHeading({ level: 1 }).run(), active: () => editor.value!.isActive("heading", { level: 1 }) },
    { label: "editor.heading2", icon: "format_h2", run: () => chain().toggleHeading({ level: 2 }).run(), active: () => editor.value!.isActive("heading", { level: 2 }) },
    { label: "editor.heading3", icon: "format_h3", run: () => chain().toggleHeading({ level: 3 }).run(), active: () => editor.value!.isActive("heading", { level: 3 }) },
  ],
  [
    { label: "editor.bold", icon: "format_bold", run: () => chain().toggleBold().run(), active: () => editor.value!.isActive("bold") },
    { label: "editor.italic", icon: "format_italic", run: () => chain().toggleItalic().run(), active: () => editor.value!.isActive("italic") },
    { label: "editor.strike", icon: "format_strikethrough", run: () => chain().toggleStrike().run(), active: () => editor.value!.isActive("strike") },
    { label: "editor.code", icon: "code", run: () => chain().toggleCode().run(), active: () => editor.value!.isActive("code") },
    { label: "editor.link", icon: "link", run: openLinkDialog, active: () => editor.value!.isActive("link") },
  ],
  [
    { label: "editor.bulletList", icon: "format_list_bulleted", run: () => chain().toggleBulletList().run(), active: () => editor.value!.isActive("bulletList") },
    { label: "editor.orderedList", icon: "format_list_numbered", run: () => chain().toggleOrderedList().run(), active: () => editor.value!.isActive("orderedList") },
    { label: "editor.taskList", icon: "checklist", run: () => chain().toggleTaskList().run(), active: () => editor.value!.isActive("taskList") },
    { label: "editor.blockquote", icon: "format_quote", run: () => chain().toggleBlockquote().run(), active: () => editor.value!.isActive("blockquote") },
    { label: "editor.codeBlock", icon: "code_blocks", run: () => chain().toggleCodeBlock().run(), active: () => editor.value!.isActive("codeBlock") },
  ],
  [
    { label: "editor.undo", icon: "undo", run: () => chain().undo().run(), enabled: () => editor.value!.can().undo() },
    { label: "editor.redo", icon: "redo", run: () => chain().redo().run(), enabled: () => editor.value!.can().redo() },
  ],
])

// Toolbar keyboard pattern: one tab stop, arrow keys move between buttons.
const toolbar = ref<HTMLElement>()
function onToolbarKey(event: KeyboardEvent) {
  if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return
  const buttons = [...(toolbar.value?.querySelectorAll<HTMLButtonElement>("button:not(:disabled)") ?? [])]
  const index = buttons.indexOf(document.activeElement as HTMLButtonElement)
  const next = event.key === "Home" ? 0 : event.key === "End" ? buttons.length - 1
    : (index + (event.key === "ArrowRight" ? 1 : -1) + buttons.length) % buttons.length
  buttons.forEach((button, i) => { button.tabIndex = i === next ? 0 : -1 })
  buttons[next]?.focus()
  event.preventDefault()
}

const linkOpen = ref(false)
const linkUrl = ref("")
const linkError = ref<string[]>([])

function openLinkDialog() {
  linkUrl.value = editor.value?.getAttributes("link").href ?? ""
  linkError.value = []
  linkOpen.value = true
}

function applyLink() {
  const href = linkUrl.value.trim()
  if (href && !isAllowedUrl(href)) {
    linkError.value = [t("editor.linkInvalid")]
    return
  }
  const link = chain().extendMarkRange("link")
  if (href) link.setLink({ href }).run()
  else link.unsetLink().run()
  linkOpen.value = false
}
</script>

<template>
  <div v-if="editor" class="description-editor">
    <div ref="toolbar" class="description-editor__toolbar" role="toolbar" :aria-label="t('editor.toolbar')" @keydown="onToolbarKey">
      <div v-for="(group, g) in tools" :key="g" class="row description-editor__group">
        <button
          v-for="(tool, i) in group"
          :key="tool.label"
          type="button"
          class="icon-button"
          :tabindex="g === 0 && i === 0 ? 0 : -1"
          :aria-label="t(tool.label)"
          :title="t(tool.label)"
          :aria-pressed="tool.active ? tool.active() : undefined"
          :disabled="tool.enabled ? !tool.enabled() : false"
          @mousedown.prevent
          @click="tool.run()"
        >
          <AppIcon :name="tool.icon" :size="20" />
        </button>
      </div>
    </div>
    <EditorContent :editor="editor" />

    <AppDialog v-model:open="linkOpen" :title="t('editor.link')">
      <form id="description-link" class="stack" @submit.prevent="applyLink">
        <AppField :label="t('editor.linkUrl')" :hint="t('editor.linkHint')" :errors="linkError">
          <template #default="{ control }">
            <input v-model="linkUrl" v-bind="control" class="input" type="text" inputmode="url" autocomplete="url">
          </template>
        </AppField>
      </form>
      <template #actions>
        <button type="button" class="button button--text" @click="linkOpen = false">{{ t("common.cancel") }}</button>
        <button type="submit" form="description-link" class="button">{{ t("common.save") }}</button>
      </template>
    </AppDialog>
  </div>
</template>

<style scoped>
.description-editor {
  border: 1px solid var(--color-border);
  border-radius: var(--radius);
  background: var(--color-surface);

  &:has(.description-editor__content:focus-visible) { outline: 2px solid var(--color-focus); outline-offset: 2px; }
}

.description-editor__toolbar {
  position: sticky;
  top: 0;
  z-index: 1;
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-1) var(--space-3);
  padding: var(--space-1) var(--space-2);
  border-block-end: 1px solid var(--color-border);
  border-start-start-radius: var(--radius);
  border-start-end-radius: var(--radius);
  background: var(--color-surface);
}

.description-editor__group { gap: 0; }
.description-editor__group .icon-button { --target-size: 32px; border-radius: var(--radius-sm); }
.description-editor__group .icon-button[aria-pressed="true"] { background: var(--color-main-lighter); color: var(--color-main-dark); }

.description-editor :deep(.description-editor__content) {
  min-block-size: 8rem;
  padding: var(--space-3) var(--space-4);
}
</style>
