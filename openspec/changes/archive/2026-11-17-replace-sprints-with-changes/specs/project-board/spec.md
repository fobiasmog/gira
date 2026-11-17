## ADDED Requirements

### Requirement: Board of a change
The board SHALL be shown for one open change of the project at a time, or for no change. The board of a change SHALL hold the root, non-archived tasks of that change. The board without a change, called the board of other tasks, SHALL hold the root, non-archived tasks that belong to no change. Both SHALL include done tasks, in the done column. An archived change, or a change of another project, SHALL have no board, and a request for one SHALL receive HTTP 404.

#### Scenario: Board of a change
- **WHEN** TEST has the open changes `add-labels`, holding tasks A and B, and `export-csv`, holding task C, task D belongs to no change, and a member opens the board of `add-labels`
- **THEN** the board shows A and B, and not C or D

#### Scenario: Board of other tasks
- **WHEN** a member opens the board of TEST without a change, and task D in "To Do" and task E in the done column belong to no change
- **THEN** the board shows D and E, and no task of any change

#### Scenario: Archived change
- **WHEN** a member requests the board of the archived change `add-labels`
- **THEN** the response is HTTP 404

## MODIFIED Requirements

### Requirement: Manage columns
Members SHALL be able to add a column (title of 1 to 50 characters), rename it, reorder columns, and delete a column. Deleting a column SHALL move its tasks to the end of the project's first remaining column, keeping their change, and SHALL NOT delete any task. A project SHALL always keep at least one column.

#### Scenario: Delete a column with tasks
- **WHEN** a member deletes the column "Work" that holds 3 tasks, on a board with columns "To Do", "Work", "Done"
- **THEN** the column is removed and the 3 tasks appear at the end of "To Do" with all their data intact, each still in the change it was in

#### Scenario: Delete the first column
- **WHEN** a member deletes "To Do", the first column, while it holds 2 tasks
- **THEN** the 2 tasks move to the end of "Work", which is now the first column

#### Scenario: Only the done column remains
- **WHEN** a member deletes "To Do" from a board with columns "To Do" and "Done" while it holds 2 tasks
- **THEN** the 2 tasks move to the end of "Done" and their completion time is set to the time of the deletion

#### Scenario: Delete the only column
- **WHEN** a member tries to delete the only remaining column
- **THEN** the request is rejected and the column is kept

## REMOVED Requirements

### Requirement: Backlog
**Reason**: There is no active sprint to plan against. Tasks that belong to no change are shown on the board of other tasks.
**Migration**: Open the board without a change (requirement "Board of a change"). The backlog task lists, sending a task to the backlog and putting a backlog task on the board are removed; a task leaves its change through spec `changes`, "Tasks in a change".

### Requirement: Done tasks outside sprints
**Reason**: The board of other tasks shows done tasks in the done column, so a separate list is not needed.
**Migration**: Open the board without a change.

### Requirement: Board respects sprints
**Reason**: There is no active sprint. Every open change has its own board.
**Migration**: See requirement "Board of a change". A task created on the board of a change is created in that change (spec `tasks`, "Create a task").
