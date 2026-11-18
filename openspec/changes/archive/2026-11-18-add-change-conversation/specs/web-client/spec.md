## ADDED Requirements

### Requirement: Change page
Each change SHALL have a page, reached from its name in the board summary and on the changes screen. The page address SHALL name the change by its name when it is open and by its id when it is archived, so that reloading or sharing the address shows the same change. The page SHALL show:
- the change's name; its phases in order, with the current phase marked as current and the earlier phases marked as passed, in text and not only by colour; its card counts with a link to its board; and, for an open change, a phase menu offering Idea, Exploring, Proposed and Implementing, and the "Archive" action (requirement "Archiving a change");
- its idea, formatted, with an edit action while the change is in Idea;
- its thread, oldest first: each comment with its author, marked as an agent where it is one (requirement "Agent marker"), and each entry of its history as a line among the comments at its time, naming who moved the change to which phase or who imported which files; and, for an open change, a field to add a comment;
- its files: a tab for each file and one for `tasks.md` with the change's marked text, each shown formatted, with a switch that shows the file's text exactly as imported; and who imported the change last, and when.

An archived change's page SHALL offer no phase menu, no idea editing, no comment field and no "Archive" action. An address that names no change of the project SHALL show a message that the change is archived or does not exist.

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
- **WHEN** a member chooses Implementing in the phase menu of `export-csv`
- **THEN** `export-csv` is in Implementing, and the page marks Implementing as current

#### Scenario: Idea fixed
- **WHEN** a member opens the page of `export-csv` while it is in Exploring
- **THEN** its idea is shown without an edit action

#### Scenario: Archived change
- **WHEN** a member opens the page of the archived change `fix-login`
- **THEN** its idea, thread and files are shown, with no phase menu, idea editing, comment field or "Archive" action

#### Scenario: Unknown change
- **WHEN** a member opens a page address naming the change `no-such-change`
- **THEN** the page says that the change is archived or does not exist

## MODIFIED Requirements

### Requirement: Screens
The client SHALL provide screens for:
- a personal dashboard (own or a teammate's open tasks and upcoming deadlines);
- the project list and project creation;
- a project's board in kanban and list layouts, one change at a time;
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
- **THEN** the project's columns are shown in order with their tasks, each card showing key, title, label, assignee avatar, deadline and importance

#### Scenario: Owner-only settings
- **WHEN** a non-owner member opens the project
- **THEN** no project settings entry is offered

#### Scenario: Agents entry
- **WHEN** any member opens a project
- **THEN** the project's sections include Agents

#### Scenario: No sprints, backlog or milestones
- **WHEN** any member opens a project
- **THEN** the project's sections include Changes, and include no Backlog, Sprints or Milestones

### Requirement: Board change tabs
Above the board, in both layouts, the client SHALL show a tab for each open change of the project, newest first, then an "Other tasks" tab for the board of other tasks (spec `project-board`), then a "New change" action. Each change tab SHALL show the change's name, its phase, a marker with an accessible name when the change is waiting for people (spec `changes`, "Waiting for people"), and how many of its cards are in the done column out of all its cards. The tabs SHALL be exposed to assistive technology as a tab list, with the shown tab marked as selected. Choosing a tab SHALL show that board, and a task added on it SHALL be created in that change, or in no change on "Other tasks". The shown tab SHALL be part of the page address, so that reloading or sharing the address shows the same tab. Without a tab in the address, the board SHALL show the newest open change, or "Other tasks" when there is no open change. An address that names a change that is not open SHALL show that default tab together with a message that the change is archived or does not exist.

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
While a change's tab is shown, the board SHALL show above its columns the change's name as a link to the change's page (requirement "Change page"), its phase, how many of the cards on the board are in the done column out of all cards on the board (as text and as a progress bar), and an "Archive" action. The board of other tasks SHALL show no summary.

#### Scenario: Change in progress
- **WHEN** the board of `add-labels`, which is in Implementing, holds 4 cards of which 1 is in the done column
- **THEN** the summary shows `add-labels` linking to its page, the phase Implementing, "1 of 4 done" with a progress bar at 25%, and "Archive"

#### Scenario: Other tasks
- **WHEN** a member shows the "Other tasks" tab
- **THEN** no change summary is shown

### Requirement: Changes screen
The changes screen SHALL show each open change, newest first, as a collapsible section whose header shows its name as a link to the change's page (requirement "Change page"), its phase, a marker with an accessible name when it is waiting for people, its task counts and its actions, and whose body lists its tasks with a field that adds a task to that change. Done tasks SHALL be marked as done in text, not only by colour. Each task SHALL offer a move menu listing the other open changes and "Other tasks", except a card whose mark is in its change's tasks text (spec `changes`, "Tasks in a change"), which SHALL offer no move menu. The screen SHALL offer a "New change" action. Archived changes SHALL be listed collapsed below, most recently archived first, each name linking to the change's page, and expanding one SHALL list its tasks.

#### Scenario: Add a task to a change
- **WHEN** a member expands `export-csv` and types "Rate limiting" into its add field
- **THEN** the task is listed under `export-csv` and appears on the board of `export-csv`

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
The "New change" action, on the board and on the changes screen, SHALL open a dialog that asks for the change's name and, optionally, its idea in a Markdown text field. As the member types the name, the dialog SHALL turn capital letters into lowercase and spaces into hyphens, and it SHALL show the allowed format. A validation error from the server SHALL be shown next to its field. After a change is created from the board, the board SHALL show that change.

#### Scenario: Typing a name
- **WHEN** a member types "Export CSV" into the name field
- **THEN** the field holds `export-csv`

#### Scenario: With an idea
- **WHEN** a member creates `export-csv` with the idea "People want a project's tasks as CSV."
- **THEN** the change's page shows that idea

#### Scenario: Name taken
- **WHEN** a member submits the name `add-labels` while an open change has that name
- **THEN** the dialog stays open and shows the server's error next to the name field

#### Scenario: From the board
- **WHEN** a member creates the change `fix-login` from the board's "New change" action
- **THEN** the dialog closes and the board shows the tab `fix-login`
