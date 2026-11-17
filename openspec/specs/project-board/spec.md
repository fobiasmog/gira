# project-board Specification

## Purpose

Defines a project's board: its ordered columns (statuses), which column means "done", how tasks are placed and ordered on it, and which tasks it shows: those of one change, or those in no change.

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

### Requirement: List columns
Members SHALL be able to list a project's columns in board order, without the board's tasks. Each column SHALL have its id, title, color, position, and whether it is the done column, as in the board snapshot. The last column in the list SHALL be the done column.

#### Scenario: List columns
- **WHEN** a member lists the columns of a project whose board has "To Do", "Work", "Review", "Done"
- **THEN** the list contains "To Do", "Work", "Review", "Done" in that order, each with its id, title, color and position, and only "Done" is marked as the done column

#### Scenario: Same columns as the board
- **WHEN** a member lists a project's columns and then reads its board
- **THEN** both contain the same columns with the same fields and order

#### Scenario: Not a member
- **WHEN** a user lists the columns of a project they are not a member of
- **THEN** the response is HTTP 404

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
