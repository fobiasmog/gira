<script setup lang="ts">
import { computed, type Directive } from "vue"
import { renderMarkdown } from "../editor/markdown.ts"

// The client's only HTML sink (enforced by script/check-frontend-policy.mjs).
// The HTML comes from renderMarkdown, which is bounded by the editor schema;
// the Sanitizer API, where available, is defence in depth.
const props = defineProps<{ source: string | null | undefined }>()
const html = computed(() => renderMarkdown(props.source ?? ""))

// Exactly what the schema renders. setHTML still applies its built-in safe
// rules (no scripts, event handlers or javascript: URLs) on top of this.
const SANITIZER = {
  elements: ["p", "br", "h1", "h2", "h3", "strong", "em", "s", "code", "pre", "blockquote", "ul", "ol", "li", "a", "label", "input", "span", "div"],
  attributes: ["href", "target", "rel", "title", "start", "type", "checked", "class", "data-type", "data-checked"],
}

interface SanitizingElement extends Element {
  setHTML?: (html: string, options: { sanitizer: typeof SANITIZER }) => void
}

function inject(el: SanitizingElement, value: string) {
  if (typeof el.setHTML === "function") el.setHTML(value, { sanitizer: SANITIZER })
  else el.innerHTML = value
  // Task-list checkboxes are toggled in the editor, not here.
  for (const input of el.querySelectorAll("input")) input.disabled = true
}

const vMarkdownHtml: Directive<SanitizingElement, string> = {
  mounted: (el, { value }) => inject(el, value),
  updated: (el, { value, oldValue }) => { if (value !== oldValue) inject(el, value) },
}
</script>

<template>
  <div v-markdown-html="html" class="markdown" />
</template>
