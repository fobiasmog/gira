## MODIFIED Requirements

### Requirement: Tool arguments
A tool call SHALL send only the arguments it was given. A body argument given as `null` SHALL be sent as `null`, and an omitted one SHALL NOT be sent. A call whose arguments do not match the tool's input schema SHALL return a tool error that names the offending arguments, without making an API request.

#### Scenario: Partial update
- **WHEN** a client calls `updateTask` with only a new title
- **THEN** the task's title changes and all its other fields keep their values

#### Scenario: Explicit null
- **WHEN** a client calls `setTaskChange` with `change_id` set to `null`
- **THEN** the task is taken out of its change

#### Scenario: Task key as id
- **WHEN** a client calls `showTask` with the id `GOAL-12`
- **THEN** the result is task GOAL-12

#### Scenario: Missing required argument
- **WHEN** a client calls `createTask` without `title`
- **THEN** the result is a tool error naming `title`, and no API request is made
