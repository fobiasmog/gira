# project-membership Specification

## Purpose

Lets project members bring other people into a project with their consent, without ever creating accounts on someone's behalf or leaking who is registered.

## Requirements

### Requirement: Invite by email
Any project member SHALL be able to invite a person by email address. The response SHALL be identical whether or not the address belongs to an existing account. The invitee SHALL receive an email with a single-use invitation link that expires after 7 days. The system SHALL NOT create an account or a password on the invitee's behalf, and invitation emails SHALL NOT contain any password.

#### Scenario: Inviting a registered user
- **WHEN** a member invites an email that belongs to an existing account
- **THEN** the member sees "invitation sent", the invitee receives an invitation link, and the invitee does not become a member yet

#### Scenario: Inviting an unknown email
- **WHEN** a member invites an email with no account
- **THEN** the member sees the same "invitation sent" response, no account is created, and the email contains a link to sign up and accept

#### Scenario: Re-inviting
- **WHEN** a member invites an email that already has a pending invitation to the same project
- **THEN** no second invitation is created, the pending one is re-sent, and its expiry is extended to 7 days from now

#### Scenario: Inviting an existing member
- **WHEN** a member invites the email of someone who is already a member
- **THEN** the response is the same "invitation sent" message and no email is sent

### Requirement: Accept an invitation
An invitation SHALL be accepted only by a signed-in user whose confirmed email address matches the invited address. Accepting SHALL make the user a project member and consume the invitation. An invitee without an account SHALL be able to register from the invitation link and accept after confirming their email.

#### Scenario: Matching user accepts
- **WHEN** a signed-in user whose email matches the invitation opens a valid invitation link and accepts
- **THEN** the user becomes a member of the project and the link can no longer be used

#### Scenario: Different account
- **WHEN** a signed-in user whose email does not match opens the invitation link
- **THEN** acceptance is refused and the user is told the invitation was sent to another address

#### Scenario: Expired invitation
- **WHEN** an invitation link older than 7 days is opened
- **THEN** acceptance is refused and no membership is created

### Requirement: Pending invitations
Members SHALL be able to see the project's pending invitations (email and expiry). The project owner and the member who sent an invitation SHALL be able to revoke it.

#### Scenario: Revoke
- **WHEN** the owner revokes a pending invitation
- **THEN** the invitation link stops working

### Requirement: Invitation rate limit
A user SHALL be able to send at most 20 invitations per hour across all projects; further invitations SHALL receive HTTP 429.

#### Scenario: Over the limit
- **WHEN** a user sends a twenty-first invitation within one hour
- **THEN** the request receives HTTP 429 and no email is sent

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

### Requirement: Agent addresses cannot be invited
An invitation to an address on the agent domain (`agents.goalner.com`) SHALL be rejected with a validation error on the address, whether or not an agent has that address. No invitation SHALL be created and no email SHALL be sent. Agents join projects as defined in spec `agents`.

#### Scenario: Inviting an agent's address
- **WHEN** a member invites `silver-fish-4821@agents.goalner.com`
- **THEN** the request is rejected with a validation error on the address, and no invitation or email is created
