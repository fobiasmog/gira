## MODIFIED Requirements

### Requirement: Endpoints available to tokens
Tokens SHALL be accepted only by endpoints explicitly opened to them: reading the project, its board, its columns and its member list; tasks and their subtasks, placement, completion, label, sprint and comments; editing and deleting comments; labels; milestones; sprints; reading one's own profile; and file downloads. Every other endpoint SHALL answer a token with HTTP 403 and have no effect, including endpoints added later unless they are opened.

#### Scenario: Project administration
- **WHEN** a read-write token for GOAL renames or archives GOAL, creates a project, invites someone, removes a member, leaves GOAL, or adds, renames, moves or deletes a column
- **THEN** each request receives HTTP 403 and nothing changes

#### Scenario: Account management
- **WHEN** a read-write token changes its owner's profile, password or avatar, or lists, creates or revokes tokens
- **THEN** each request receives HTTP 403 and nothing changes

#### Scenario: Data across projects
- **WHEN** a token requests teammates, statistics or announcements, or sends feedback
- **THEN** each request receives HTTP 403

#### Scenario: Member list
- **WHEN** a read-only token for GOAL requests GOAL's members
- **THEN** the members are returned

#### Scenario: Column list
- **WHEN** a read-only token for GOAL requests GOAL's columns
- **THEN** the columns are returned in board order

#### Scenario: Columns of another project
- **WHEN** a token for GOAL requests the columns of TEST, a project its owner also belongs to
- **THEN** the response is HTTP 404

#### Scenario: Own profile
- **WHEN** a token requests the signed-in user's profile
- **THEN** its owner's profile is returned
