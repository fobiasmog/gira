## Purpose

Lets a project define its own labels and tag each task with one of them for quick visual grouping on the board.

## ADDED Requirements

### Requirement: Project labels
Members SHALL be able to list the project's labels and create a label with a title of 1 to 30 characters that is unique within the project, ignoring letter case.

#### Scenario: Duplicate title
- **WHEN** a member creates a label "bug" in a project that already has "Bug"
- **THEN** creation is rejected with a validation error

### Requirement: Label a task
A task SHALL carry at most one label. Members SHALL be able to set a task's label to one of the same project's labels, replacing any previous label, and to remove it.

#### Scenario: Replace label
- **WHEN** a member sets label "feature" on a task labelled "bug"
- **THEN** the task's only label is "feature"

#### Scenario: Label from another project
- **WHEN** a client sets a label id that belongs to another project
- **THEN** the request is rejected and the task's label is unchanged

#### Scenario: Remove label
- **WHEN** a member removes the label from a task
- **THEN** the task has no label
