# Proposal

## Why

The Vue 3 client was rebuilt with the legacy look intact: a purple gradient sidebar, low-contrast primary buttons (white on `#9859e8` is 4.3:1, below WCAG AA), shadow-only cards and a board header that shows little more than the project title. Design direction A ("Aubergine", explored on the design canvas https://claude.ai/artifact/3YSWYWV9i1Q4F4D1rGcWiZ) keeps Goalner's purple identity and Rubik, and gives the main screens a calmer, higher-contrast and more informative layout. It was chosen over three alternatives and worked out for the board, task page, backlog and dashboard.

## What Changes

- New design tokens: deep aubergine sidebar (`#2B1D3F`), a darker primary (`#7C3FD0`, 6:1 against white), darker body and muted text, lighter lavender background, 1px-bordered cards and panels with larger radii, and status colours for overdue, done and important. Shared components (`.button`, `.chip`, `.segmented`, `.panel`, `.input`, `.icon-button`, `ProgressBar`) take the new look, so every screen inherits it.
- Shell: solid sidebar with a **project switcher** (a menu listing the user's projects and "New project") in place of the plain project heading, restyled navigation and project list with colour markers, and a header with a breadcrumb for project screens and the user's first name next to the avatar.
- Board: page header with the active **sprint summary** (title linking to Sprints, date range, a done/total progress bar for the tasks on the board, days left) and a **"New task"** button that opens the add-task field of the first column; columns get a status dot and a count badge; cards get bordered surfaces, coloured label chips, an "Important" marker and a highlighted overdue deadline. The list layout uses the restyled rows.
- Task page: main content in a card with a status chip and label next to the key, a subtask progress bar ("3 of 5 done"), a comment count, and a "Details" panel with full-width value buttons.
- Backlog: one bordered list with full-row layout, a dashed placeholder for unassigned tasks and a labelled "To board" menu button instead of the icon-only one.
- Dashboard: the current date, project cards with colour markers and column groups side by side, an "Open board" link per project, and deadline entries with date tiles (today highlighted). The announcements panel is restyled.
- Labels and projects get stable colours derived from their id (no API change), so the same label looks the same on every screen and for every member.
- Other screens (projects, sprints, milestones, members, settings, archive) are not redesigned; they inherit the tokens and shared components and are checked for regressions.

Not included: dark mode, new font files (the self-hosted Rubik 400/500/700 is reused), new runtime or development dependencies, API or backend changes, and the mockup's backlog-count badge and member count in the sidebar (the shell does not have that data).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `web-client`: adds the board's sprint summary and "New task" action, the project switcher, subtask progress on the task page, and stable label and project colours; extends the accessibility baseline with colour-contrast requirements.

## Impact

- Code: `app/frontend/styles/` (`tokens.css`, `base.css`), `components/shell/` (`AppShell`, `SideNav`, `UserMenu`, `AnnouncementsPanel`), `components/board/` (`KanbanColumn`, `TaskCard`, `TaskRow`, `BoardList`), `components/task/` (`TaskDetails`, `SubtaskList`, `CommentForm`, `CommentItem`), `components/ProgressBar.vue`, `components/UserAvatar.vue`, pages `BoardPage`, `TaskPage`, `BacklogPage`, `DashboardPage`, and `i18n/en.ts` / `i18n/ru.ts` for new strings. New pure helpers for derived colours and sprint dates, with unit tests.
- Tests: existing system tests that rely on changed markup (shell, board, task page, dashboard, accessibility) need updates; new system tests cover the sprint summary, "New task" and the project switcher.
- No API, database, dependency or CSP changes. Fonts and icons stay self-hosted; any new icons are added to the existing SVG sprite.
