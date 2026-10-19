# Tasks

## 1. Tokens, shared styles and helpers

- [x] 1.1 Update `styles/tokens.css` to the A palette as listed in design.md (repointed text, muted, border, background, radius and shadow values; new `--color-primary*`, `--color-nav-*`, `--color-badge*`, `--color-overdue*`, `--radius-card`, `--radius-lg`, and six label tone pairs); verify `npm run build` succeeds and the app renders with the new background and text colours
- [x] 1.2 Add a pure WCAG contrast module and `styles/tokens.test.ts`, which reads `tokens.css` and checks every foreground/background pair listed in design.md against its minimum ratio; verify `npm test` passes, and fails when `--color-primary` is temporarily set to `#9859e8`
- [x] 1.3 Restyle the shared classes in `styles/base.css` (`.button` on `--color-primary`, `.button--secondary`, `.button--text`, `.icon-button`, `.chip` with `[data-tone]` variants, a `.badge` count style, `.segmented`, `.panel` with border and `--radius-lg`, `.input`, `.menu__item`), and `ProgressBar` fill on `--color-primary`; verify `bin/rails test test/system/ui_components_test.rb` passes and the components fixture page shows the new styles
- [x] 1.4 Add a pure helper that maps an id to a tone 1–6, and a column-dot helper (valid hex `column.color`, else success colour for the done column, else the derived tone), each with `node --test` unit tests (stable output, spread over consecutive ids, invalid colour strings rejected); verify `npm test` passes

## 2. Shell

- [x] 2.1 Move the project section list (route names, labels, icons) out of `SideNav` into a shared module, and restyle `SideNav` on the `--color-nav-*` tokens: solid background, logo, navigation, a "Projects" list with tone markers, "Write to us" in the footer; verify `bin/rails test test/system/app_shell_test.rb` passes after updating any selectors it relies on
- [x] 2.2 Add the project switcher to `SideNav` (an `AppMenu` with the user's projects, `aria-current="page"` on the open one, a separator and "New project"; "Choose a project" with no project sections when none is open) with `en`/`ru` strings; verify new system tests for the spec scenarios "Switch to another project", "Create a project from the switcher" and "No project open", including in the mobile drawer
- [x] 2.3 Add the header breadcrumb for project routes (project title / section / task key) in `AppShell`, and show the first name and a chevron in the `UserMenu` trigger; verify a system test that the task page header reads "<project> / Board / <key>" and that the user menu still opens and signs out
- [x] 2.4 Restyle `AnnouncementsPanel` as the tinted news banner with "Dismiss all"; verify `bin/rails test test/system/dashboard_test.rb` still passes its dismiss scenario

## 3. Board

- [x] 3.1 Implement the pure `sprintSummary(sprint, columns, tasks, today)` (done/total, days left from calendar dates, `running` / `last-day` / `ended`) and add `en`/`ru` strings with plural forms for days left; verify unit tests for 7 days left, last day, ended, a DST-crossing range and Russian forms (1, 3, 5 days), and that the i18n key-parity test passes
- [x] 3.2 Rebuild the `BoardPage` header: title, the sprint summary (title link to Sprints, date range via `formatRange`, progress bar, days left) only when a sprint is active, the layout switch, and the "New task" button calling the first column's exposed `startAdding()` (kanban layout with at least one column only); verify new system tests for "Sprint in progress", "No active sprint", "Add a task from the header" and "Cancel with Escape", and update `board_test.rb` where it checked the old sprint chip
- [x] 3.3 Restyle `KanbanColumn` (status dot, title, count badge, add and actions buttons, "Add task" footer button, no grey column background) and the "Add column" control; verify `bin/rails test test/system/board_test.rb test/system/board_drag_test.rb test/system/board_keyboard_test.rb` pass, including drop indicators and keyboard focus rings staying visible
- [x] 3.4 Restyle `TaskCard` (bordered surface with `--radius-card`, toned label chip, "Important" marker with text, overdue deadline highlight, subtask and comment counts, assignee avatar); verify the "Board screen" scenario test still finds key, title, label, assignee, deadline and importance on a card, and the contrast test covers the overdue and important colours
- [x] 3.5 Restyle `TaskRow` (full-width row in a bordered list, toned label, overdue highlight, dashed placeholder for unassigned) and `BoardList` group headers to match; verify `bin/rails test test/system/board_list_test.rb test/system/archive_test.rb` pass

## 4. Task page

- [x] 4.1 Restyle `TaskPage`: main content in a panel, header line with key, toned label chip and status chip (column dot and title), title with the edit button, section headings; verify `bin/rails test test/system/task_page_test.rb` passes after selector updates
- [x] 4.2 Add subtask progress to `SubtaskList` ("x of y done" and a progress bar, hidden without subtasks, updated on completion) and restyle the list as a bordered checklist with the inline "New subtask" field; verify system tests for "Partly done subtasks" and "Completing a subtask updates progress"
- [x] 4.3 Restyle comments (`CommentForm` with avatar, bordered composer, "Attach files", hint and primary "Post comment"; `CommentItem` with avatar, name, time, "edited", actions menu and attachment cards) and add the comment count badge to the section heading; verify `task_page_test.rb` comment and attachment scenarios and `markdown_test.rb` pass
- [x] 4.4 Restyle `TaskDetails` as the "Details" panel (label column plus full-width value buttons for status, assignee, label, milestone and sprint; the deadline input; the "Important" pressed toggle; creator line; "Archive task"); verify `task_page_test.rb` field-editing scenarios pass and every control is reachable by keyboard

## 5. Backlog

- [x] 5.1 Restyle `BacklogPage`: title with a task-count badge, intro text, the "New backlog task" form as one bordered bar with a primary "Create" button, the task list in one bordered panel, and the placement trigger as a labelled "To board" button with the column menu (accessible name unchanged); verify `bin/rails test test/system/board_list_test.rb` backlog round trip passes and a system test checks the button's visible text and accessible name

## 6. Dashboard

- [x] 6.1 Restyle `DashboardPage`: the current date above "My tasks", the "Show the tasks of" select, project cards with tone markers, open-task count and an "Open board" link, column groups side by side with task tiles and importance markers; verify `bin/rails test test/system/dashboard_test.rb` teammate-switch scenario passes
- [x] 6.2 Restyle the deadlines panel with date tiles (weekday and day number from `Intl`, today highlighted with "Today"), task key and project name, and title; verify a system test with a deadline due today and one later in the week, in English and Russian

## 7. Integration checks

- [ ] 7.1 Review the screens that are not redesigned (projects, new project, project settings, members, sprints, milestones, archive, profile and security settings, not-found) at 1440px and 390px wide, in English and Russian, and fix wrapping or contrast regressions; verify by screenshots attached to the PR
- [x] 7.2 Run the full frontend and system checks: `npm run policy`, `npm run typecheck`, `npm test`, `npm run build`, `bin/rails test test/system` (including `accessibility_test.rb` and the production-mode CSP test); verify all pass with no CSP violations and no new dependencies in `package.json`

## Workflow follow-up

- Run `/opsx:apply` to implement, then archive the change with `/opsx:archive` once it is reviewed and merged.
