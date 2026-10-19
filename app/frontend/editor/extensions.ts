import { Extension, InputRule, type JSONContent, type MarkdownParseHelpers, type MarkdownRendererHelpers, type MarkdownToken } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import { TaskItem, TaskList } from "@tiptap/extension-list"
import { Placeholder } from "@tiptap/extensions"
import { Markdown } from "@tiptap/markdown"

// The single feature set for editing and displaying Markdown (spec
// markdown-content). The editor and MarkdownView both use this list, so the
// schema doubles as the HTML allowlist.

export const LINK_ATTRIBUTES = { rel: "noopener noreferrer nofollow", target: "_blank" } as const

export function isAllowedUrl(url: unknown): boolean {
  return typeof url === "string" && /^(?:https?:\/\/|mailto:)/i.test(url.trim())
}

const plainText = (nodes: JSONContent[]): string =>
  nodes.map((node) => node.text ?? plainText(node.content ?? [])).join("")

const textNode = (helpers: MarkdownParseHelpers, text: string): JSONContent[] =>
  text ? [helpers.createTextNode(text)] : []

// Link's own Markdown parser does not check the URL; this one runs first
// (higher priority) and turns links to anything but http(s)/mailto into text.
const SafeMarkdownLinks = Extension.create({
  name: "safeMarkdownLinks",
  priority: 1001,
  markdownTokenName: "link",
  parseMarkdown: (token: MarkdownToken, helpers: MarkdownParseHelpers) => {
    const content = helpers.parseInline(token.tokens ?? [])
    if (!isAllowedUrl(token.href)) return content
    return helpers.applyMark("link", content, { href: token.href, title: token.title || null })
  },
})

// Images have no node: their alt text stays as plain text and nothing is
// fetched.
const ImagesAsText = Extension.create({
  name: "imagesAsText",
  markdownTokenName: "image",
  parseMarkdown: (token: MarkdownToken, helpers: MarkdownParseHelpers) => textNode(helpers, token.text ?? ""),
})

// Tables have no node: each row becomes a paragraph of its cells' plain text.
const TablesAsText = Extension.create({
  name: "tablesAsText",
  markdownTokenName: "table",
  parseMarkdown: (token: MarkdownToken, helpers: MarkdownParseHelpers) => {
    const rows: { tokens?: MarkdownToken[] }[][] = [token.header ?? [], ...(token.rows ?? [])]
    return rows.map((cells) =>
      helpers.createNode("paragraph", undefined, textNode(helpers, cells.map((cell) => plainText(helpers.parseInline(cell.tokens ?? []))).join(" | "))))
  },
})

// Headings deeper than level 3 are shown as level 3. The serializer looks up
// handlers by token name before node name, so this one also has to render
// headings (as Heading itself does).
const HeadingLevels = Extension.create({
  name: "headingLevels",
  priority: 101,
  markdownTokenName: "heading",
  parseMarkdown: (token: MarkdownToken, helpers: MarkdownParseHelpers) =>
    helpers.createNode("heading", { level: Math.min(token.depth ?? 1, 3) }, helpers.parseInline(token.tokens ?? [])),
  renderMarkdown: (node: JSONContent, helpers: MarkdownRendererHelpers) =>
    node.content ? `${"#".repeat(Number(node.attrs?.level ?? 1))} ${helpers.renderChildren(node.content)}` : "",
})

// The `- [ ] ` shortcut: "- " starts a bulleted list, then "[ ] " or "[x] " at
// the start of its first paragraph turns the list into a task list.
const BulletToTaskList = Extension.create({
  name: "bulletToTaskList",
  addInputRules() {
    return [
      new InputRule({
        find: /^\[([ xX])\]\s$/,
        handler: ({ state, range, match, chain }) => {
          const { $from } = state.selection
          if ($from.depth < 2 || $from.node(-1).type.name !== "listItem" || $from.node(-2).type.name !== "bulletList" || $from.index(-1) !== 0) return null
          chain().deleteRange(range).toggleTaskList().updateAttributes("taskItem", { checked: match[1] !== " " }).run()
        },
      }),
    ]
  },
})

export const MARKED_OPTIONS = { gfm: true, breaks: true }

export function markdownExtensions(options: { placeholder?: string } = {}) {
  return [
    StarterKit.configure({
      heading: { levels: [1, 2, 3] },
      underline: false,
      horizontalRule: false,
      link: {
        openOnClick: false,
        autolink: true,
        defaultProtocol: "https",
        HTMLAttributes: LINK_ATTRIBUTES,
        isAllowedUri: (url) => isAllowedUrl(url),
      },
    }),
    TaskList,
    TaskItem.configure({ nested: true }),
    BulletToTaskList,
    Placeholder.configure({ placeholder: options.placeholder ?? "" }),
    Markdown.configure({ markedOptions: MARKED_OPTIONS }),
    SafeMarkdownLinks,
    ImagesAsText,
    TablesAsText,
    HeadingLevels,
  ]
}
