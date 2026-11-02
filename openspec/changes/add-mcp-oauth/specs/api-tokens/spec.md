# Spec Delta

## ADDED Requirements

### Requirement: Connection tokens
A connection token SHALL be issued only to the MCP server, in exchange for a valid access token of an MCP connection (spec `mcp-authorization`), presented together with the MCP server's service key. It SHALL reach the projects and access level of that connection. It SHALL expire no later than that access token, and SHALL stop authenticating when the connection ends. Every other rule of this spec SHALL apply to it as to a personal token.

#### Scenario: Exchange
- **WHEN** the MCP server presents its service key and a valid access token of Alice's read-write connection
- **THEN** it receives a connection token that expires no later than the access token, and requests with it act as Alice in all of her non-archived projects

#### Scenario: Wrong service key
- **WHEN** a request presents a valid access token with a missing or wrong service key
- **THEN** the response is HTTP 401 and no token is issued

#### Scenario: Ended connection
- **WHEN** the MCP server presents an access token of a connection that has ended
- **THEN** the response is HTTP 401 and no token is issued

#### Scenario: Disconnected while in use
- **WHEN** Alice disconnects a connection whose connection token has not yet expired
- **THEN** the next request with that connection token receives HTTP 401

#### Scenario: Read-only connection
- **WHEN** a connection token of a read-only connection is used to create a task
- **THEN** the response is HTTP 403 with the code `insufficient_scope`

#### Scenario: Not a personal token
- **WHEN** a user with connection tokens lists their API tokens
- **THEN** no connection token is listed, and connection tokens do not count toward the limit of 20

## MODIFIED Requirements

### Requirement: Create a personal API token
A signed-in user SHALL be able to create an API token with a name of 1 to 100 characters, one non-archived project they are a member of, an access level of read-only or read-write, and an expiry of 1 to 365 days from creation. The response SHALL contain the token's value, which SHALL NOT be retrievable afterwards. A user SHALL have at most 20 unexpired personal tokens. Connection tokens SHALL NOT count toward this limit.

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

### Requirement: List and revoke tokens
A user SHALL be able to list their unexpired personal tokens, each with its name, project, access level, the last four characters of its value, expiry, creation time and last use, and SHALL be able to revoke any of them without re-entering the password. A revoked token SHALL stop authenticating immediately. A user SHALL NOT be able to see or revoke another user's tokens. Connection tokens SHALL NOT be listed and SHALL NOT be revocable here; they end with their connection.

#### Scenario: Listing does not reveal values
- **WHEN** a user lists their tokens
- **THEN** each entry shows the last four characters of the token's value and never the whole value

#### Scenario: Revoke
- **WHEN** a user revokes their token "CI"
- **THEN** the next request made with that token receives HTTP 401

#### Scenario: Another user's token
- **WHEN** a user requests revocation of a token id that belongs to another user
- **THEN** the response is HTTP 404 and the token keeps working

#### Scenario: Connection token id
- **WHEN** a user requests revocation of the id of one of their connection tokens
- **THEN** the response is HTTP 404 and the connection keeps working

### Requirement: Token reach is limited to its project
A personal token SHALL give access only to the project it was created for, and only while its owner is a member of that project and the project is not archived. Requests for any other project SHALL receive HTTP 404, as for a non-member, even when the owner is a member of it. With a personal token, the project list SHALL contain only the token's project. A connection token SHALL reach every non-archived project its owner is a member of at the time of each request.

#### Scenario: Another project of the owner
- **WHEN** a token created for project GOAL requests the tasks of project TEST, which its owner is also a member of
- **THEN** the response is HTTP 404

#### Scenario: Project list
- **WHEN** a token created for GOAL, owned by a member of GOAL and TEST, requests the project list
- **THEN** the list contains only GOAL

#### Scenario: Comment in another project
- **WHEN** a token created for GOAL edits its owner's comment on a task of TEST
- **THEN** the response is HTTP 404 and the comment is unchanged

#### Scenario: Connection token project list
- **WHEN** a connection token owned by a member of GOAL and TEST, and of the archived project OLD, requests the project list
- **THEN** the list contains GOAL and TEST

#### Scenario: Connection token after leaving
- **WHEN** the owner of a connection token leaves TEST and the token then requests TEST's tasks
- **THEN** the response is HTTP 404, and requests for the owner's other projects keep working

### Requirement: File downloads with a token
A token SHALL be able to download the attachments of comments in the projects it reaches and the avatars of those projects' members, including its owner's. Any other file SHALL receive HTTP 404, as for a user who may not see it.

#### Scenario: Attachment in the token's project
- **WHEN** a token for GOAL downloads an attachment of a comment on a GOAL task
- **THEN** the file is returned

#### Scenario: Attachment in another project
- **WHEN** a token for GOAL downloads an attachment of a comment in TEST, a project its owner also belongs to
- **THEN** the response is HTTP 404

### Requirement: Token lifetime and revocation
A token SHALL stop authenticating when:
- it expires;
- its owner revokes it (personal tokens) or its connection ends (connection tokens);
- the owner's password is changed or reset;
- for a personal token, the owner leaves or is removed from the token's project;
- for a personal token, that project is archived.

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

#### Scenario: Connection token outlives no project
- **WHEN** the owner of GOAL archives it while a member holds a connection token
- **THEN** the connection token keeps working for the member's other projects and receives HTTP 404 for GOAL

### Requirement: Token rate limits
A user SHALL be able to create at most 10 personal tokens per hour. Each access token of a connection SHALL be exchanged for connection tokens at most 60 times per hour. Each token SHALL be able to make at most 300 requests per minute. Requests over a limit SHALL receive HTTP 429 and SHALL NOT be processed.

#### Scenario: Request burst
- **WHEN** a token makes its 301st request within one minute
- **THEN** the request receives HTTP 429 and has no effect

#### Scenario: Creation burst
- **WHEN** a user requests an eleventh token within one hour
- **THEN** the request receives HTTP 429 and no token is created

#### Scenario: Exchange burst
- **WHEN** the MCP server exchanges the same access token a 61st time within one hour
- **THEN** the response is HTTP 429 and no token is issued
