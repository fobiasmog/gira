## Purpose

Lets a project group tasks under milestones and track how much of each milestone is done.

## ADDED Requirements

### Requirement: Create and list milestones
Members SHALL be able to create a milestone with a title of 1 to 100 characters and list the project's milestones. Each listed milestone SHALL include its total number of non-archived tasks and how many of them are in the done column.

#### Scenario: Progress counts
- **WHEN** a milestone has 5 non-archived tasks of which 2 are in the done column, plus 1 archived task
- **THEN** the milestone is listed with total 5 and done 2

### Requirement: View a milestone
Members SHALL be able to open a milestone and see its non-archived tasks.

#### Scenario: Open milestone
- **WHEN** a member opens milestone "v1"
- **THEN** the response contains "v1" and the list of its non-archived tasks

### Requirement: Delete and recover
Members SHALL be able to delete a milestone and recover a deleted milestone. A deleted milestone SHALL NOT be offered for assignment to tasks, and its tasks SHALL keep their reference so that recovering restores the grouping.

#### Scenario: Delete then recover
- **WHEN** a member deletes milestone "v1" with 3 tasks and then recovers it
- **THEN** "v1" is listed again with the same 3 tasks

#### Scenario: Assign a deleted milestone
- **WHEN** a client sets a task's milestone to a deleted milestone
- **THEN** the update is rejected with a validation error
