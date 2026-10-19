import { generateHTML, type JSONContent } from "@tiptap/core"
import { MarkdownManager } from "@tiptap/markdown"
import { MARKED_OPTIONS, markdownExtensions } from "./extensions.ts"

const extensions = markdownExtensions()
let manager: MarkdownManager | null = null

function markdown(): MarkdownManager {
  manager ??= new MarkdownManager({ extensions, markedOptions: MARKED_OPTIONS })
  return manager
}

export function parseMarkdown(source: string): JSONContent {
  return markdown().parse(source)
}

const CACHE_LIMIT = 300
const cache = new Map<string, string>()

// HTML for Markdown, produced only through the editor's schema: anything the
// schema has no node or mark for cannot appear in the output.
export function renderMarkdown(source: string): string {
  const cached = cache.get(source)
  if (cached !== undefined) return cached

  const html = source.trim() ? generateHTML(parseMarkdown(source), extensions) : ""
  if (cache.size >= CACHE_LIMIT) cache.delete(cache.keys().next().value!)
  cache.set(source, html)
  return html
}
