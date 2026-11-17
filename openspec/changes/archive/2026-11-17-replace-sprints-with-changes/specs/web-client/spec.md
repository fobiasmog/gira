## ADDED Requirements

### Requirement: Board change tabs
Above the board, in both layouts, the client SHALL show a tab for each open change of the project, newest first, then an "Other tasks" tab for the board of other tasks (spec `project-board`), then a "New change" action. Each change tab SHALL show the change's name and how many of its cards are in the done column out of all its cards. The tabs SHALL be exposed to assistive technology as a tab list, with the shown tab marked as selected. Choosing a tab SHALL show that board, and a task added on it SHALL be created in that change, or in no change on "Other tasks". The shown tab SHALL be part of the page address, so that reloading or sharing the address shows the same tab. Without a tab in the address, the board SHALL show the newest open change, or "Other tasks" when there is no open change. An address that names a change that is not open SHALL show that default tab together with a message that the change is archived or does not exist.

#### Scenario: Switch change
- **WHEN** a member viewing the board of `add-labels` chooses the tab `export-csv`
- **THEN** the board shows the tasks of `export-csv`, the tab `export-csv` is marked as selected, and the page address names `export-csv`

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
While a change's tab is shown, the board SHALL show above its columns the change's name as a link to the changes screen, how many of the cards on the board are in the done column out of all cards on the board (as text and as a progress bar), and an "Archive" action. The board of other tasks SHALL show no summary.

#### Scenario: Change in progress
- **WHEN** the board of `add-labels` holds 4 cards of which 1 is in the done column
- **THEN** the summary shows `add-labels` linking to the changes screen, "1 of 4 done" with a progress bar at 25%, and "Archive"

#### Scenario: Other tasks
- **WHEN** a member shows the "Other tasks" tab
- **THEN** no change summary is shown

### Requirement: Archiving a change
Archiving a change, from the board summary or the changes screen, SHALL ask for confirmation in a dialog. When the change has root tasks that are not in the done column, the dialog SHALL say how many there are, that agents may still be working on them, and that they stay with the archived change and leave the board. Archiving SHALL stay possible either way. After a change is archived from its board, the board SHALL show the default tab (requirement "Board change tabs").

#### Scenario: Unfinished cards
- **WHEN** a member chooses "Archive" for `add-labels`, which has 3 cards that are not in the done column
- **THEN** the dialog warns that 3 cards are not done and will stay with the archived change, and the member can still archive it

#### Scenario: Everything done
- **WHEN** a member chooses "Archive" for a change whose cards are all in the done column
- **THEN** the dialog asks for confirmation and shows no warning

#### Scenario: After archiving
- **WHEN** a member confirms archiving `add-labels` from its board
- **THEN** the tab `add-labels` is gone and the board shows the default tab

### Requirement: Changes screen
The changes screen SHALL show each open change, newest first, as a collapsible section whose header shows its name, task counts and actions, and whose body lists its tasks with a field that adds a task to that change. Done tasks SHALL be marked as done in text, not only by colour. Each task SHALL offer a move menu listing the other open changes and "Other tasks", except a card whose mark is in its change's tasks text (spec `changes`, "Tasks in a change"), which SHALL offer no move menu. The screen SHALL offer a "New change" action. Archived changes SHALL be listed collapsed below, most recently archived first, and expanding one SHALL list its tasks.

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

### Requirement: New change dialog
The "New change" action, on the board and on the changes screen, SHALL open a dialog that asks for the change's name. As the member types, the dialog SHALL turn capital letters into lowercase and spaces into hyphens, and it SHALL show the allowed format. A validation error from the server SHALL be shown next to the field. After a change is created from the board, the board SHALL show that change.

#### Scenario: Typing a name
- **WHEN** a member types "Export CSV" into the name field
- **THEN** the field holds `export-csv`

#### Scenario: Name taken
- **WHEN** a member submits the name `add-labels` while an open change has that name
- **THEN** the dialog stays open and shows the server's error next to the name field

#### Scenario: From the board
- **WHEN** a member creates the change `fix-login` from the board's "New change" action
- **THEN** the dialog closes and the board shows the tab `fix-login`

## MODIFIED Requirements

### Requirement: Screens
The client SHALL provide screens for:
- a personal dashboard (own or a teammate's open tasks and upcoming deadlines);
- the project list and project creation;
- a project's board in kanban and list layouts, one change at a time;
- task details;
- changes;
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

### Requirement: Accessibility baseline
All interactive controls SHALL be operable by keyboard with a visible focus indicator; icon-only buttons SHALL have accessible names; dialogs SHALL be modal (focus contained, background inert) and close with Escape, returning focus to the control that opened them.

#### Scenario: Close a dialog with Escape
- **WHEN** a keyboard user opens the "new change" dialog and presses Escape
- **THEN** the dialog closes and focus returns to the "new change" button

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

### Requirement: Stable label and project colours
Every label and every project SHALL be shown with a colour that depends only on its identity, so that it is the same on every screen, for every member and across sessions. A colour SHALL never be the only way to identify a label or project: its title SHALL always be shown next to it.

#### Scenario: Same label everywhere
- **WHEN** a task with the label "Design" is shown as a board card, as a row on the changes screen and on its task page
- **THEN** the label chip has the same colours in all three places

#### Scenario: Same colour for every member
- **WHEN** two members of a project open its board on different devices
- **THEN** each label and the project marker are shown in the same colours for both

### Requirement: Collapsible sidebar
On wide screens, the sidebar SHALL offer a control that collapses it to a narrow rail of icons, and from the rail a control that expands it again. The rail SHALL keep the logo, the project switcher (as the open project's initial), Dashboard, the open project's sections and "Write to us". Each of these SHALL keep its accessible name and SHALL show its label as a tooltip. The rail SHALL still mark the active section. The project list SHALL NOT be shown in the rail. The content area SHALL take the width the sidebar gives up. The choice SHALL be remembered in the browser across reloads. When browser storage is unavailable, the sidebar SHALL start expanded. The narrow-screen navigation SHALL always show the full sidebar and SHALL NOT offer the collapse control.

#### Scenario: Collapse the sidebar
- **WHEN** a member on a wide screen with the "Goalner" board open activates "Collapse menu"
- **THEN** the sidebar narrows to icons, the section labels and the project list are no longer visible, the "Changes" link is still reachable by its name, and the board area is wider than before

#### Scenario: Navigate from the rail
- **WHEN** the sidebar is collapsed and the member activates the "Changes" icon
- **THEN** the changes screen opens and its icon is marked as the active section

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

## REMOVED Requirements

### Requirement: Board sprint summary
**Reason**: Changes have no dates and there is no active sprint.
**Migration**: See requirements "Board change tabs" and "Board change summary".

### Requirement: Backlog screen
**Reason**: The backlog is removed (spec `project-board`). Tasks in no change are shown on the "Other tasks" tab of the board.
**Migration**: Use the "Other tasks" tab (requirement "Board change tabs").

### Requirement: Sprint planning screen
**Reason**: Sprints are replaced by changes.
**Migration**: See requirement "Changes screen".

### Requirement: Move to backlog from the board
**Reason**: The backlog is removed.
**Migration**: Move a task out of its change from the changes screen's move menu, or from the task page.

### Requirement: OpenSpec work in a sprint being archived
**Reason**: Sprints are replaced by changes, and carry-over is removed.
**Migration**: See requirement "Archiving a change".
