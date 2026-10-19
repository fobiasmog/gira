## Purpose

Gives a user a personal overview of the open work assigned to them and of upcoming deadlines, and lets them look at a teammate's overview within the projects they share.

## ADDED Requirements

### Requirement: Open tasks assigned to a user
The system SHALL return the root, non-archived tasks assigned to the requested user that are not in a done column, grouped by project and then by column in column order. Each task SHALL include its key, title and importance flag.

#### Scenario: Own overview
- **WHEN** a user requests their own overview
- **THEN** the response groups their open assigned tasks by project and column and excludes done and archived tasks

### Requirement: Upcoming deadlines
The system SHALL return the requested user's open assigned tasks whose deadline falls between now and 7 days from now, ordered by deadline.

#### Scenario: Deadline window
- **WHEN** a user has open tasks due in 2 days, in 10 days and 1 day ago
- **THEN** only the task due in 2 days is returned

### Requirement: Teammate overview is limited to shared projects
A user SHALL be able to request the overview and deadlines of a teammate. The results SHALL include only tasks from projects that both the requester and the teammate are members of. Requests about a user who is not a teammate SHALL respond with HTTP 404.

#### Scenario: Partially shared work
- **WHEN** Alice views Bob's overview, and Bob has tasks in project A (shared with Alice) and project C (not shared)
- **THEN** only Bob's tasks from project A are returned

#### Scenario: Not a teammate
- **WHEN** Alice requests the overview of a user who shares no project with her
- **THEN** the response is HTTP 404
