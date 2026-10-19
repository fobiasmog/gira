## Purpose

Defines the signed-in single-page application: which screens exist and how they are reached, how it talks to the API and handles errors, how it renders user content safely under a strict Content Security Policy, and which browsers and dependencies it relies on.

## ADDED Requirements

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
