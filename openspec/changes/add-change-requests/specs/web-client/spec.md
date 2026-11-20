## ADDED Requirements

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

## MODIFIED Requirements

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

## REMOVED Requirements

### Requirement: New task from the board header
**Reason**: The board's header keeps only the project's title for now: each column's own add action creates a task in that column, so the header's "New task" repeated it for the first column.
**Migration**: Add a task with the add action of the column it belongs in.
