# Design

## Context

The look of the client lives in a small set of places: design tokens in `styles/tokens.css` (`@layer tokens`), shared component classes in `styles/base.css` (`.button`, `.chip`, `.segmented`, `.panel`, `.input`, `.icon-button`, `.menu__item`), and scoped styles in a handful of components (`SideNav`, `AppShell`, `KanbanColumn`, `TaskCard`, `TaskRow`, `TaskDetails`, `ProgressBar`, `UserAvatar`, `AnnouncementsPanel`) and pages. Constraints from the `web-client` and `security-baseline` specs apply unchanged: no new dependencies, fonts and icons served from the app origin (Rubik 400/500/700 woff2 files and an SVG sprite of Material Symbols), no runtime `<style>` injection.

The data the mockups rely on is mostly already in the client: `Column` has `color` (nullable) and `done`; the board snapshot has `active_sprint` with `starts_on`/`ends_on` and only the active sprint's tasks; `TaskDetail` has `status` and `subtasks`; statistics give projects, columns and deadlines. Labels and projects have no colour, and the shell knows neither the backlog size nor the member count.

The target look is the "A" frames on the design canvas (board, task page, backlog, dashboard). See proposal.md for scope and the delta spec for the behaviour added.

## Goals / Non-Goals

**Goals:**
- Reach the A look mostly by changing tokens and shared classes, so the screens that are not redesigned still match.
- Keep every new behaviour computable on the client from data already loaded.
- Make colour contrast checkable in CI instead of by eye.

**Non-Goals:**
- Pixel-matching the mockups. Where the mockup conflicts with existing behaviour (for example, an "Edit" button over the always-editable description, or a checkbox for "Important" where the app has a pressed toggle), the existing behaviour stays and only its styling changes.
- Restructuring routes, stores or the API.

## Decisions

### Tokens: repoint the existing names, add only what is missing
Change values of the existing tokens (`--color-text` → `#2A2233`, `--color-muted` → `#6B6478`, `--color-border` → `#E7E2EF`, `--color-background` → `#F6F4FA`, `--radius` → 8px, `--shadow` → a 1px hairline shadow) and add: `--color-primary` `#7C3FD0` / `--color-primary-hover` for primary buttons and progress fills, a `--color-nav-*` group for the sidebar (background `#2B1D3F`, raised `#35264D`, active `#4A3566`, text `#D9CEEA`, muted `#B7A9CC`, heading `#A898C0`), `--color-badge` / `--color-badge-text` for count badges, `--color-overdue` / `--color-overdue-bg`, and `--radius-card` (10px) and `--radius-lg` (14px). `--color-main` stays the brand purple for the logo and accents but is no longer used behind white text.
*Alternative:* a second, parallel token set for the new theme. Rejected: two sets drift, and nothing needs the old values.

### Contrast is tested from the token file
A `node --test` test reads `styles/tokens.css`, resolves the custom properties, and checks a list of foreground/background pairs with their minimum ratio (4.5 for text, 3 for markers and focus rings): primary button text, body and muted text on surface and background, sidebar text, muted and headings on the sidebar, badge text, chip tones, overdue text on its highlight, the "Important" colour on white. The WCAG relative-luminance formula lives in a small pure module next to the test. Values checked while designing: white on `#7C3FD0` 6.0:1, `#6B6478` on white 5.6:1, `#A898C0` on `#2B1D3F` 5.9:1, `#A3221B` on `#FCE4E4` 6.2:1, `#C4482F` on white 4.9:1.
*Alternative:* an axe-style check in system tests. Rejected as the primary gate: slower, and it only sees what a test happens to render.

### Derived colours: a tone index from the id
A pure helper maps an id to one of six tones (`id % 6`). Labels use tone classes (`[data-tone="1"]` … `"6"`) that set a pale background and a dark text colour from tokens (purple, blue, amber, green, rose, teal); projects use the same index for a solid, decorative marker. Using the id keeps the colour stable across renames, sessions and members, and sequential ids spread neighbouring labels over different tones. Tones are set through a data attribute and CSS, not inline styles.
*Alternatives:* hashing the title (changes on rename); storing a colour per label and project (needs an API and migration — a later feature can add a colour picker and fall back to the derived tone).

### Column status dots
A column's dot uses `column.color` when it is a valid `#rgb`/`#rrggbb` value (anything else is ignored, since the field may hold legacy data), otherwise the success colour for the done column and the derived tone for others. The dot is decorative; the column title carries the meaning.

### Sprint summary is a pure function of the board snapshot
`sprintSummary(sprint, columns, tasks, today)` returns `{ done, total, daysLeft, state }`, where `state` is `running`, `last-day` or `ended`. `total` is the number of tasks on the board and `done` the number in done columns, which matches what the board shows because the board already holds only the active sprint's tasks. Days are counted between calendar dates: `ends_on` (a `YYYY-MM-DD` string) and the browser's local date are both converted to UTC day numbers, so DST changes cannot shift the count, and "today" agrees with the relative deadlines on the cards. The date range uses `Intl.DateTimeFormat#formatRange`. New strings go into `en` and `ru` with plural forms (`{count} days left`, «осталось {count} дня», etc.), and the key-parity test covers them.

### "New task" opens the first column's field
`KanbanColumn` exposes its existing `startAdding()` through `defineExpose`; `BoardPage` keeps template refs to the columns and calls the first one's. The add field, submit and Escape behaviour stay exactly as they are. The button is rendered only in the kanban layout and only when there is at least one column.
*Alternative:* a "new task" dialog with a column picker. Rejected: a second creation path to maintain, for no gain on the common case.

### Project switcher reuses `AppMenu`
The switcher is an `AppMenu` trigger showing the project's initial, title and short name; items are `RouterLink`s to each project's board with `aria-current="page"` on the open one, a separator, and "New project". The sidebar's own project list stays, as in the mockup, for one-click access on wide screens. Without an open project, the trigger reads "Choose a project" and the project sections are hidden, as they are today.

### Breadcrumb in the shell header, date in the dashboard
On project routes the header shows `project title / section` (and `/ task key` on task pages), built from the route name and a section map shared with `SideNav` (moved to a small module so both use one list). Other routes show no breadcrumb. The dashboard's date line lives in the dashboard page header, not in the shell. The user menu trigger adds the first name and a chevron next to the avatar.

### Fonts and icons stay as they are
The mockups use Rubik 600; headings use 500 and the logo 700, the weights already self-hosted. Icons come from the existing sprite (`expand_more` for the switcher, `chevron_right` for "Open board", `sprint`, `calendar_today`, `local_fire_department_filled`, `attach_file`, `edit`); the announcements banner drops the mockup's bell rather than adding a symbol.
*Alternative:* add Rubik 600 files. Rejected: more bytes for a barely visible difference.

### Shared rows restyle once
`TaskRow` is used by the board list layout, backlog, archive and milestone pages, so its new look (full-width row in a bordered list, dashed placeholder for unassigned, overdue highlight) reaches all four. The backlog's "Put on board" trigger becomes a labelled secondary button ("To board"), keeping its existing accessible name.

## Risks / Trade-offs

- [System tests select by changed markup or text (shell, board header chip, dashboard, accessibility)] → update each test in the same task as the screen it covers, and run the full system suite before the change is marked done.
- [Six tones give collisions once a project has more than six labels] → acceptable for visual grouping; the title is always shown, and a colour picker can come later.
- [`column.color` may hold arbitrary legacy strings] → only hex colours are used; everything else falls back.
- [Restyling `.button`, `.chip` and `.panel` changes screens that are not redesigned] → a review pass over projects, sprints, milestones, members, settings and archive pages, in English and Russian (longer Russian labels wrap in headers and badges).
- [`formatRange` output differs between browsers] → tests assert the presence of both dates, not the exact string.

## Migration Plan

Front-end only: ship as one deploy. No data or API migration. Rollback is reverting the change; no stored state depends on it.

## Open Questions

- Should labels later get a user-chosen colour? Deferrable: the derived tone becomes the fallback and nothing in this design blocks it.
