#!/usr/bin/env node
// Frontend dependency and rendering policy (spec web-client, "Dependency
// policy" and "Safe rendering of user content"). Zero dependencies on purpose.
// Usage: node script/check-frontend-policy.mjs [repo root]
import { readFileSync, readdirSync, existsSync } from "node:fs"
import { join, relative, basename } from "node:path"

const root = process.argv[2] ?? join(import.meta.dirname, "..")
const frontend = join(root, "app/frontend")
const errors = []

const RUNTIME_REQUIRED = ["vue", "vue-router", "pinia", "@sentry/vue", "swagger-ui-dist"]
const RUNTIME_PATTERN = /^@tiptap\/[a-z0-9-]+$/
const DEV_REQUIRED = ["vite", "@vitejs/plugin-vue", "typescript", "vue-tsc"]
// Packages only one file may import: the API documentation viewer stays out
// of the single-page application.
const IMPORTED_ONLY_BY = { "swagger-ui-dist": "app/frontend/entrypoints/api-docs.ts" }
const EXACT_VERSION = /^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/

// --- package.json ---------------------------------------------------------
const pkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8"))
const runtime = pkg.dependencies ?? {}
const dev = pkg.devDependencies ?? {}

for (const field of ["optionalDependencies", "peerDependencies", "bundleDependencies", "bundledDependencies", "overrides"]) {
  if (pkg[field] && Object.keys(pkg[field]).length > 0) errors.push(`package.json: "${field}" is not allowed`)
}
for (const name of Object.keys(runtime)) {
  if (!RUNTIME_REQUIRED.includes(name) && !RUNTIME_PATTERN.test(name)) {
    errors.push(`package.json: dependency "${name}" is not on the allowlist`)
  }
}
for (const name of Object.keys(dev)) {
  if (!DEV_REQUIRED.includes(name)) errors.push(`package.json: devDependency "${name}" is not on the allowlist`)
}
for (const name of RUNTIME_REQUIRED) if (!(name in runtime)) errors.push(`package.json: dependency "${name}" is missing`)
for (const name of DEV_REQUIRED) if (!(name in dev)) errors.push(`package.json: devDependency "${name}" is missing`)
for (const [name, version] of [...Object.entries(runtime), ...Object.entries(dev)]) {
  if (!EXACT_VERSION.test(version)) errors.push(`package.json: "${name}" must be pinned to an exact version, not "${version}"`)
}
if (!existsSync(join(root, "package-lock.json"))) errors.push("package-lock.json is missing")

// --- sources --------------------------------------------------------------
const SOURCE = /\.(ts|vue|js|mjs|css|svg|html)$/
const isTest = (file) => /\.test\.ts$/.test(file)

function* walk(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) yield* walk(path)
    else if (SOURCE.test(entry.name)) yield path
  }
}

const IMPORT = /(?:\bimport\s*(?:[\w*{}\s,$]+\s*from\s*)?|\bexport\s*[\w*{}\s,$]+\s*from\s*|\bimport\s*\(\s*)["']([^"']+)["']/g
const HTML_SINKS = [
  ["v-html", /\bv-html\b/],
  ["innerHTML", /\binnerHTML\b/],
  ["outerHTML", /\bouterHTML\b/],
  ["insertAdjacentHTML", /\binsertAdjacentHTML\b/],
  ["document.write", /\bdocument\s*\.\s*write(ln)?\b/],
  ["new Function", /\bnew\s+Function\b/],
  ["eval", /(?<![.\w])eval\s*\(/],
  ["setHTML", /\bsetHTML(Unsafe)?\b/],
  ["parseHTMLUnsafe", /\bparseHTMLUnsafe\b/],
  ["createContextualFragment", /\bcreateContextualFragment\b/],
  ["srcdoc", /\bsrcdoc\b/],
]
const HTML_SINK_FILE = "MarkdownView.vue"
// XML namespace identifiers are not fetched.
const ALLOWED_URL = /^https?:\/\/www\.w3\.org\//
const ABSOLUTE_URL = /\bhttps?:\/\/[a-z0-9][^\s"'`)<>]*/gi
const PROTOCOL_RELATIVE = /(?:url\(\s*["']?|\b(?:src|href|action)\s*=\s*["'])\/\/[^\s"')]+/g

const packageOf = (specifier) => {
  const parts = specifier.split("/")
  return specifier.startsWith("@") ? parts.slice(0, 2).join("/") : parts[0]
}
const lineOf = (text, index) => text.slice(0, index).split("\n").length

if (existsSync(frontend)) {
  for (const file of walk(frontend)) {
    const rel = relative(root, file)
    const text = readFileSync(file, "utf8")
    const test = isTest(file)

    if (/\.(ts|vue|js|mjs)$/.test(file)) {
      for (const match of text.matchAll(IMPORT)) {
        const specifier = match[1]
        if (specifier.startsWith(".") || specifier.startsWith("/")) continue
        if (specifier.startsWith("node:")) {
          if (!test) errors.push(`${rel}:${lineOf(text, match.index)}: Node built-in "${specifier}" outside a test`)
          continue
        }
        const name = packageOf(specifier)
        if (!(name in runtime)) {
          errors.push(`${rel}:${lineOf(text, match.index)}: imports "${specifier}", but "${name}" is not a direct dependency`)
        } else if (IMPORTED_ONLY_BY[name] && IMPORTED_ONLY_BY[name] !== rel) {
          errors.push(`${rel}:${lineOf(text, match.index)}: imports "${specifier}", which only ${IMPORTED_ONLY_BY[name]} may import`)
        }
      }
    }

    if (basename(file) !== HTML_SINK_FILE) {
      for (const [label, pattern] of HTML_SINKS) {
        const match = pattern.exec(text)
        if (match) errors.push(`${rel}:${lineOf(text, match.index)}: "${label}" is only allowed in ${HTML_SINK_FILE}`)
      }
    }

    if (!test) {
      for (const match of text.matchAll(ABSOLUTE_URL)) {
        if (!ALLOWED_URL.test(match[0])) errors.push(`${rel}:${lineOf(text, match.index)}: third-party URL ${match[0]}`)
      }
      for (const match of text.matchAll(PROTOCOL_RELATIVE)) {
        errors.push(`${rel}:${lineOf(text, match.index)}: protocol-relative URL ${match[0]}`)
      }
    }
  }
}

if (errors.length > 0) {
  console.error(`Frontend policy check failed:\n${errors.map((e) => `  - ${e}`).join("\n")}`)
  process.exit(1)
}
console.log("Frontend policy check passed.")
