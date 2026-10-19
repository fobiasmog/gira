# sprints Specification

## Purpose

Lets a project work in time-boxed sprints: plan them, make one active so the board focuses on it, carry unfinished work over, and archive finished sprints.

## Requirements

### Requirement: Create a sprint
Members SHALL be able to create a sprint with a title of 1 to 100 characters, a start date and an end date not earlier than the start date. Creation SHALL accept two optional flags: one that activates the new sprint, and one that carries over the unfinished tasks of the currently active sprint.

#### Scenario: Plain sprint
- **WHEN** a member creates sprint "S1" from 2026-10-05 to 2026-10-18 without options
- **THEN** the sprint exists, is not active, and has no tasks

#### Scenario: Invalid dates
- **WHEN** a member submits an end date earlier than the start date
- **THEN** creation is rejected with a validation error

### Requirement: Single active sprint
A project SHALL have at most one active sprint. Activating a sprint SHALL deactivate any other sprint of the same project in the same operation.

#### Scenario: Activate another sprint
- **WHEN** a member activates sprint "S2" while "S1" is active
- **THEN** "S2" is active, "S1" is not, and the board shows the tasks of "S2"

### Requirement: Carry over unfinished tasks
Carrying tasks over from a source sprint into a target sprint SHALL copy every root, non-archived task of the source sprint that is not in the done column into the target sprint, and SHALL record for each copy the original task it descends from. Tasks in the done column SHALL stay only in the source sprint.

#### Scenario: Carry over at creation
- **WHEN** a member creates and activates sprint "S2" with carry-over while active "S1" has 4 open tasks and 3 done tasks
- **THEN** "S2" contains copies of the 4 open tasks, each linked to its original, and "S1" still contains all 7 tasks

### Requirement: Add tasks to a sprint
Members SHALL be able to put a root task of the project into one of the project's sprints; a task SHALL belong to at most one sprint.

#### Scenario: Sprint of another project
- **WHEN** a client assigns a task to a sprint id that belongs to another project
- **THEN** the request is rejected and the task's sprint is unchanged

### Requirement: Sprint lists and statistics
Members SHALL be able to list the project's sprints (newest first), the sprints still available for planning (starting today or later, or currently active), and archived sprints. Each listed sprint SHALL include its task count per column and its total task count, excluding archived tasks.

#### Scenario: Sprint statistics
- **WHEN** a member lists sprints of a project where "S1" has 2 tasks in "To Do" and 1 in "Done"
- **THEN** "S1" is reported with counts To Do 2, Done 1 and total 3

### Requirement: Archive a sprint
Members SHALL be able to archive a sprint, optionally carrying its unfinished tasks over to another sprint of the same project first. An archived sprint SHALL NOT be active and SHALL appear only in the archived sprints list.

#### Scenario: Archive with carry-over
- **WHEN** a member archives the active sprint "S1" choosing to move its tasks to "S2"
- **THEN** "S2" receives copies of the unfinished tasks, "S1" is archived and no longer active
