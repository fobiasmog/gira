# Spec Delta

## MODIFIED Requirements

### Requirement: Screens
The client SHALL provide screens for: a personal dashboard (own or a teammate's open tasks and upcoming deadlines); the project list and project creation; a project's board in kanban and list layouts; backlog; task details; sprints; milestones and a single milestone; members and invitations; project settings (owner only); the project archive and an archived task; profile settings (name, language, contact links, avatar, password, API tokens); announcements; and feedback.

#### Scenario: Board screen
- **WHEN** a member opens a project's board
- **THEN** the project's columns are shown in order with their tasks, each card showing key, title, label, assignee avatar, deadline and importance

#### Scenario: Owner-only settings
- **WHEN** a non-owner member opens the project
- **THEN** no project settings entry is offered

## ADDED Requirements

### Requirement: API tokens screen
The settings SHALL include an API tokens screen that lists the user's tokens and creates one from a name, one of the user's projects, read-only or read-write access, an expiry of 7, 30, 90 or 365 days, and the current password. A new token's value SHALL be shown once, with a copy control and a warning that it will not be shown again. Revoking SHALL ask for confirmation.

#### Scenario: Create and copy
- **WHEN** a user creates a token on the API tokens screen with their correct password
- **THEN** the token's value is shown with a copy control and a warning that it will not be shown again, and the token appears in the list

#### Scenario: Value not shown again
- **WHEN** a user leaves the API tokens screen after creating a token and comes back
- **THEN** the list shows the token without its value

#### Scenario: Wrong password
- **WHEN** a user submits the creation form with a wrong current password
- **THEN** the error is shown under the password field and the other fields keep their values

#### Scenario: Revoke
- **WHEN** a user chooses to revoke a token and confirms
- **THEN** the token disappears from the list

#### Scenario: Password change warning
- **WHEN** a user opens the password change form
- **THEN** it states that changing the password revokes all API tokens
