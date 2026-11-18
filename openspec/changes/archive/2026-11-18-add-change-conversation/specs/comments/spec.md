## ADDED Requirements

### Requirement: Comment on a change
Each change SHALL have a thread of comments. Members SHALL be able to list the comments of a change, open or archived, oldest first, and add a comment to an open change, under the same rules for text and attachments as comments on a task. Adding a comment to an archived change SHALL be refused with a validation error.

#### Scenario: Thread order
- **WHEN** agent Fish posts "Should archived tasks go into the file?" on `export-csv`, and a member then replies "No."
- **THEN** listing the comments of `export-csv` returns Fish's comment followed by the member's reply, each with its author and creation time

#### Scenario: Agent through MCP
- **WHEN** a client holding Fish's read-write MCP token posts a comment on `export-csv`
- **THEN** the comment is listed on `export-csv` with Fish as its author

#### Scenario: Archived change
- **WHEN** a member posts a comment on the archived change `fix-login`
- **THEN** the response is HTTP 422 with a validation error, and listing its comments still returns the earlier ones

#### Scenario: Attachment on a change comment
- **WHEN** a member posts a comment with a 1 MB PNG on `export-csv`
- **THEN** the file is attached and listed with file name, size and a preview, and only members of TEST can download it

## MODIFIED Requirements

### Requirement: Edit and delete own comments
A user SHALL be able to edit or delete only comments they wrote, on tasks and on changes. Deleted comments SHALL disappear from the comment list of their task or change.

#### Scenario: Edit someone else's comment
- **WHEN** a user tries to edit a comment written by another member
- **THEN** the response is HTTP 404 and the comment is unchanged

#### Scenario: Delete a comment on a change
- **WHEN** a member deletes the comment they posted on `export-csv`
- **THEN** it is no longer listed among the comments of `export-csv`
