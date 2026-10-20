# web-client Specification

## Purpose

Defines the signed-in single-page application: which screens exist and how they are reached, how it talks to the API and handles errors, how it renders user content safely under a strict Content Security Policy, and which browsers and dependencies it relies on.

## Requirements

### Requirement: Application shell and navigation
The client SHALL be served under `/app` to signed-in users and SHALL support deep links: reloading or opening any client URL SHALL show the same screen. Navigation between screens SHALL not reload the page. Unknown client URLs SHALL show a not-found screen with a link to the project list.

#### Scenario: Reload a task URL
- **WHEN** a signed-in user reloads `/app/projects/7/tasks/GOAL-12`
- **THEN** the task screen for GOAL-12 is shown

#### Scenario: Unknown URL
- **WHEN** a signed-in user opens `/app/does-not-exist`
- **THEN** a not-found screen is shown with a link to the project list

### Requirement: Screens
The client SHALL provide screens for: a personal dashboard (own or a teammate's open tasks and upcoming deadlines); the project list and project creation; a project's board in kanban and list layouts; backlog; task details; sprints; milestones and a single milestone; members and invitations; project settings (owner only); the project archive and an archived task; profile settings (name, language, contact links, avatar, password); announcements; and feedback.

#### Scenario: Board screen
- **WHEN** a member opens a project's board
- **THEN** the project's columns are shown in order with their tasks, each card showing key, title, label, assignee avatar, deadline and importance

#### Scenario: Owner-only settings
- **WHEN** a non-owner member opens the project
- **THEN** no project settings entry is offered

### Requirement: Language and formatting
The client SHALL display all interface text in the signed-in user's language (`en` or `ru`), and SHALL format dates, relative days (yesterday/today/tomorrow) and counted nouns according to that language's rules.

#### Scenario: Russian relative day
- **WHEN** a Russian-language user views a task due tomorrow
- **THEN** the deadline reads «завтра»

#### Scenario: Russian plural
- **WHEN** a Russian-language user views a column with 3 tasks
- **THEN** the count reads «3 задачи»

### Requirement: API communication and errors
Every state-changing request SHALL carry the CSRF token from the page. When the API answers 401, the client SHALL send the user to sign-in and return them to the same URL afterwards. Validation errors (422) SHALL be shown next to the related fields. Rate-limit (429) and unexpected (5xx or network) errors SHALL be shown as a short, generic message; the client SHALL NOT display raw error payloads.

#### Scenario: Session expired
- **WHEN** a user's session expires and they save a task
- **THEN** they are taken to sign-in and, after signing in, return to the task URL

#### Scenario: Validation error
- **WHEN** the API rejects a project with an invalid short name
- **THEN** the message is shown under the short-name field and the form keeps the user's input

### Requirement: Safe rendering of user content
User-supplied text (titles, names, labels, comments, descriptions, announcements, file names) SHALL be rendered as text, except Markdown content rendered through the Markdown renderer defined in `markdown-content`. No other part of the client SHALL inject HTML strings into the page.

#### Scenario: Script in a task title
- **WHEN** a task title is `<img src=x onerror=alert(1)>`
- **THEN** the title is displayed literally as text and no script runs

### Requirement: Strict CSP compatibility
The client SHALL run without Content Security Policy violations under the production policy defined in `security-baseline`: no inline scripts, no `<style>` elements injected at runtime, no `eval` or `new Function`, and no requests to third-party origins other than the error-tracking ingest host. Fonts and icons SHALL be served from the application's origin.

#### Scenario: No violations during use
- **WHEN** a user signs in, opens a board, edits a description and posts a comment in a production build
- **THEN** the browser reports no CSP violations

### Requirement: Privacy-preserving error reporting
In production the client SHALL report unexpected errors to the configured error tracker without component props, store contents, request or response bodies, session replays, or user data beyond the internal user id.

#### Scenario: Error in a component
- **WHEN** a component throws while showing a task
- **THEN** the error report contains the stack trace and the user id, and no task title, description, comment or email

### Requirement: Accessibility baseline
All interactive controls SHALL be operable by keyboard with a visible focus indicator; icon-only buttons SHALL have accessible names; dialogs SHALL be modal (focus contained, background inert) and close with Escape, returning focus to the control that opened them.

#### Scenario: Close a dialog with Escape
- **WHEN** a keyboard user opens the "new sprint" dialog and presses Escape
- **THEN** the dialog closes and focus returns to the "new sprint" button

### Requirement: Supported browsers
The client SHALL fully work in the latest two major versions of Chrome, Edge, Firefox and Safari (desktop and iOS) and in Chrome for Android. Features newer than that baseline SHALL only enhance behaviour and SHALL NOT be required for any task to be completed.

#### Scenario: Missing progressive feature
- **WHEN** a supported browser lacks view transitions
- **THEN** board moves still work, only without the animation

### Requirement: Dependency policy
The client's directly declared runtime dependencies SHALL be exactly `vue`, `vue-router`, `pinia`, `@sentry/vue` and `@tiptap/*` packages, and its development dependencies exactly `vite`, `@vitejs/plugin-vue`, `typescript` and `vue-tsc`, at exact versions with a committed lockfile. Packages SHALL be installed without running install scripts. Client code SHALL NOT import packages that are not declared directly. CI SHALL fail when any of these rules is broken.

#### Scenario: Unapproved dependency added
- **WHEN** a change adds `axios` to `package.json`
- **THEN** the CI dependency-policy check fails and names the package

#### Scenario: Importing a transitive package
- **WHEN** client code imports `marked`, which is only present as a transitive dependency
- **THEN** the CI check fails

### Requirement: Board sprint summary
When the project has an active sprint, the board SHALL show above its columns the sprint's title as a link to the sprints screen, its start and end dates, how many of the tasks on the board are in the done column out of all tasks on the board (as text and as a progress bar), and how many days remain until the end date. Without an active sprint, no sprint summary SHALL be shown.

#### Scenario: Sprint in progress
- **WHEN** today is 19 October, the active sprint "Sprint 14" runs from 13 to 26 October, and the board holds 12 tasks of which 3 are in the done column
- **THEN** the board shows "Sprint 14" linking to the sprints screen, the dates 13–26 October, "3 of 12 done" with a progress bar at 25%, and "7 days left"

#### Scenario: Last day of the sprint
- **WHEN** today is the active sprint's end date
- **THEN** the summary says it is the sprint's last day instead of a number of days

#### Scenario: Sprint past its end date
- **WHEN** the active sprint's end date is before today
- **THEN** the summary says the sprint has ended

#### Scenario: Russian day count
- **WHEN** a Russian-language user views a board whose active sprint ends in 3 days
- **THEN** the remaining time reads «осталось 3 дня»

#### Scenario: No active sprint
- **WHEN** a member opens the board of a project without an active sprint
- **THEN** no sprint summary is shown and the columns are shown as before

### Requirement: New task from the board header
The board in kanban layout SHALL offer a "New task" action next to the layout switch. Activating it SHALL open the add-task field of the first column and move keyboard focus into it; the task is created there as with the column's own add action. When the board has no columns, the action SHALL NOT be offered.

#### Scenario: Add a task from the header
- **WHEN** a member activates "New task" on a board whose first column is "To do"
- **THEN** the add-task field of "To do" opens with keyboard focus in it, and submitting a title creates the task in "To do"

#### Scenario: Cancel with Escape
- **WHEN** the member presses Escape in that field without typing
- **THEN** the field closes and no task is created

### Requirement: Project switcher
The navigation SHALL show the open project's title and short name as a control that opens a menu listing all of the user's projects, with the open one marked as current, followed by an entry for creating a new project. Choosing a project SHALL open its board. When no project is open, the control SHALL invite the user to choose a project, and project sections SHALL NOT be listed.

#### Scenario: Switch to another project
- **WHEN** a member viewing "Website relaunch" opens the project switcher and chooses "Mobile app"
- **THEN** the board of "Mobile app" is shown and the switcher shows "Mobile app"

#### Scenario: Create a project from the switcher
- **WHEN** a user opens the project switcher and chooses the new-project entry
- **THEN** the project creation screen is shown

#### Scenario: No project open
- **WHEN** a user opens the dashboard without having opened a project in this page load
- **THEN** the switcher invites them to choose a project and no Board, Backlog or other project section links are shown

### Requirement: Subtask progress on the task page
The task page SHALL show, for a task that has subtasks, how many of them are done out of the total, as text and as a progress bar. A task without subtasks SHALL show no progress bar.

#### Scenario: Partly done subtasks
- **WHEN** a member opens a task with 5 subtasks of which 3 are complete
- **THEN** the subtasks section shows "3 of 5 done" and a progress bar at 60%

#### Scenario: Completing a subtask updates progress
- **WHEN** the member marks a fourth subtask complete
- **THEN** the section shows "4 of 5 done" without a page reload

### Requirement: Stable label and project colours
Every label and every project SHALL be shown with a colour that depends only on its identity, so that it is the same on every screen, for every member and across sessions. A colour SHALL never be the only way to identify a label or project: its title SHALL always be shown next to it.

#### Scenario: Same label everywhere
- **WHEN** a task with the label "Design" is shown as a board card, as a backlog row and on its task page
- **THEN** the label chip has the same colours in all three places

#### Scenario: Same colour for every member
- **WHEN** two members of a project open its board on different devices
- **THEN** each label and the project marker are shown in the same colours for both

### Requirement: Colour contrast
Text SHALL have a contrast ratio of at least 4.5:1 against its background, or at least 3:1 for large text (24px, or 18.66px bold, and larger). Focus indicators, the boundaries needed to identify a control, and markers that carry meaning on their own (overdue deadline, importance, done) SHALL have a contrast ratio of at least 3:1 against adjacent colours.

#### Scenario: Primary button label
- **WHEN** a primary button such as "New task" is shown
- **THEN** its label has a contrast ratio of at least 4.5:1 against the button colour

#### Scenario: Navigation text
- **WHEN** the navigation shows an inactive link and a section heading on the sidebar background
- **THEN** both have a contrast ratio of at least 4.5:1 against it

#### Scenario: Overdue deadline
- **WHEN** a card shows a deadline that has passed
- **THEN** the deadline text has a contrast ratio of at least 4.5:1 against its highlight, and the highlight is not the only sign of being overdue because the relative day ("yesterday", a past date) is shown as text

### Requirement: Collapsible sidebar
On wide screens, the sidebar SHALL offer a control that collapses it to a narrow rail of icons, and from the rail a control that expands it again. The rail SHALL keep the logo, the project switcher (as the open project's initial), Dashboard, the open project's sections and "Write to us". Each of these SHALL keep its accessible name and SHALL show its label as a tooltip. The rail SHALL still mark the active section. The project list SHALL NOT be shown in the rail. The content area SHALL take the width the sidebar gives up. The choice SHALL be remembered in the browser across reloads. When browser storage is unavailable, the sidebar SHALL start expanded. The narrow-screen navigation SHALL always show the full sidebar and SHALL NOT offer the collapse control.

#### Scenario: Collapse the sidebar
- **WHEN** a member on a wide screen with the "Goalner" board open activates "Collapse menu"
- **THEN** the sidebar narrows to icons, the section labels and the project list are no longer visible, the "Backlog" link is still reachable by its name, and the board area is wider than before

#### Scenario: Navigate from the rail
- **WHEN** the sidebar is collapsed and the member activates the "Backlog" icon
- **THEN** the backlog opens and its icon is marked as the active section

#### Scenario: Switch project from the rail
- **WHEN** the sidebar is collapsed and the member activates the project switcher
- **THEN** the menu of the member's projects opens, and choosing one opens its board

#### Scenario: Expand the sidebar
- **WHEN** the sidebar is collapsed and the member activates "Expand menu"
- **THEN** the full sidebar with labels and the project list is shown again, and keyboard focus stays on the toggle

#### Scenario: Choice remembered
- **WHEN** a member collapses the sidebar and reloads the page
- **THEN** the sidebar is still collapsed

#### Scenario: Narrow screen
- **WHEN** a member who collapsed the sidebar opens the menu on a narrow screen
- **THEN** the navigation shows full labels and the project list, with no collapse control
