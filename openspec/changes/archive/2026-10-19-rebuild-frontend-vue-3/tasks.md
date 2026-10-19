## 1. Toolchain and guardrails

- [x] 1.1 Replace the placeholder `package.json` with the exact-pinned allowlist (`vue` 3.5.x, `vue-router` 5.x, `pinia` 4.x, `@tiptap/vue-3`, `@tiptap/starter-kit`, `@tiptap/extension-list`, `@tiptap/extensions`, `@tiptap/pm`, `@tiptap/markdown`, `@tiptap/core` 3.x, `@sentry/vue` 11.x; dev: `vite` 8.x, `@vitejs/plugin-vue` 6.x, `typescript` 6.0.x, `vue-tsc` 3.x), add `.npmrc` (`save-exact=true`, `ignore-scripts=true`), and generate `package-lock.json`; verify `npm ci --ignore-scripts` succeeds and `npm audit signatures` passes
- [x] 1.2 Add `vite.config.ts` (manifest, `outDir: public/vite`, `base: /vite/`, dev server origin matching the backend CSP) and `tsconfig.json` (`strict`, `noUncheckedIndexedAccess`, `verbatimModuleSyntax`, `erasableSyntaxOnly`); verify `npx vite build` emits `public/vite/.vite/manifest.json` and `npx vue-tsc --noEmit` passes on the placeholder entry
- [x] 1.3 Write `script/check-frontend-policy.mjs` (dependency allowlist with exact versions, no undeclared package imports, no `v-html`/`innerHTML`/`outerHTML`/`insertAdjacentHTML`/`document.write`/`new Function` outside `MarkdownView.vue`, no third-party URLs in frontend sources) and add a `frontend` CI job running `npm ci --ignore-scripts`, `npm audit signatures`, the policy script, `vue-tsc --noEmit`, `node --test` and `vite build`; verify the job passes, and fails when `axios` is added or `import 'marked'` appears in a scratch commit
- [x] 1.4 Add the Dependabot npm `cooldown` (7 days) to `.github/dependabot.yml` and include `package-lock.json` in the osv-scanner step; verify the CI security job scans both lockfiles

## 2. Foundations

- [x] 2.1 Implement `api/client.ts` (CSRF header from meta, JSON, same-origin credentials, 15 s timeout, `ApiError` from the error envelope, 401 → full navigation to the current URL) and `api/types.ts` for every backend serializer; verify `node --test` unit tests with a stubbed `fetch` cover success, 401, 422 field errors, 429, 500 and timeout
- [x] 2.2 Port the `en`/`ru` dictionaries to typed TypeScript and implement `i18n/format.ts` (`DateTimeFormat`, `RelativeTimeFormat` with `numeric: 'auto'`, `PluralRules` word forms); verify unit tests for key parity between languages, «завтра», «3 задачи» and English equivalents
- [x] 2.3 Create the CSS foundation (`@layer` order, tokens from the legacy colours, base/reset, utilities replacing the `g-*` helpers, self-hosted Rubik `@font-face`) and the SVG sprite of the 43 used Material Symbols with `AppIcon`; verify a production build references no third-party origin and the icons render on a sample page
- [x] 2.4 Implement `AppDialog` (`<dialog>`/`showModal`, Esc, backdrop click, focus return), `AppMenu` (popover + anchor positioning with a `toggle`-event fallback), `AppToast` (`popover="manual"` + `aria-live`), form controls with autosize fallback, and `useMediaQuery`; verify system tests on a fixture page for Escape closing a dialog with focus returned, menu light-dismiss, and toast announcement
- [x] 2.5 Implement the router (manual route table under `/app/`, lazy pages, not-found route, scroll behaviour) and the app shell (sidebar/drawer, project navigation, `ui.loading`), plus `GET /api/me` bootstrap setting language and user; verify system tests for reloading a deep task URL, an unknown URL showing not-found, and the shell rendering in Russian for a `ru` user
- [x] 2.6 Initialise `@sentry/vue` only when `<meta name="sentry-dsn">` exists, with `sendDefaultPii: false`, `attachProps: false`, no Replay/Feedback, tracing off, a `beforeSend` scrubber and the Pinia plugin without state; verify a unit test of the scrubber on a sample event and a system test (production mode) that a thrown component error produces a captured event without titles, descriptions or emails

## 3. Stores

- [x] 3.1 Port the Vuex modules to Pinia setup stores (`ui`, `me`, `projects`, `board`, `backlog`, `sprints`, `milestones`, `labels`, `archive`, `announcements`, `statistics`), splitting legacy `team` into `projects` and `board`, all calling the typed API modules; verify `vue-tsc` passes and a system test loads a board through the stores

## 4. Markdown

- [x] 4.1 Create `editor/extensions.ts` (StarterKit with headings 1–3, underline disabled, Link limited to http/https/mailto with `noopener noreferrer nofollow` and `_blank`; TaskList/TaskItem; Placeholder; Markdown) and the `PlainTextFallback` handling `image` and `table` tokens; verify system tests for the markdown-content scenarios "Image syntax in a comment" and "Script link"
- [x] 4.2 Implement `MarkdownView.vue` (parse with `MarkdownManager`, `generateHTML`, per-content cache, `setHTML` when available and `innerHTML` otherwise) as the only HTML sink; verify a system test where a comment containing `<img src=x onerror=alert(1)><script>alert(2)</script>` creates no `img`/`script` element and triggers no dialog, and the policy script still passes
- [x] 4.3 Implement `DescriptionEditor.vue` (toolbar for every supported format, `injectCSS: false` with the editor CSS in the bundle, load via `setContent(..., { contentType: 'markdown' })`, save via `getMarkdown()` with `useAutosave` on blur and 1 s idle, task-list checkboxes, Markdown paste handler); verify system tests for "Format and save", "Toggle a checkbox" and "Paste a list", and a save/reload round-trip fixture for every supported construct

## 5. Board and drag and drop

- [x] 5.1 Implement `useDragSort` (in-memory drag state, custom MIME type per group, `setDragImage`, rAF-throttled index calculation as a pure function, drop indicator, edge auto-scroll, `dragend` cleanup, document-level guard against foreign drops) with unit tests for the index function; verify `node --test` passes for before/after/empty/last-position cases
- [x] 5.2 Build the kanban board page (columns in order, cards with key/title/label/assignee/deadline/importance, column add/rename/delete, card and column dragging with optimistic update, view transition and rollback toast) and a system-test helper that dispatches `DragEvent`s with a shared `DataTransfer`; verify system tests for "Move to another column", "Dragging outside the handle", "Move a column", "Network failure", "Drop a link from another tab" and "Escape during a drag"
- [x] 5.3 Implement keyboard moves (Alt+Up/Down/Left/Right on cards, rows and column headers) through the same move path with `aria-live` announcements; verify the system test "Move right by keyboard", including the announcement text
- [x] 5.4 Build the list layout (tasks grouped by column, row dragging between groups) and the backlog page (send to backlog, place onto a column); verify system tests for "Row to another group" and a backlog round trip
- [ ] 5.5 Apply touch styles to handles (`-webkit-touch-callout: none`, `user-select: none`) and run a manual check on iOS Safari, Chrome for Android and Firefox for Android (status-menu fallback); verify by recording the results in the PR description

## 6. Remaining screens

- [x] 6.1 Task page: title, Markdown description, column/status menu, assignee, deadline (`datetime-local`), importance, milestone, label, sprint (checkbox list), subtasks (add, complete), comments (Markdown textarea, attachments upload with client-side size/type pre-check, list via `MarkdownView`, edit/delete own), archive action; verify system tests for editing each field, posting a comment with an attachment, and archiving
- [x] 6.2 Projects list and creation (with field-level validation errors), project settings (owner only: rename, short name, archive), members and invitations (invite, pending list, revoke, owner removes member, leave project); verify system tests for "Validation error", "Owner-only settings", inviting, and leaving
- [x] 6.3 Sprints page (create with date inputs and activate/carry-over options, activate, archive with carry-over, per-column counts) and milestones pages (list with progress, single milestone, delete/recover); verify system tests for creating and activating a sprint and recovering a milestone
- [x] 6.4 Archive list and read-only archived task view (description and comments through `MarkdownView`); verify the system test "Archived task description"
- [x] 6.5 Dashboard (own or a teammate's open tasks by project and column, deadlines in 7 days, teammate switcher), announcements panel (Markdown, dismiss all) and feedback dialog; verify system tests for the teammate switch, dismissing announcements and sending feedback
- [x] 6.6 Settings: profile (name, language switch re-rendering the UI, contact links with `https` validation, avatar upload with preview) and security (change password with current password); verify system tests for each, including the language change taking effect without a manual reload

## 7. Hardening and cleanup

- [x] 7.1 Add a production-mode system test that signs in, opens a board, moves a card, edits a description and posts a comment while collecting browser logs, failing on any CSP violation or third-party request; verify it passes against the backend's production CSP
- [x] 7.2 Run an accessibility pass: keyboard-only walkthrough of every screen, accessible names on icon-only buttons, visible focus, dialog semantics; verify by a system test asserting that every `button` without visible text has `aria-label`, and by notes in the PR description
- [x] 7.3 Delete `legacy/` and any remaining references to it, and remove the `legacy-2021` mention from active docs (the tag itself stays); verify `git ls-files legacy` is empty and the full Rails test suite, system tests and frontend CI job pass
