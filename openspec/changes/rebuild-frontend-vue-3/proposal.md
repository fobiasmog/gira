## Why

The SPA is built on Vue 2.6 (end-of-life since December 2023), Vuetify 1.5, Vuex 3 and a Webpacker 4 / webpack 4 / Babel toolchain. Its `yarn.lock` holds 1,135 packages, of which 101 have known advisories (255 distinct, 16 critical); the browser bundle itself ships vulnerable axios, qs, moment and lodash versions and a Vue template compiler with an unfixable XSS advisory. User-generated comments are injected through `v-html`, and fonts, icons and analytics load from third-party origins, which rules out a strict Content Security Policy. The backend rebuild (`rebuild-backend-rails-8`) replaces the API, so the client has to be rebuilt anyway; this is the moment to cut it down to a minimal, auditable dependency set built on modern browser features.

## What Changes

- **BREAKING** Replace `legacy/app/javascript` (Vue 2, ~11k reachable lines plus ~3.5k unreachable) with a TypeScript Vue 3 SPA in `app/frontend/`, ported screen by screen against the new API. Unreachable legacy code (old categories/inbox app, dashboard charts) is not ported.
- **BREAKING** Directly declared runtime dependencies are limited to `vue`, `vue-router`, `pinia`, `@tiptap/*` (including `@tiptap/markdown`) and `@sentry/vue`; development dependencies to `vite`, `@vitejs/plugin-vue`, `typescript` (6.0.x) and `vue-tsc`. CI enforces this allowlist.
- Removed: Vuetify, Vuex, axios, qs, moment, lodash, chart.js, vue-chartjs, numeralize-ru, flatpickr, vue-flatpickr-component, vue-multiselect, vuedraggable/SortableJS, linkifyjs (direct), stylus, Babel, PostCSS plugins, Webpacker, webpack CLI/dev server, vue-loader, vue-template-compiler, yarn.
- Replaced with platform features: `fetch`, `Intl` (dates, relative days, plurals), native `<dialog>`, the Popover API, native date/time inputs, native HTML Drag and Drop, CSS nesting/layers/container queries, a self-hosted SVG icon sprite and self-hosted fonts.
- Markdown everywhere: task descriptions are edited in a WYSIWYG editor that reads and writes Markdown; comments are written as Markdown; descriptions, comments, archived tasks and announcements are displayed through one renderer that shares the editor's feature set, and is the only place that injects HTML.
- Board drag and drop on the native HTML Drag and Drop API with a keyboard alternative, replacing vuedraggable.
- Client works under the backend's strict CSP (no inline script/style injection, no eval, no third-party origins except the error-tracking ingest host); error reporting strips personal data.
- Unit tests for pure modules with Node's built-in test runner; end-to-end coverage through Rails system tests; `vue-tsc` type checking in CI.
- `legacy/` is deleted when the port is complete.

## Capabilities

### New Capabilities
- `web-client`: the signed-in single-page application — screens and navigation, language and formatting, error handling, safe rendering rules, CSP compatibility, accessibility and browser support, and the dependency policy.
- `board-drag-and-drop`: moving cards, columns and list rows by drag and drop and by keyboard, with persistence, cancellation and rejection of foreign drops.
- `markdown-content`: editing task descriptions and comments as Markdown and displaying Markdown content safely and consistently.

### Modified Capabilities
<!-- None: the capabilities introduced by rebuild-backend-rails-8 are not archived yet; this change adds client-side capabilities alongside them. -->

## Impact

- Depends on `rebuild-backend-rails-8` (API, CSP, `/app` hosting, `ViteHelper`, Rubik font in `public/fonts/`) being implemented first.
- Code: new `app/frontend/`, `package.json`/`package-lock.json`, `vite.config.ts`, `tsconfig.json`; deletion of `legacy/`.
- Dependencies: 1,135 locked npm packages (101 vulnerable) → ~160 locked packages with 0 known advisories at planning time (2026-10-01), of which only Vue, vue-router, Pinia, tiptap/ProseMirror and Sentry code reaches the browser.
- Browser support: latest two versions of Chrome, Edge, Firefox and Safari (desktop and iOS) and Chrome for Android. Firefox for Android lacks native drag and drop; there, tasks are moved through the status menu and keyboard shortcuts.
