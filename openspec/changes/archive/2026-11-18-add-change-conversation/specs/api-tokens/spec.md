## MODIFIED Requirements

### Requirement: Endpoints available to tokens
Tokens SHALL be accepted only by endpoints explicitly opened to them: reading the project, its board, its columns and its member list; tasks and their subtasks, placement, completion, label, change and comments; editing and deleting comments; labels; changes, their comments and their files (spec `changes`, spec `comments` and spec `openspec-changes`); importing OpenSpec changes (spec `openspec-changes`); reading one's own profile; and file downloads. Every other endpoint SHALL answer a token with HTTP 403 and have no effect, including endpoints added later unless they are opened.

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

#### Scenario: OpenSpec import
- **WHEN** a read-write token for GOAL imports an OpenSpec change into GOAL, and a read-only token for GOAL opens it
- **THEN** both requests succeed

#### Scenario: OpenSpec import with a read-only token
- **WHEN** a read-only token for GOAL imports an OpenSpec change
- **THEN** the response is HTTP 403 with the code `insufficient_scope` and nothing changes

#### Scenario: Changes
- **WHEN** a read-write token for GOAL creates a change, puts a task into it, lists the changes and archives the change
- **THEN** each request succeeds

#### Scenario: Changes with a read-only token
- **WHEN** a read-only token for GOAL lists GOAL's changes and then tries to create one
- **THEN** the list is returned, and the creation receives HTTP 403 with the code `insufficient_scope` and creates nothing

#### Scenario: Change thread, phase and files
- **WHEN** a read-write token for GOAL moves a change to Exploring and comments on it, and a read-only token for GOAL lists the change's comments and reads its `proposal.md`
- **THEN** each request succeeds

#### Scenario: Change thread with a read-only token
- **WHEN** a read-only token for GOAL comments on a change or moves it to another phase
- **THEN** each request receives HTTP 403 with the code `insufficient_scope` and nothing changes
