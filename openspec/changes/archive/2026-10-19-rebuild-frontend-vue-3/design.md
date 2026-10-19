## Context

See proposal.md (Why). Facts that shape the approach:

- **Legacy code size:** the legacy SPA has 202 files and 15k lines. Import-graph analysis shows ~160 files / ~11k lines are reachable from the two entry points. Unreachable: the old categories/inbox app, the dashboard charts reached only through a styles-only import, and the `blocks/*` components.
- **Legacy usage that needs replacing:**
  - Vuetify is used in 40 files, almost all simple widgets: `v-btn` ×38, `v-icon` ×38, `v-list*`, `v-dialog` ×6, `v-menu` ×6, `v-tooltip` ×4, one `v-snackbar`.
  - Vuex is used in 65 files, 206 of them `mapGetters`/`mapActions` calls. All seven live modules are namespaced, and none reaches into another.
  - The router uses named routes, params, meta and query, three nested views and active-link slots. There are no guards.
- **Icons:** 43 distinct Material icon names are used.
- **Drag and drop:** handle-based in three places (kanban cards, kanban columns, list rows); only the `end` event is used.
- **Target versions** (resolved and OSV-scanned on 2026-10-01, 160 packages, 0 advisories): `vue` 3.5.43, `vue-router` 5.3.1, `pinia` 4.0.3, `@tiptap/*` 3.31.4, `@sentry/vue` 11.2.0, `vite` 8.3.2, `@vitejs/plugin-vue` 6.0.9, `typescript` 6.0.3, `vue-tsc` 3.3.11. Only `fsevents` (optional, macOS) has an install script.
- **Provided by `rebuild-backend-rails-8`:** the API, the production CSP, the `/app/*path` layout with `csrf_meta_tags`, `ViteHelper`, a placeholder entry, `bin/dev`, and Rubik fonts in `public/fonts/`.

## Goals / Non-Goals

**Goals:**
- Port every screen listed in spec `web-client` to Vue 3 + TypeScript, with only the allowed dependencies.
- Keep all HTML injection in one audited component, and run clean under the strict CSP.
- Provide guardrails in CI so the dependency and rendering rules stay true after this change.

**Non-Goals:**
- Visual redesign. Layout and styling stay close to the legacy look, rebuilt in plain CSS.
- Offline support, real-time collaboration, or conflict resolution for simultaneous description edits (last write wins).
- Porting unreachable legacy code, the dashboard charts, or the mood/inbox features.
- Server-side rendering.

## Decisions

### 1. Layout of `app/frontend/`
```
app/frontend/
  entrypoints/application.ts   createApp, pinia, router, sentry, mount
  api/        client.ts (fetch wrapper) + one module per resource; types.ts mirrors API JSON
  router/     routes.ts (manual route table), index.ts
  stores/     ui, me, projects, board, backlog, sprints, milestones, labels, archive,
              announcements, statistics   (Pinia setup stores)
  editor/     extensions.ts (single tiptap extension list), markdown.ts (parse/render helpers)
  composables/ useDragSort.ts, useMediaQuery.ts, useAutosave.ts
  components/ ui/ (AppDialog, AppMenu, AppToast, AppIcon, form controls), MarkdownView.vue,
              DescriptionEditor.vue, board/, task/, project/, ...
  pages/      one component per route
  i18n/       en.ts, ru.ts (typed keys), format.ts (Intl helpers)
  styles/     layers.css, tokens.css, base.css, utilities.css
  assets/     icons.svg (sprite)
```
Components are ported page by page from `legacy/app/javascript`. Each script becomes `<script setup lang="ts">`; the Vuex and Vuetify removals force rewriting the script and template anyway.

### 2. Toolchain: Vite 8, TypeScript 6.0, npm with exact pins
- **Vite and TypeScript config:** Vite with `@vitejs/plugin-vue`; `build.manifest: true`, `outDir: public/vite`, `base: /vite/`, the default build target (`baseline-widely-available`). `tsconfig.json` uses `strict`, `noUncheckedIndexedAccess`, `verbatimModuleSyntax` and `erasableSyntaxOnly`; the last one lets Node run `.ts` tests directly.
- **TypeScript stays on 6.0.x.** TypeScript 7.0 (the native compiler) has no stable programmatic API yet, and `vue-tsc` relies on it. We move to TypeScript 7.x once `vue-tsc` officially supports it; the TypeScript team targets that API for 7.1.
- **npm instead of yarn 1.** `.npmrc` sets `save-exact=true` and `ignore-scripts=true`; CI runs `npm ci --ignore-scripts` and `npm audit signatures`. Dependabot gets a 7-day `cooldown`, so freshly published (possibly compromised) releases aren't picked up immediately.
- **Development:** the app is opened on the Vite dev server, which proxies every path outside `/vite/` to Rails, so the page and the SVG sprite share an origin (`<use>` refuses cross-origin files). The stylesheets Vite injects carry a per-request `style-src` nonce, allowed in development only (spec `security-baseline`).
- *Alternative considered:* no build step (vendored Vue ESM build plus an import map). Rejected: templates would compile in the browser via `new Function`, which forces `'unsafe-eval'` into the CSP, and we'd lose single-file components and template type checking.

### 3. API client: a typed `fetch` wrapper
- **The wrapper** (`client.ts`, about 60 lines) handles:
  - the `X-CSRF-Token` header read from `<meta name="csrf-token">`, plus `Accept`/`Content-Type: application/json` and `credentials: 'same-origin'`;
  - a default `AbortSignal.timeout(15000)`;
  - parsing the backend's error envelope into an `ApiError` (status, code, field errors).
- **401 handling:** a 401 triggers a full navigation to the current `/app/...` URL. The server-side authentication filter stores that location and redirects to sign-in, then returns the user there afterwards. This avoids a client-built `return_to` parameter and the open-redirect validation it would need.
- **Resource modules:** each returns typed promises. `types.ts` is hand-written next to the backend serializers, which is cheap at this API size.
- *Alternatives considered:* axios (removed, 24 advisories in the old version) and OpenAPI code generation (extra tooling for one client).

### 4. Pinia setup stores replacing Vuex modules
- **Module mapping:** each Vuex module becomes a setup store (`ref`/`computed`/functions); mutations disappear. The 628-line `team` module is split into `projects` (list, current project, members) and `board` (columns, tasks, counts).
- **Components:** they use `storeToRefs(useXStore())` for state and call actions directly.
- **Loader:** the root store's DOM-poking loader becomes `ui.loading`, which the shell renders.

### 5. vue-router 5 with a manual route table
File-based routing, now bundled in vue-router 5, isn't enabled; the existing route list maps one-to-one. The routes live under `createWebHistory('/app/')`:

```
/                               dashboard (own or ?user= teammate)
/projects                       list          /projects/new        create
/projects/:pid/board            kanban        /projects/:pid/list  list layout
/projects/:pid/backlog          /projects/:pid/sprints              /projects/:pid/milestones[/:mid]
/projects/:pid/members          /projects/:pid/settings (owner)     /projects/:pid/archive[/:tid]
/projects/:pid/tasks/:ref       ref = KEY-N or N
/settings/profile               /settings/security
/:pathMatch(.*)*                not found
```

Routes are lazy-loaded per page. Scroll behaviour restores the saved position on back/forward and scrolls to the top otherwise.

### 6. Replacing Vuetify with platform features and ~6 small components
| Legacy | Replacement |
|---|---|
| `v-dialog` | `AppDialog`: `<dialog>` + `showModal()` (focus containment, Esc, `::backdrop`, inert page); focus is returned to the opener on close |
| `v-menu`, `v-tooltip` | `AppMenu`: `popover` attribute + `popovertarget`; positioned with CSS anchor positioning where supported, otherwise with a `getBoundingClientRect` fallback on the `toggle` event |
| `v-snackbar` | `AppToast`: `popover="manual"` + `aria-live="polite"` |
| `v-icon`, Material Icons font | `AppIcon`: `<svg><use href="/vite/…/icons.svg#name">` from a sprite of the 43 used Material Symbols (Apache-2.0, files copied, no package) |
| `v-btn`, `v-list*`, `v-card`, `v-layout/flex/spacer`, `v-toolbar` | Semantic HTML (`button`, `ul/li`, `article`, `header`) + CSS classes |
| `v-text-field`, `v-textarea` | Native inputs; textarea autosize via `field-sizing: content`, with an `input`-event fallback |
| `v-navigation-drawer` | CSS grid layout; on narrow screens the sidebar is an `AppDialog` |
| `$vuetify.breakpoint` | CSS media/container queries; `useMediaQuery` (~15 lines) only where logic needs it |
| flatpickr, vue-multiselect | `<input type="date">`/`datetime-local`; a date range is two inputs linked through `min`/`max`; sprint multi-select is a checkbox list inside `AppMenu` |

### 7. Styling: plain CSS
- **Cascade layers:** `@layer reset, tokens, base, layout, components, utilities`. Design tokens are custom properties carried over from the legacy colours.
- **Component styles:** `<style scoped>` in single-file components, which Vite compiles into the CSS bundle, so nothing is injected at runtime. Native nesting, `:has()` and container queries (board columns) are used.
- **Fonts:** Rubik is self-hosted. The commercial Circe and Helvetica Neue Cyr files aren't carried over, since their licences are unverified.
- **Animations:** animate.css is replaced by a few `@keyframes`, `@starting-style` (progressive) and View Transitions for board moves (progressive).

### 8. i18n and formatting without libraries
The legacy `en`/`ru` dictionaries are ported to typed TypeScript objects, so `t('task.description')` is checked by `vue-tsc`. `format.ts` wraps the `Intl` APIs:
- `Intl.DateTimeFormat(lang)` for dates;
- `Intl.RelativeTimeFormat(lang, { numeric: 'auto' })` for yesterday/today/tomorrow;
- `Intl.PluralRules(lang)` with per-language word forms for counts.

The language comes from `GET /api/me`. This also fixes the legacy bug of formatting Russian strings with an English locale.

### 9. Markdown pipeline: tiptap everywhere; marked is never imported directly
- **One extension list** (`editor/extensions.ts`) is used by the editor and the renderer:
  - StarterKit, with headings 1–3, `link` restricted to `http`/`https`/`mailto` with `rel="noopener noreferrer nofollow"` and `target="_blank"`, and **underline disabled** because Markdown has no underline syntax;
  - TaskList/TaskItem from `@tiptap/extension-list`;
  - Placeholder from `@tiptap/extensions`;
  - `Markdown` from `@tiptap/markdown`.
- **Editor** (`DescriptionEditor.vue`):
  - created with `injectCSS: false` (its CSS ships in the bundle, which keeps the strict CSP);
  - loads content with `setContent(md, { contentType: 'markdown' })` and saves with `getMarkdown()` through `useAutosave` (on blur, and after 1 s without typing);
  - a ~20-line `handlePaste` turns `text/plain` clipboard content without `text/html` into editor content through the Markdown parser. `@tiptap/markdown` has no paste handling of its own.
- **Renderer** (`MarkdownView.vue`):
  - `new MarkdownManager({ extensions }).parse(md)` → JSON → `generateHTML(json, extensions)` from `@tiptap/core`, cached per content string;
  - a raw HTML token in the Markdown is parsed through the extensions' `parseHTML` rules, so only supported nodes survive and unrecognised markup becomes text;
  - the Link extension validates URLs both when parsing and when rendering;
  - output is injected through a single directive that uses `Element.prototype.setHTML` (Sanitizer API) when the browser has it, and `innerHTML` otherwise;
  - this component is the only HTML sink in the client.
- **Unsupported constructs:** marked's tokens can include `image` and `table`, which have no node in our list.
  - A small `PlainTextFallback` extension handles them through `@tiptap/markdown`'s per-extension token parse hooks and emits plain text (alt text, cell text). tiptap only uses marked's token stream, so marked renderer overrides wouldn't apply.
  - If the hook proves insufficient, the fallback rewrites those tokens to text after `marked.lexer` and before `MarkdownManager` converts them.
  - Tests covering the spec scenarios lock this in.
- **Comments** use a plain `<textarea>`; their Markdown goes through `MarkdownView`. Bare URLs become links through marked's GFM autolinks, then the Link extension.
- **Why not call marked directly:** it is already a transitive dependency of `@tiptap/markdown`, at a version tiptap controls. Rendering through the tiptap schema keeps display identical to editing, and makes the schema act as the HTML allowlist.

### 10. Native drag and drop: `useDragSort`
Each container registers itself with `useDragSort({ group, axis, items, onMove })`. The groups are `column`, `card` and `row`.

```
handle [draggable=true]
  dragstart --> dragState = { group, id, fromContainer, fromIndex }   (module-level ref)
            --> dataTransfer.setData('application/x-goalner-' + group, id)
            --> dataTransfer.setDragImage(wholeItemEl, offsetX, offsetY)
container
  dragover  --> accept (preventDefault) only if dragState?.group === group
            --> target index from child midpoints, at most once per animation frame
            --> reactive { toContainer, toIndex }; Vue renders the drop indicator
            --> within 48px of a horizontal scroll edge: scrollBy (board columns)
  drop      --> preventDefault; if dragState is null, ignore (foreign drop)
            --> optimistic store update inside startViewTransition (if available)
            --> onMove(...) --> API; on failure, roll back and show a toast
source
  dragend   --> clear dragState and indicator (also covers Esc and drops outside)
document
  dragover/drop with no app drag --> preventDefault, so foreign drops never navigate
```

- **The DOM is never moved directly;** Vue renders the result of the reactive state.
- **Keyboard support:** handlers on focused cards, rows and column headers implement Alt+Arrow moves through the same `onMove`, and announce through a shared `aria-live` region.
- **Touch:** `-webkit-touch-callout: none` and `user-select: none` on handles.
- **Drop-index math** is a pure function, unit-tested with `node --test`.
- *Alternative considered:* Pointer Events for full control on every browser. Rejected by product decision in favour of the native API. The cost is no drag on Firefox for Android; the status menu and keyboard moves cover that case.

### 11. Error reporting: `@sentry/vue` with personal data stripped
- **When and where:** `Sentry.init` runs only when `<meta name="sentry-dsn">` is present. The backend renders that tag in production from credentials, so one build serves every environment.
- **Settings:** `sendDefaultPii: false`, `attachProps: false`, no Replay or Feedback integrations, tracing off.
- **Scrubbing:** a `beforeSend` removes `request.data` and breadcrumbs carrying fetch bodies. The Pinia plugin is configured not to attach store state.
- **Identity:** the user is set by id only.

### 12. Testing and CI guardrails
- **Unit tests:** `node --test` on `.ts` files covering the API client (with `fetch` stubbed), `format.ts`, the i18n key parity between `en` and `ru`, drag-index math, and route resolution helpers. No test framework is added.
- **End-to-end:** Rails system tests (Capybara + headless Chrome) cover each spec scenario. Native drag-and-drop is driven by dispatching `DragEvent`s with a shared `DataTransfer` in a test helper, because WebDriver's HTML5 drag-and-drop simulation is unreliable. Keyboard moves are tested through real key presses. A dedicated test collects browser console logs and fails on any CSP violation.
- **Type checking:** `vue-tsc --noEmit` and `vite build` in CI.
- **CI guardrails** are a zero-dependency Node script, `script/check-frontend-policy.mjs`, which fails if:
  - `package.json` dependencies or devDependencies differ from the allowlist, or any version isn't exact;
  - any `app/frontend` file imports a package that isn't declared directly;
  - `v-html`, `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `document.write` or `new Function` appear outside `MarkdownView.vue`;
  - any URL with a third-party origin appears in `app/frontend` styles or templates.

## Risks / Trade-offs

- **[Native drag-and-drop differences between browsers]** (drag image, auto-scroll, events on child elements) → Container-level `dragover` only, explicit edge scrolling, manual checks on Chrome, Firefox and Safari desktop plus iOS Safari and Chrome Android before release.
- **[Firefox for Android has no native drag and drop]** → Status menu and keyboard moves; documented in the spec.
- **[`@tiptap/markdown` round-trip fidelity]** (spacing, nested lists, escaping) → Unit-style system tests save and reload fixtures for every supported construct; descriptions are short-form content.
- **[A tiptap update changes HTML parsing or link validation]** → Exact version pins, the Markdown security scenarios as regression tests, and the strict CSP as backstop.
- **[Sanitizer API absent in some browsers]** → Schema-bounded `generateHTML` output is the primary control; `setHTML` is defence in depth only.
- **[Two users editing one description]** → Last write wins (non-goal). Autosave keeps windows short.
- **[vue-tsc / TypeScript 7 timing]** → Stay on 6.0.x until `vue-tsc` supports 7.x; esbuild/oxc transpilation in Vite doesn't depend on it.
- **[Vuex-to-Pinia port mistakes in a 628-line module]** → The split into two stores is done first, with system tests on the board before other pages are ported.

## Migration Plan

- Implemented after `rebuild-backend-rails-8`; there is no user data to migrate.
- Port screens in dependency order (shell → projects → board → task → the rest).
- Delete `legacy/` once every screen in spec `web-client` has a passing system test.
- Rollback during development: tag `legacy-2021`.
