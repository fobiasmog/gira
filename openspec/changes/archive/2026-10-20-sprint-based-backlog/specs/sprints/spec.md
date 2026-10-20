## MODIFIED Requirements

### Requirement: Add tasks to a sprint
Members SHALL be able to put a root task of the project into one of the project's open sprints, move it to another open sprint, or take it out of its sprint, which returns it to the backlog. A task SHALL belong to at most one sprint and SHALL keep its column when its sprint changes.

#### Scenario: Sprint of another project
- **WHEN** a client assigns a task to a sprint id that belongs to another project
- **THEN** the request is rejected and the task's sprint is unchanged

#### Scenario: Archived sprint
- **WHEN** a client assigns a task to an archived sprint
- **THEN** the request is rejected and the task's sprint is unchanged

#### Scenario: Move to another sprint
- **WHEN** a member moves task GOAL-9, which is in "Work" in the planned sprint "S3", to the planned sprint "S4"
- **THEN** GOAL-9 belongs to "S4", is still in "Work", and is no longer listed with the tasks of "S3"

#### Scenario: Take a task out of its sprint
- **WHEN** a member takes task GOAL-9, which is in "Work" in "S3", out of its sprint
- **THEN** GOAL-9 belongs to no sprint, is still in "Work", and is listed in the backlog

## ADDED Requirements

### Requirement: Sprint task list
Members SHALL be able to list the root, non-archived tasks of one sprint of their project, done ones included, ordered by column order and then by position within the column. Each listed task SHALL include its column and, when it has been carried over, the sprint that holds its most recent copy.

#### Scenario: Tasks of a planned sprint
- **WHEN** a member lists the tasks of the planned sprint "S3", which holds one task in "Done" and two in "To Do"
- **THEN** the two "To Do" tasks are listed first in their column order, followed by the "Done" task

#### Scenario: Carried-over task
- **WHEN** a member lists the tasks of "S1", whose open task GOAL-3 was carried over into "S2"
- **THEN** GOAL-3 is listed with "S2" as the sprint holding its copy

#### Scenario: Sprint of another project
- **WHEN** a member requests, within their project, the task list of a sprint id that belongs to another project
- **THEN** the response is HTTP 404 and no tasks are returned
