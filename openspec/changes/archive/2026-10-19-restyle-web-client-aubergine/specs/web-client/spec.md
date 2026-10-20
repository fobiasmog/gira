# Spec Delta

## ADDED Requirements

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
