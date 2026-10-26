# api-tokens Specification

## Purpose

Lets users give scripts and integrations access to the API on their behalf through personal tokens that are limited to one project, an access level and a lifetime, and that can be revoked, while the web client keeps using its session.

## Requirements

### Requirement: Create a personal API token
A signed-in user SHALL be able to create an API token with a name of 1 to 100 characters, one non-archived project they are a member of, an access level of read-only or read-write, and an expiry of 1 to 365 days from creation. The response SHALL contain the token's value, which SHALL NOT be retrievable afterwards. A user SHALL have at most 20 unexpired tokens.

#### Scenario: Successful creation
- **WHEN** a member of project GOAL creates a read-write token named "CI" for GOAL expiring in 90 days, entering their correct password
- **THEN** the response contains the token's value, name, project, access level and expiry, and the token is listed among the user's tokens

#### Scenario: Expiry over a year
- **WHEN** a user requests a token expiring in 366 days
- **THEN** creation is rejected with a validation error on the expiry and no token is created

#### Scenario: No expiry
- **WHEN** a user requests a token without an expiry
- **THEN** creation is rejected with a validation error on the expiry and no token is created

#### Scenario: Project the user does not belong to
- **WHEN** a user requests a token for a project they are not a member of
- **THEN** creation is rejected with a validation error on the project and no token is created

#### Scenario: Token limit
- **WHEN** a user with 20 unexpired tokens requests another one
- **THEN** creation is rejected with a validation error and no token is created

### Requirement: Token creation requires the current password
Creating a token SHALL require the user's current password. A wrong password SHALL reject the request without creating a token and SHALL count as a failed attempt toward account lockout as defined in `user-auth`. While the account is locked, creation SHALL be refused with the same error even when the password is correct.

#### Scenario: Wrong password
- **WHEN** a signed-in user requests a token with a wrong current password
- **THEN** the request is rejected with a validation error on the current password, no token is created, and the account's failed-attempt count increases by one

#### Scenario: Locked account
- **WHEN** a user whose account is locked requests a token with the correct password
- **THEN** the request is rejected with the same validation error as for a wrong password and no token is created

### Requirement: List and revoke tokens
A user SHALL be able to list their unexpired tokens, each with its name, project, access level, the last four characters of its value, expiry, creation time and last use, and SHALL be able to revoke any of them without re-entering the password. A revoked token SHALL stop authenticating immediately. A user SHALL NOT be able to see or revoke another user's tokens.

#### Scenario: Listing does not reveal values
- **WHEN** a user lists their tokens
- **THEN** each entry shows the last four characters of the token's value and never the whole value

#### Scenario: Revoke
- **WHEN** a user revokes their token "CI"
- **THEN** the next request made with that token receives HTTP 401

#### Scenario: Another user's token
- **WHEN** a user requests revocation of a token id that belongs to another user
- **THEN** the response is HTTP 404 and the token keeps working

### Requirement: Authenticate API requests with a token
A request SHALL be authenticated by a token only through the header `Authorization: Bearer <token>`. Such a request SHALL be authenticated by the token alone: its session cookie SHALL be ignored and it SHALL NOT need a CSRF token. An unknown, expired or revoked token SHALL receive HTTP 401 with the JSON error envelope. A token sent in the URL or the request body SHALL NOT authenticate.

#### Scenario: Write without a CSRF token
- **WHEN** a client sends a POST that creates a task with a valid read-write token and no CSRF token
- **THEN** the task is created

#### Scenario: Invalid token with a valid session cookie
- **WHEN** a request carries an unknown token and also a valid session cookie
- **THEN** the response is HTTP 401 and the session is not used

#### Scenario: Expired token
- **WHEN** a request carries a token whose expiry has passed
- **THEN** the response is HTTP 401 with the JSON error envelope

#### Scenario: Token in the query string
- **WHEN** a client without a session sends a valid token as a query parameter and no `Authorization` header
- **THEN** the response is HTTP 401

#### Scenario: Web client unchanged
- **WHEN** the web client sends a request with its session cookie and CSRF token and no `Authorization` header
- **THEN** the request is authenticated by the session exactly as without this capability

### Requirement: Token reach is limited to its project
A token SHALL give access only to the project it was created for, and only while its owner is a member of that project and the project is not archived. Requests for any other project SHALL receive HTTP 404, as for a non-member, even when the owner is a member of it. With a token, the project list SHALL contain only the token's project.

#### Scenario: Another project of the owner
- **WHEN** a token created for project GOAL requests the tasks of project TEST, which its owner is also a member of
- **THEN** the response is HTTP 404

#### Scenario: Project list
- **WHEN** a token created for GOAL, owned by a member of GOAL and TEST, requests the project list
- **THEN** the list contains only GOAL

#### Scenario: Comment in another project
- **WHEN** a token created for GOAL edits its owner's comment on a task of TEST
- **THEN** the response is HTTP 404 and the comment is unchanged

### Requirement: Token access level
A read-only token SHALL be allowed only GET and HEAD requests. A read-write token SHALL be allowed every method on the endpoints that accept tokens. Any other request made with a read-only token SHALL receive HTTP 403 and SHALL have no effect. Changes made with a token SHALL be attributed to the token's owner, as if made by them in the web client.

#### Scenario: Read-only token writes
- **WHEN** a read-only token for GOAL creates a task in GOAL
- **THEN** the response is HTTP 403 and no task is created

#### Scenario: Read-only token reads
- **WHEN** a read-only token for GOAL requests GOAL's board
- **THEN** the board is returned

#### Scenario: Attribution
- **WHEN** a read-write token owned by Alice adds a comment to a task
- **THEN** the comment's author is Alice

### Requirement: Endpoints available to tokens
Tokens SHALL be accepted only by endpoints explicitly opened to them: reading the project, its board and its member list; tasks and their subtasks, placement, completion, label, sprint and comments; editing and deleting comments; labels; milestones; sprints; reading one's own profile; and file downloads. Every other endpoint SHALL answer a token with HTTP 403 and have no effect, including endpoints added later unless they are opened.

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

#### Scenario: Own profile
- **WHEN** a token requests the signed-in user's profile
- **THEN** its owner's profile is returned

### Requirement: File downloads with a token
A token SHALL be able to download the attachments of comments in its project and the avatars of its project's members, including its owner's. Any other file SHALL receive HTTP 404, as for a user who may not see it.

#### Scenario: Attachment in the token's project
- **WHEN** a token for GOAL downloads an attachment of a comment on a GOAL task
- **THEN** the file is returned

#### Scenario: Attachment in another project
- **WHEN** a token for GOAL downloads an attachment of a comment in TEST, a project its owner also belongs to
- **THEN** the response is HTTP 404

### Requirement: Token storage and secrecy
The system SHALL store only a one-way digest of each token's value, never the value itself. Token values SHALL start with the prefix `glnr_`, so that leaked values can be recognised, and SHALL contain at least 160 bits of randomness. Token values SHALL NOT appear in logs or error reports.

#### Scenario: Stored data
- **WHEN** an operator reads the stored token records
- **THEN** no record contains a value that authenticates a request

#### Scenario: Logged request
- **WHEN** a request authenticated by a token is logged or produces an error report
- **THEN** neither contains the token's value

### Requirement: Token lifetime and revocation
A token SHALL stop authenticating when:
- it expires;
- its owner revokes it;
- the owner's password is changed or reset;
- the owner leaves or is removed from the token's project;
- that project is archived.

A token that stopped authenticating SHALL NOT work again, even when the owner rejoins the project. The time of a token's last use SHALL be recorded to within one hour.

#### Scenario: Password changed
- **WHEN** a user with two tokens changes their password from settings
- **THEN** requests with either token receive HTTP 401, and the user's current session stays signed in

#### Scenario: Password reset
- **WHEN** a user with a token completes a password reset
- **THEN** requests with the token receive HTTP 401

#### Scenario: Leaving and rejoining
- **WHEN** a user with a token for GOAL leaves GOAL and is later invited back and accepts
- **THEN** requests with the token receive HTTP 401, both before and after rejoining

#### Scenario: Removed by the owner
- **WHEN** the owner of GOAL removes a member who has a token for GOAL
- **THEN** requests with that token receive HTTP 401

#### Scenario: Project archived
- **WHEN** the owner archives GOAL
- **THEN** every member's tokens for GOAL stop authenticating

#### Scenario: Last use
- **WHEN** a token is used to make a request
- **THEN** listing tokens shows a last use no more than one hour before that request

### Requirement: Token rate limits
A user SHALL be able to create at most 10 tokens per hour. Each token SHALL be able to make at most 300 requests per minute. Requests over a limit SHALL receive HTTP 429 and SHALL NOT be processed.

#### Scenario: Request burst
- **WHEN** a token makes its 301st request within one minute
- **THEN** the request receives HTTP 429 and has no effect

#### Scenario: Creation burst
- **WHEN** a user requests an eleventh token within one hour
- **THEN** the request receives HTTP 429 and no token is created
