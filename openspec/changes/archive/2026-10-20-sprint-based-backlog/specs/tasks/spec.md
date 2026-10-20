## MODIFIED Requirements

### Requirement: Create a task
Members SHALL be able to create a task in a project with a title of 1 to 255 characters, optionally naming its column and its sprint. A task created without a column SHALL be placed on the project's first column. A named sprint SHALL be an open sprint of the same project. The creator SHALL be recorded. Each task SHALL receive a sequence number unique within its project, starting at 1 for the project's first task and increasing by one for each task created afterwards.

#### Scenario: First task in a project
- **WHEN** a member creates the first task of project "GOAL"
- **THEN** the task's sequence number is 1 and its key is "GOAL-1"

#### Scenario: Concurrent creation
- **WHEN** two members create tasks in the same project at the same moment
- **THEN** the two tasks receive different sequence numbers

#### Scenario: Create without a column
- **WHEN** a member creates a task without naming a column or a sprint in a project with columns "To Do", "Work", "Done"
- **THEN** the task is at the end of "To Do", belongs to no sprint, and is listed in the backlog

#### Scenario: Create in a planned sprint
- **WHEN** a member creates a task naming the planned sprint "S3"
- **THEN** the task belongs to "S3", is on the first column, and is listed with the tasks of "S3"

#### Scenario: Archived sprint
- **WHEN** a client creates a task naming an archived sprint or a sprint of another project
- **THEN** the request is rejected with a validation error and no task is created
