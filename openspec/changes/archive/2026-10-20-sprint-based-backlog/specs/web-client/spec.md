## ADDED Requirements

### Requirement: Backlog screen
The backlog screen SHALL list the project's backlog tasks, each showing its column, with a field that adds a task to the backlog. Each task SHALL offer a move menu listing the project's open sprints and, only while a sprint is active, the board's columns. Below the list, a collapsed "Done" group SHALL show the number of done tasks in no sprint and list them when expanded.

#### Scenario: Add a backlog task during a sprint
- **WHEN** a member types "Dark mode" into the backlog's add field while a sprint is active
- **THEN** the task is listed in the backlog on the first column and is not shown on the board

#### Scenario: Move a task into a planned sprint
- **WHEN** a member chooses "Sprint 3" in TEST-1's move menu
- **THEN** TEST-1 leaves the backlog list and is listed under "Sprint 3" on the sprints screen

#### Scenario: Put a task on the board
- **WHEN** a member chooses the column "Work" in TEST-1's move menu while "Sprint 1" is active
- **THEN** TEST-1 leaves the backlog list and appears at the end of "Work" on the board

#### Scenario: No active sprint
- **WHEN** a member opens a task's move menu while no sprint is active
- **THEN** the menu lists the open sprints and no board columns

#### Scenario: Done tasks outside sprints
- **WHEN** a member opens the backlog while 2 tasks in no sprint are in the done column
- **THEN** the backlog list does not contain them, a collapsed "Done (2)" group is shown below it, and expanding the group lists both tasks

### Requirement: Sprint planning screen
The sprints screen SHALL show each non-archived sprint, newest first, as a collapsible section whose header shows its title, dates, task counts and actions, and whose body lists its tasks with a field that adds a task to that sprint. Done tasks SHALL be marked as done and carried-over tasks SHALL name the sprint holding their copy. Each task SHALL offer a move menu listing the other open sprints and the backlog. Archived sprints SHALL be listed collapsed below.

#### Scenario: Plan a task
- **WHEN** a member expands "Sprint 3" and types "Rate limiting" into its add field
- **THEN** the task is listed under "Sprint 3" and appears neither on the board nor in the backlog

#### Scenario: Move a planned task back to the backlog
- **WHEN** a member chooses "Backlog" in the move menu of TEST-9, which is listed under "Sprint 3"
- **THEN** TEST-9 leaves "Sprint 3" and is listed in the backlog with its column unchanged

#### Scenario: Active sprint
- **WHEN** a member opens the sprints screen while "Sprint 1" is active
- **THEN** "Sprint 1" is marked as active and its section lists the tasks shown on the board

#### Scenario: Done and carried-over tasks in a sprint section
- **WHEN** a member expands "Sprint 2", which holds the done task GOAL-5 and the task GOAL-3 that was carried over into "Sprint 3"
- **THEN** GOAL-5 is marked as done in text, not only by colour, and GOAL-3 is marked "Carried to Sprint 3"

### Requirement: Move to backlog from the board
The board SHALL offer moving a task to the backlog only while a sprint is active.

#### Scenario: Move to backlog during a sprint
- **WHEN** a member chooses "Move to backlog" for GOAL-4 on the board while "Sprint 1" is active
- **THEN** GOAL-4 disappears from the board and is listed in the backlog

#### Scenario: No active sprint
- **WHEN** a member opens a task's menu on the board while no sprint is active
- **THEN** no "Move to backlog" action is offered
