# project-board Specification

## Purpose

Defines a project's board: its ordered columns (statuses), which column means "done", how tasks are placed and ordered on it, and the backlog of tasks not yet on the board.

## Requirements

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
Members SHALL be able to add a column (title of 1 to 50 characters), rename it, reorder columns, and delete a column. Deleting a column SHALL move its tasks to the end of the project's first remaining column, keeping their sprint, and SHALL NOT delete any task. A project SHALL always keep at least one column.

#### Scenario: Delete a column with tasks
- **WHEN** a member deletes the column "Work" that holds 3 tasks, on a board with columns "To Do", "Work", "Done"
- **THEN** the column is removed and the 3 tasks appear at the end of "To Do" with all their data intact, each still in the sprint it was in

#### Scenario: Delete the first column
- **WHEN** a member deletes "To Do", the first column, while it holds 2 tasks
- **THEN** the 2 tasks move to the end of "Work", which is now the first column

#### Scenario: Only the done column remains
- **WHEN** a member deletes "To Do" from a board with columns "To Do" and "Done" while it holds 2 tasks
- **THEN** the 2 tasks move to the end of "Done" and their completion time is set to the time of the deletion

#### Scenario: Delete the only column
- **WHEN** a member tries to delete the only remaining column
- **THEN** the request is rejected and the column is kept

### Requirement: Place and order tasks
Members SHALL be able to move a root task to a given position in a given column of the same project. Every placement SHALL name a column; a placement without one SHALL be rejected. Positions within every affected column SHALL remain contiguous starting from 0 after the move. Moving a task into the done column SHALL record its completion time; moving it out SHALL clear it.

#### Scenario: Move between columns
- **WHEN** a member moves a task from "To Do" position 2 to "Work" position 0
- **THEN** the task is first in "Work", the tasks below it in "Work" shift down by one, and the remaining "To Do" tasks close the gap

#### Scenario: Move into done
- **WHEN** a member moves a task into the done column
- **THEN** the task's completion time is set to the time of the move

#### Scenario: Column from another project
- **WHEN** a client moves a task to a column id that belongs to a different project
- **THEN** the request is rejected with a validation error and the task stays where it was

#### Scenario: Placement without a column
- **WHEN** a client moves a task without naming a column
- **THEN** the request is rejected with a validation error and the task stays where it was

### Requirement: Backlog
Root, non-archived tasks that belong to no sprint and are not in the done column SHALL form the project's backlog, whatever other column they are in. Members SHALL be able to list the backlog with each task's column. While a sprint is active, members SHALL be able to send a board task to the backlog, which takes it out of the sprint and keeps its column, and put a backlog task onto a chosen column and position in one operation, which adds it to the active sprint.

#### Scenario: Task on a column outside the active sprint
- **WHEN** a sprint is active and task TEST-1 is in "To Do" and in no sprint
- **THEN** TEST-1 is listed in the backlog with the column "To Do" and is not shown on the board

#### Scenario: Task in a planned sprint
- **WHEN** a task belongs to the planned sprint "S3"
- **THEN** it is not listed in the backlog

#### Scenario: No active sprint
- **WHEN** no sprint is active
- **THEN** the tasks in no sprint that are not done are listed in the backlog, and all tasks in no sprint, done ones included, are shown on the board

#### Scenario: Done task outside sprints
- **WHEN** task GOAL-7 is in the done column and in no sprint
- **THEN** GOAL-7 is not listed in the backlog

#### Scenario: Send to backlog
- **WHEN** a member sends task GOAL-4, which is in "Work" in the active sprint "S1", to the backlog
- **THEN** GOAL-4 is no longer in "S1" or on the board, and it is listed in the backlog with the column "Work"

#### Scenario: Put a backlog task on the board
- **WHEN** a member puts the backlog task TEST-1 onto "Work" at position 0 while "S1" is active
- **THEN** TEST-1 belongs to "S1", is first in "Work" on the board, and is no longer listed in the backlog

### Requirement: Done tasks outside sprints
Members SHALL be able to list the root, non-archived tasks that are in the done column and belong to no sprint, most recently completed first, each with its completion time.

#### Scenario: List done tasks outside sprints
- **WHEN** GOAL-7 was completed yesterday and GOAL-8 today, both in no sprint, while GOAL-9 is done in the active sprint
- **THEN** the list contains GOAL-8 followed by GOAL-7, and not GOAL-9

### Requirement: Board respects sprints
When a project has an active sprint, the board SHALL show only the active sprint's tasks, and a task created on a column SHALL be added to that sprint unless the client explicitly creates it outside the sprint. When no sprint is active, the board SHALL show the tasks that belong to no sprint.

#### Scenario: Create task during a sprint
- **WHEN** a member creates a task on a column while a sprint is active
- **THEN** the task belongs to the active sprint and appears on the board

#### Scenario: Board without an active sprint
- **WHEN** no sprint is active, task A is in "To Do" and in no sprint, and task B is in "To Do" and in the planned sprint "S3"
- **THEN** the board shows A and does not show B
