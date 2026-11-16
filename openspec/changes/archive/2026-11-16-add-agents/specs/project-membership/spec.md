## ADDED Requirements

### Requirement: Agent addresses cannot be invited
An invitation to an address on the agent domain (`agents.goalner.com`) SHALL be rejected with a validation error on the address, whether or not an agent has that address. No invitation SHALL be created and no email SHALL be sent. Agents join projects as defined in spec `agents`.

#### Scenario: Inviting an agent's address
- **WHEN** a member invites `silver-fish-4821@agents.goalner.com`
- **THEN** the request is rejected with a validation error on the address, and no invitation or email is created

## MODIFIED Requirements

### Requirement: Member list and removal
Members SHALL be able to list the project's members with name, email and avatar. Agents (spec `agents`) SHALL be listed and marked as agents. Deleted agents SHALL NOT be listed. Only the project owner SHALL be able to remove other members who are people. Any member SHALL be able to remove an agent, as defined in spec `agents`. The owner SHALL NOT be removable.

#### Scenario: Owner removes a member
- **WHEN** the owner removes a member
- **THEN** that user loses access to the project and their assigned tasks in it become unassigned

#### Scenario: Member tries to remove another member
- **WHEN** a non-owner member requests removal of another member who is a person
- **THEN** the request is rejected with HTTP 403 and membership is unchanged

#### Scenario: Member removes an agent
- **WHEN** a non-owner member removes agent Fish, which also belongs to another project
- **THEN** Fish is no longer a member of the project, and its assigned tasks in it become unassigned

#### Scenario: Agents in the list
- **WHEN** a member lists the members of a project with agent Fish and deleted agent Owl
- **THEN** Fish is listed and marked as an agent, and Owl is not listed

### Requirement: Teammates
The system SHALL list a user's teammates: the distinct users who share at least one non-archived project with them, with name, email and avatar. Agents SHALL be listed and marked as agents. Deleted agents SHALL NOT be teammates.

#### Scenario: Teammates list
- **WHEN** a user who shares project A with Bob and project B with Carol requests teammates
- **THEN** the list contains Bob and Carol and no other users

#### Scenario: Agent teammates
- **WHEN** a user shares GOAL with agent Fish and deleted agent Owl
- **THEN** the teammates list contains Fish, marked as an agent, and does not contain Owl
