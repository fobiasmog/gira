## MODIFIED Requirements

### Requirement: Assignment email
When a member assigns a task to another member who is a person, the system SHALL send the assignee one email in the assignee's language. The email SHALL contain the assigner's name, the task key and a link to the task, and SHALL NOT contain the task description or comments. An assigner who is an agent (spec `agents`) SHALL be named like any other. No email SHALL be sent:
- when the assignee is an agent;
- when users assign a task to themselves;
- when the assignee is unchanged;
- when the update is rejected.

#### Scenario: Assign to a teammate
- **WHEN** Alice assigns GOAL-7 to Bob
- **THEN** Bob receives one email naming Alice and GOAL-7 with a link to the task

#### Scenario: Self-assignment
- **WHEN** Alice assigns GOAL-7 to herself
- **THEN** no email is sent

#### Scenario: Assign to an agent
- **WHEN** Alice assigns GOAL-7 to agent Fish
- **THEN** no email is sent

#### Scenario: Agent assigns a person
- **WHEN** agent Fish assigns GOAL-12 to Bob
- **THEN** Bob receives one email naming Fish and GOAL-12 with a link to the task
