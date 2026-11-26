## ADDED Requirements

### Requirement: Repository of a project
A project SHALL be one git repository. It SHALL have a repository address, a text of 1 to 500 characters or `null`, and a default branch, which SHALL be `main` unless set. A branch name SHALL:
- be 1 to 255 characters of Latin letters, digits, `/`, `.`, `_` and `-`;
- not start with `/`, `.` or `-`;
- not end with `/`, `.` or `.lock`;
- not contain `..` or `//`.

Only the project owner SHALL be able to set the repository address and the default branch. A member's attempt SHALL be rejected with HTTP 403 and SHALL change nothing. Reading the project SHALL include both, for members and for tokens that reach the project. Changing the default branch SHALL NOT change the base branch of any existing change (spec `changes`, "Base branch of a change").

#### Scenario: New project
- **WHEN** a user creates the project TEST
- **THEN** TEST has no repository address and the default branch `main`

#### Scenario: Owner sets the repository
- **WHEN** the owner of TEST sets its repository address to `git@github.com:acme/goalner.git` and its default branch to `trunk`
- **THEN** reading TEST shows that address and the default branch `trunk`, and the next change created without a base branch gets `trunk`

#### Scenario: Member tries
- **WHEN** a member of TEST who is not its owner sets its default branch
- **THEN** the response is HTTP 403, and the default branch is unchanged

#### Scenario: Invalid branch name
- **WHEN** the owner sets the default branch to `-main`
- **THEN** the request is rejected with a validation error on the default branch
