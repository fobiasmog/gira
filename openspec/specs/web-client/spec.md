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
The client SHALL provide screens for:
- a personal dashboard (own or a teammate's open tasks and upcoming deadlines);
- the project list and project creation;
- a project's board, one change at a time, in the kanban layout; the list layout is reached only by its address, since the board offers no layout switch for now, and tasks are added from their column's own add action;
- task details;
- changes, and each change's page;
- members and invitations;
- agents;
- project settings (owner only);
- the project archive and an archived task;
- profile settings (name, language, contact links, avatar, password, API tokens, connected apps);
- announcements;
- feedback.

#### Scenario: Board screen
- **WHEN** a member opens a project's board
- **THEN** the project's columns are shown in order with their tasks, each card showing key, title, label, assignee avatar, deadline and importance, and no switch to another layout is offered

#### Scenario: Owner-only settings
- **WHEN** a non-owner member opens the project
- **THEN** no project settings entry is offered

#### Scenario: Agents entry
- **WHEN** any member opens a project
- **THEN** the project's sections include Agents

#### Scenario: No sprints, backlog or milestones
- **WHEN** any member opens a project
- **THEN** the project's sections include Changes, and include no Backlog, Sprints or Milestones

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
- **WHEN** a keyboard user opens the "new change" dialog and presses Escape
- **THEN** the dialog closes and focus returns to the "new change" button

### Requirement: Supported browsers
The client SHALL fully work in the latest two major versions of Chrome, Edge, Firefox and Safari (desktop and iOS) and in Chrome for Android. Features newer than that baseline SHALL only enhance behaviour and SHALL NOT be required for any task to be completed.

#### Scenario: Missing progressive feature
- **WHEN** a supported browser lacks view transitions
- **THEN** board moves still work, only without the animation

### Requirement: Dependency policy
The client's directly declared runtime dependencies SHALL be exactly `vue`, `vue-router`, `pinia`, `@sentry/vue`, `@tiptap/*` packages and `swagger-ui-dist`, and its development dependencies exactly `vite`, `@vitejs/plugin-vue`, `typescript` and `vue-tsc`, at exact versions with a committed lockfile. Packages SHALL be installed without running install scripts. Client code SHALL NOT import packages that are not declared directly. Only the API documentation page's entry point SHALL import `swagger-ui-dist`. CI SHALL fail when any of these rules is broken.

#### Scenario: Unapproved dependency added
- **WHEN** a change adds `axios` to `package.json`
- **THEN** the CI dependency-policy check fails and names the package

#### Scenario: Importing a transitive package
- **WHEN** client code imports `marked`, which is only present as a transitive dependency
- **THEN** the CI check fails

#### Scenario: Documentation viewer imported by the application
- **WHEN** a module of the single-page application imports `swagger-ui-dist`
- **THEN** the CI check fails and names the importing file

### Requirement: Board change tabs
Above the board, in both layouts, the client SHALL show a tab for each open change of the project, newest first, then an "Other tasks" tab for the board of other tasks (spec `project-board`), then a "New change" action. Each change tab SHALL show the change's name, its phase, and a marker with an accessible name when the change is waiting for people (spec `changes`, "Waiting for people"); it SHALL show no count of cards, which the board summary shows (requirement "Board change summary"). The tabs SHALL be exposed to assistive technology as a tab list, with the shown tab marked as selected. Choosing a tab SHALL show that board, and a task added on it SHALL be created in that change, or in no change on "Other tasks". The shown tab SHALL be part of the page address, so that reloading or sharing the address shows the same tab. Without a tab in the address, the board SHALL show the newest open change, or "Other tasks" when there is no open change. An address that names a change that is not open SHALL show that default tab together with a message that the change is archived or does not exist.

#### Scenario: Switch change
- **WHEN** a member viewing the board of `add-labels` chooses the tab `export-csv`
- **THEN** the board shows the tasks of `export-csv`, the tab `export-csv` is marked as selected, and the page address names `export-csv`

#### Scenario: Phase and waiting marker
- **WHEN** `export-csv` is in Exploring and is waiting for people, and `add-labels` is in Implementing and is not
- **THEN** the tab `export-csv` shows Exploring and the waiting marker, and the tab `add-labels` shows Implementing and no marker

#### Scenario: Default tab
- **WHEN** a member opens the board of TEST, whose newest open change is `fix-login`, from the navigation
- **THEN** the tab `fix-login` is shown

#### Scenario: No open change
- **WHEN** a member opens the board of a project without open changes
- **THEN** "Other tasks" is shown, and the tab row holds only "Other tasks" and "New change"

#### Scenario: Reload
- **WHEN** a member reloads the page while the tab `export-csv` is shown
- **THEN** the board of `export-csv` is shown again

#### Scenario: Archived change in the address
- **WHEN** a member opens an address naming `add-labels` after `add-labels` was archived
- **THEN** the default tab is shown with a message that `add-labels` is archived or does not exist

#### Scenario: Add a task to a change's board
- **WHEN** a member adds "Fix flaky test" to the column "To Do" on the board of `add-labels`
- **THEN** the task belongs to `add-labels` and appears on its board

### Requirement: Board change summary
While a change's tab is shown, the board SHALL show above its columns an "Open the change" link to the change's page (requirement "Change page"), which names the change to assistive technology, and how many of the cards on the board are in the done column out of all cards on the board (as text and as a progress bar). It SHALL show no phase, which the change's tab shows (requirement "Board change tabs"), and offer no archive action: changes are archived from their page and from the changes screen (requirement "Archiving a change"). The board of other tasks SHALL show no summary.

#### Scenario: Change in progress
- **WHEN** the board of `add-labels`, which is in Implementing, holds 4 cards of which 1 is in the done column
- **THEN** the summary shows "Open the change" linking to the page of `add-labels` and "1 of 4 done" with a progress bar at 25%, and shows no phase and no "Archive only" action

#### Scenario: Other tasks
- **WHEN** a member shows the "Other tasks" tab
- **THEN** no change summary is shown

### Requirement: Archiving a change
The "Archive only" action, on the changes screen and the change page, SHALL archive the change in Goalner (spec `changes`, "Archive a change") without asking any agent for a step. It SHALL ask for confirmation in a dialog, which SHALL say that no agent is asked, so the OpenSpec change is not archived and its specs are not synced, and that "Archive and sync specs" on the change's page (requirement "Requests on the change page") asks an agent to do that. When the change has root tasks that are not in the done column, the dialog SHALL also say how many there are, that agents may still be working on them, and that they stay with the archived change and leave the board. Archiving SHALL stay possible either way. Once a change is archived, the board SHALL no longer offer its tab, and SHALL show the default tab where it showed the change (requirement "Board change tabs").

#### Scenario: Unfinished cards
- **WHEN** a member chooses "Archive only" for `add-labels`, which has 3 cards that are not in the done column
- **THEN** the dialog warns that 3 cards are not done and will stay with the archived change, and the member can still archive it

#### Scenario: Everything done
- **WHEN** a member chooses "Archive only" for a change whose cards are all in the done column
- **THEN** the dialog asks for confirmation, says that the OpenSpec change is not archived and its specs are not synced, and shows no warning

#### Scenario: After archiving
- **WHEN** a member confirms archiving `add-labels` on its page, and then opens the board
- **THEN** the tab `add-labels` is gone and the board shows the default tab

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
- **THEN** the switcher invites them to choose a project and no Board, Changes or other project section links are shown

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
- **WHEN** a task with the label "Design" is shown as a board card, as a row on the changes screen and on its task page
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
On wide screens, the sidebar SHALL offer a control that collapses it to a narrow rail of icons, and from the rail a control that expands it again. The rail SHALL keep the logo, the project switcher (as the open project's initial), Dashboard, the open project's sections and "Write to us". Each of these SHALL keep its accessible name and SHALL show its label as a tooltip. The rail SHALL still mark the active section. The sidebar SHALL list no projects of its own, expanded or not: the project switcher lists them (requirement "Project switcher"). The content area SHALL take the width the sidebar gives up. The choice SHALL be remembered in the browser across reloads. When browser storage is unavailable, the sidebar SHALL start expanded. The narrow-screen navigation SHALL always show the full sidebar and SHALL NOT offer the collapse control.

#### Scenario: Collapse the sidebar
- **WHEN** a member on a wide screen with the "Goalner" board open activates "Collapse menu"
- **THEN** the sidebar narrows to icons, the section labels are no longer visible, the "Changes" link is still reachable by its name, and the board area is wider than before

#### Scenario: Navigate from the rail
- **WHEN** the sidebar is collapsed and the member activates the "Changes" icon
- **THEN** the changes screen opens and its icon is marked as the active section

#### Scenario: Switch project from the rail
- **WHEN** the sidebar is collapsed and the member activates the project switcher
- **THEN** the menu of the member's projects opens, and choosing one opens its board

#### Scenario: Expand the sidebar
- **WHEN** the sidebar is collapsed and the member activates "Expand menu"
- **THEN** the full sidebar with labels is shown again, and keyboard focus stays on the toggle

#### Scenario: Choice remembered
- **WHEN** a member collapses the sidebar and reloads the page
- **THEN** the sidebar is still collapsed

#### Scenario: Narrow screen
- **WHEN** a member who collapsed the sidebar opens the menu on a narrow screen
- **THEN** the navigation shows full labels, with no collapse control

### Requirement: Changes screen
The changes screen SHALL show each open change, newest first, as a collapsible section whose header shows its name as a link to the change's page (requirement "Change page"), its phase, a marker with an accessible name when it is waiting for people, its task counts and its actions, and whose body lists its tasks. The screen SHALL offer no field to add a task: tasks are added to a change on its board. Done tasks SHALL be marked as done in text, not only by colour. Each task SHALL offer a move menu listing the other open changes and "Other tasks", except a card whose mark is in its change's tasks text (spec `changes`, "Tasks in a change"), which SHALL offer no move menu. The screen SHALL offer a "New change" action. Archived changes SHALL be listed collapsed below, most recently archived first, each name linking to the change's page, and expanding one SHALL list its tasks.

#### Scenario: Add a task to a change
- **WHEN** a member expands `export-csv`, and later adds "Rate limiting" on the board of `export-csv`
- **THEN** the section offers no field to add a task, and then lists "Rate limiting" under `export-csv`

#### Scenario: Move a task to other tasks
- **WHEN** a member chooses "Other tasks" in the move menu of TEST-9, which is listed under `fix-login`
- **THEN** TEST-9 leaves `fix-login` and is shown on the board of other tasks with its column unchanged

#### Scenario: Card of tasks.md
- **WHEN** a member views the section of `add-labels`, whose cards were created by importing it
- **THEN** those cards offer no move menu, and a task added to `add-labels` by hand does offer one

#### Scenario: Archived change
- **WHEN** a member expands the archived change `fix-login` below the open changes
- **THEN** its tasks are listed, done ones marked as done

#### Scenario: Phase and waiting marker
- **WHEN** `export-csv` is in Proposed and is waiting for people
- **THEN** its section header shows Proposed and the waiting marker, and its name links to its page

### Requirement: New change dialog
The "New change" action, on the board and on the changes screen, SHALL open a dialog that asks for the change's name, optionally its idea in a Markdown text field, and its agent (spec `change-requests`, "Agent of a change"). The agent field SHALL offer "Any free agent", which is the default, and each of the project's agents with its state: free, on which change, or offline. As the member types the name, the dialog SHALL turn capital letters into lowercase and spaces into hyphens, and it SHALL show the allowed format. A validation error from the server SHALL be shown next to its field. After a change is created from the board, the board SHALL show that change.

#### Scenario: Typing a name
- **WHEN** a member types "Export CSV" into the name field
- **THEN** the field holds `export-csv`

#### Scenario: With an idea
- **WHEN** a member creates `export-csv` with the idea "People want a project's tasks as CSV."
- **THEN** the change's page shows that idea

#### Scenario: Pick an agent
- **WHEN** a member opens the dialog while Fish is on `export-csv`, Heron is free and Owl is offline, and creates `add-tags` with Fish
- **THEN** the agent field listed Fish as on `export-csv`, Heron as free and Owl as offline, and the page of `add-tags` says that Fish will take it

#### Scenario: Name taken
- **WHEN** a member submits the name `add-labels` while an open change has that name
- **THEN** the dialog stays open and shows the server's error next to the name field

#### Scenario: From the board
- **WHEN** a member creates the change `fix-login` from the board's "New change" action
- **THEN** the dialog closes and the board shows the tab `fix-login`

### Requirement: API tokens screen
The settings SHALL include an API tokens screen that lists the user's tokens and creates one from a name, one of the user's projects, read-only or read-write access, an expiry of 7, 30, 90 or 365 days, and the current password. A new token's value SHALL be shown once, with a copy control and a warning that it will not be shown again. Revoking SHALL ask for confirmation. The screen SHALL link to the API documentation.

#### Scenario: Create and copy
- **WHEN** a user creates a token on the API tokens screen with their correct password
- **THEN** the token's value is shown with a copy control and a warning that it will not be shown again, and the token appears in the list

#### Scenario: Value not shown again
- **WHEN** a user leaves the API tokens screen after creating a token and comes back
- **THEN** the list shows the token without its value

#### Scenario: Wrong password
- **WHEN** a user submits the creation form with a wrong current password
- **THEN** the error is shown under the password field and the other fields keep their values

#### Scenario: Revoke
- **WHEN** a user chooses to revoke a token and confirms
- **THEN** the token disappears from the list

#### Scenario: Password change warning
- **WHEN** a user opens the password change form
- **THEN** it states that changing the password revokes all API tokens and disconnects all connected apps

#### Scenario: Link to the API documentation
- **WHEN** a user follows the API documentation link on the API tokens screen
- **THEN** the API documentation page opens

### Requirement: Connected apps screen
The settings SHALL include a Connected apps screen that lists the user's MCP connections. Each connection SHALL show the client's name, its redirect host, the access level, when it was connected and when it was last active. Disconnecting SHALL ask for confirmation. With no connections, the screen SHALL explain how to connect an MCP client and link to the README's MCP section.

#### Scenario: List connections
- **WHEN** a user with a read-write claude.ai connection opens the Connected apps screen
- **THEN** the connection is listed with its client name, the host `claude.ai`, read-write access, and its connection and last-active times

#### Scenario: Disconnect
- **WHEN** a user chooses to disconnect a connection and confirms
- **THEN** the connection disappears from the list

#### Scenario: No connections
- **WHEN** a user without connections opens the Connected apps screen
- **THEN** the screen explains how to connect an MCP client instead of showing an empty list

### Requirement: Agents screen
Each project SHALL have an Agents screen. It SHALL list the project's agents with their name, address, creator, number of live tokens, whether they are online or offline with their last check-in, and the change each one is on (spec `change-requests`, "Check-ins"), and its deleted agents in a collapsed group. From it, a member SHALL be able to:
- create an agent from a name, the first token's name, read-only or read-write access, its channels (API, MCP or both) and the current password;
- add an agent they can see from another of their projects;
- rename an agent;
- remove an agent from the project, except from its last project;
- delete an agent, after confirming;
- restore a deleted agent;
- list an agent's tokens with issuer, access, channels, last four characters, creation time and last use;
- issue a token with the same fields as at creation;
- revoke a token, after confirming.

A new token's value SHALL be shown once, with a copy control and a warning that it will not be shown again. When the token includes MCP, the screen SHALL also show a ready-to-copy MCP client configuration with the MCP endpoint and the value, a note that a client configured with it in a working copy acts as that agent there, and a link to the MCP guide. When it includes the API, the screen SHALL link to the API documentation.

#### Scenario: Create with MCP
- **WHEN** a member creates agent "Fish" with an MCP-only token and their correct password
- **THEN** the token's value is shown once with a copy control, a warning and an MCP client configuration containing it, and Fish appears in the list

#### Scenario: Agent states
- **WHEN** Fish checked in a minute ago and is on `export-csv`, and Owl last checked in two hours ago
- **THEN** the list shows Fish as online and on `export-csv`, and Owl as offline with its last check-in

#### Scenario: Wrong password
- **WHEN** a member submits the creation form with a wrong current password
- **THEN** the error is shown under the password field and the other fields keep their values

#### Scenario: Only project
- **WHEN** a member opens the actions of an agent that belongs to no other non-archived project
- **THEN** removing it from the project is not offered, and deleting it is

#### Scenario: Restore
- **WHEN** a member restores a deleted agent from the deleted group
- **THEN** the agent moves to the list of agents, with no tokens

### Requirement: Agent marker
Wherever the client shows a user, an agent SHALL carry a visible marker with an accessible name, and a deleted agent SHALL additionally be marked as deleted. This covers avatars on cards and on the task page, assignee and member pickers, comments, the member list, teammates and the dashboard's choice of teammate. The marker SHALL NOT rely on colour alone. Assignee pickers SHALL NOT offer deleted agents.

#### Scenario: Card
- **WHEN** a task assigned to agent Fish is on the board
- **THEN** its assignee avatar carries the agent marker

#### Scenario: Comment by a deleted agent
- **WHEN** a task shows a comment written by an agent that has since been deleted
- **THEN** the author is shown with the agent marker and marked as deleted

#### Scenario: Assignee picker
- **WHEN** a member opens the assignee picker of a task in a project with agent Fish and deleted agent Owl
- **THEN** Fish is offered with the agent marker, and Owl is not offered

### Requirement: Change page
Each change SHALL have a page, reached from the "Open the change" link of the board summary and from its name on the changes screen. The page address SHALL name the change by its name when it is open and by its id when it is archived, so that reloading or sharing the address shows the same change. The page SHALL show:
- the change's name; its phases in order, with the current phase marked as current and the earlier phases marked as passed, in text and not only by colour; its card counts with a link to its board; and, for an open change, the "Archive only" action (requirement "Archiving a change");
- its idea, formatted, with an edit action while the change is in Idea;
- its thread, oldest first: each comment with its author, marked as an agent where it is one (requirement "Agent marker"), and each entry of its history as a line among the comments at its time, naming who moved the change to which phase or who imported which files; and, for an open change, a field to add a comment;
- its files: a tab for each file and one for `tasks.md` with the change's marked text, each shown formatted, with a switch that shows the file's text exactly as imported; and who imported the change last, and when.

The page SHALL offer no menu to choose a phase: a change's phase moves with the steps its agent takes (spec `change-requests`) and through the API. An archived change's page SHALL offer no idea editing, no comment field and no "Archive only" action. An address that names no change of the project SHALL show a message that the change is archived or does not exist.

#### Scenario: Review a proposal
- **WHEN** a member opens the page of `export-csv`, which is in Proposed and whose last import brought a proposal, a design, the spec `export` and a tasks text
- **THEN** the page marks Idea and Exploring as passed and Proposed as current, offers the tabs `proposal.md`, `design.md`, `specs/export/spec.md` and `tasks.md`, and shows the proposal formatted

#### Scenario: Answer in the thread
- **WHEN** agent Fish's question is the newest comment on `export-csv`, and a member replies "No archived tasks." on its page
- **THEN** the reply is shown last in the thread, and `export-csv` is no longer marked as waiting for people

#### Scenario: History in the thread
- **WHEN** Fish moved `export-csv` to Exploring and then asked a question on it
- **THEN** the thread shows a line saying that Fish moved the change to Exploring, above Fish's question

#### Scenario: Source of a file
- **WHEN** a member shows `design.md` of `export-csv`, which holds a table, and switches to its source
- **THEN** the text of `design.md` is shown exactly as imported, the table's lines included

#### Scenario: Phase menu
- **WHEN** a member opens the page of `export-csv`, which is open and in Proposed
- **THEN** the page marks Proposed as current, and offers no menu to choose a phase

#### Scenario: Idea fixed
- **WHEN** a member opens the page of `export-csv` while it is in Exploring
- **THEN** its idea is shown without an edit action

#### Scenario: Archived change
- **WHEN** a member opens the page of the archived change `fix-login`
- **THEN** its idea, thread and files are shown, with no idea editing, comment field or "Archive only" action

#### Scenario: Unknown change
- **WHEN** a member opens a page address naming the change `no-such-change`
- **THEN** the page says that the change is archived or does not exist

### Requirement: Requests on the change page
On the page of an open change (requirement "Change page"), the client SHALL show:
- when the change has no open request (spec `change-requests`), a button beside the line of the request and agent, at the top of the page, that asks for the step that fits its phase: "Start exploring" in Idea, "Write the proposal" in Exploring, "Implement" in Proposed, "Continue implementing" in Implementing, and "Archive and sync specs" in Done. Text in the comment field SHALL go with the request as its comment, which the button SHALL say while the field holds text, and the field SHALL then be emptied;
- the change's request and agent in one line, at the start of that block. While no agent is on the change, the line SHALL be the agent menu followed by "will take it": the menu offers "Any free agent" and the project's agents with their states (free, on which change, or offline), and shows the picked agent, or "Any free agent" when none is picked. While an agent is on the change, the line SHALL say who is working on its taken request and since when; that the agent's context is full and the change is blocked, for a blocked change (spec `change-requests`, "Full context"); that its waiting request is queued for the agent, saying when the agent is offline; or, with no open request, that the agent is on the change;
- a "Cancel request" action while there is an open request. When that request is a reply request that is waiting, the button for the phase's step SHALL be shown as well;
- a "Release" action, naming the agent, while an agent is on the change;
- beside the comment field, while a comment would create a reply request, a note that posting asks the change's agent, or an agent, to reply.

While the change has an open request and the page is visible, the client SHALL reload the change and its thread at least every 15 seconds, so that the request's state, the agent's comments and the phase are shown without reloading the page. In the thread, each request asked for, taken, finished or cancelled, each release and each block SHALL appear as a history line naming who did it and which step or which agent. The page of an archived change SHALL offer no request or agent actions.

#### Scenario: Start exploring
- **WHEN** a member opens the page of `export-csv`, which is in Idea with no agent and no open request, and chooses "Start exploring"
- **THEN** the page says that any free agent will take it, offers "Cancel request", and no longer offers "Start exploring"

#### Scenario: Button for the phase
- **WHEN** a member opens the page of `export-csv`, which is in Proposed with no open request
- **THEN** the page offers "Implement"

#### Scenario: Comment with the step
- **WHEN** a member types "Start with the API." into the comment field of `export-csv` and chooses "Implement"
- **THEN** the comment is shown in the thread, the field is empty, and the page shows the implement request as open

#### Scenario: Queued for a busy agent
- **WHEN** a member chooses "Start exploring" on `add-tags`, which has agent Fish picked while Fish is on `export-csv`
- **THEN** the page says that Fish, on `export-csv`, will take it, and offers "Cancel request"

#### Scenario: Taken request
- **WHEN** agent Fish took the implement request of `export-csv` at 14:05
- **THEN** the page says that Fish has been working on it since 14:05, and offers "Cancel request" and "Release Fish"

#### Scenario: Blocked
- **WHEN** Fish's context filled up while it was implementing `export-csv`, and a member opens the board and then the page of `export-csv`
- **THEN** the tab `export-csv` shows the waiting marker, and the page says that Fish's context is full and the change is blocked, and offers "Release Fish"

#### Scenario: Agent picks it up
- **WHEN** a member has the page of `export-csv` open with its explore request waiting, and Fish takes the request and later finishes it with questions
- **THEN** without reloading, the page shows that Fish is working on it, and later shows Fish's questions in the thread and no open request

#### Scenario: Cancel
- **WHEN** a member chooses "Cancel request" while the explore request of `export-csv` is waiting
- **THEN** the page shows no open request and offers "Start exploring" again

#### Scenario: Pick another agent
- **WHEN** a member chooses Heron in the agent menu of `add-tags`, which has Fish picked
- **THEN** the page says that Heron will take it

#### Scenario: Release
- **WHEN** Fish is on `export-csv` and a member chooses "Release Fish"
- **THEN** the page shows no agent and offers the agent menu, and the thread shows a line saying that the member released Fish

#### Scenario: Reply note
- **WHEN** a member opens the page of `export-csv`, which is in Exploring with Fish on it and no open request
- **THEN** a note beside the comment field says that posting asks Fish to reply

#### Scenario: Request lines in the thread
- **WHEN** a member asked for an explore request on `export-csv` and Fish took it and finished it with questions
- **THEN** the thread shows the member asking for exploring, Fish taking it and finishing it, followed by Fish's questions

#### Scenario: Archived change
- **WHEN** a member opens the page of the archived change `fix-login`
- **THEN** no request button, "Cancel request", "Release" or agent menu is offered
