## Purpose

Defines a project's board: its ordered columns (statuses), which column means "done", how tasks are placed and ordered on it, and the backlog of tasks not yet on the board.

## ADDED Requirements

### Requirement: Default columns
Every new project SHALL start with three columns in this order: "To Do", "Work", "Done".

#### Scenario: New project board
- **WHEN** a project is created
- **THEN** its columns are "To Do", "Work", "Done" in that order and "Done" is the done column

### Requirement: Done column
Exactly one column of a project SHALL be the done column, and it SHALL always be the last column in order. A newly added column SHALL be inserted immediately before the done column. When columns are reordered or deleted, the done column SHALL be recalculated to be the new last column.

#### Scenario: Column added
- **WHEN** a member adds a column "Review" to a board with columns "To Do", "Work", "Done"
- **THEN** the order becomes "To Do", "Work", "Review", "Done" and "Done" remains the done column

#### Scenario: Reordering
- **WHEN** a member moves the last column to the first position
- **THEN** the column that is now last becomes the done column

### Requirement: Manage columns
Members SHALL be able to add a column (title of 1 to 50 characters), rename it, reorder columns, and delete a column. Deleting a column SHALL move its tasks to the backlog and SHALL NOT delete any task. A project SHALL always keep at least one column.

#### Scenario: Delete a column with tasks
- **WHEN** a member deletes a column that holds 3 tasks
- **THEN** the column is removed and the 3 tasks appear in the backlog with all their data intact

#### Scenario: Delete the only column
- **WHEN** a member tries to delete the only remaining column
- **THEN** the request is rejected and the column is kept

### Requirement: Place and order tasks
Members SHALL be able to move a root task to a given position in a given column of the same project. Positions within every affected column SHALL remain contiguous starting from 0 after the move. Moving a task into the done column SHALL record its completion time; moving it out SHALL clear it.

#### Scenario: Move between columns
- **WHEN** a member moves a task from "To Do" position 2 to "Work" position 0
- **THEN** the task is first in "Work", the tasks below it in "Work" shift down by one, and the remaining "To Do" tasks close the gap

#### Scenario: Move into done
- **WHEN** a member moves a task into the done column
- **THEN** the task's completion time is set to the time of the move

#### Scenario: Column from another project
- **WHEN** a client moves a task to a column id that belongs to a different project
- **THEN** the request is rejected with a validation error and the task stays where it was

### Requirement: Backlog
Root tasks that are not placed on any column SHALL form the project's backlog. Members SHALL be able to list the backlog, move a task from a column to the backlog, and place a backlog task onto a column.

#### Scenario: Send to backlog
- **WHEN** a member moves a task from a column to the backlog
- **THEN** the task no longer appears on the board and appears in the backlog list

### Requirement: Board respects sprints
When a project has an active sprint, newly created board tasks SHALL be added to that sprint unless the client explicitly creates them outside it, and the board SHALL show only the active sprint's tasks.

#### Scenario: Create task during a sprint
- **WHEN** a member creates a task on a column while a sprint is active
- **THEN** the task belongs to the active sprint and appears on the board
