# api-documentation Specification

## Purpose

Describes the API available to personal API tokens in a machine-readable OpenAPI document, keeps that document in step with the implementation, and lets signed-in users read it and try requests from an interactive page.

## Requirements

### Requirement: OpenAPI description of the token API
The system SHALL maintain an OpenAPI 3.1 document that describes every method and path opened to API tokens (spec `api-tokens`, "Endpoints available to tokens") and no other endpoint. Each operation SHALL describe its path and query parameters, its request body, its success response, and its error responses. Each operation SHALL declare Bearer token authentication.

#### Scenario: Opened endpoint documented
- **WHEN** a reader looks up creating a task in the document
- **THEN** it shows `POST /api/projects/{project_id}/tasks` with its body fields, the created task's fields in the 201 response, and Bearer authentication

#### Scenario: Session-only endpoint absent
- **WHEN** a reader looks for archiving a project, inviting a member or listing teammates
- **THEN** the document contains no such operation

#### Scenario: File downloads
- **WHEN** a reader looks up downloading an attachment
- **THEN** the document describes `GET /files/{signed_id}` and its preview variant, returning the file's bytes

### Requirement: Documented error responses
Every operation SHALL document the error responses it can give a token request, using the API's JSON error envelope and its error codes: 401 `invalid_token`, 403 `insufficient_scope` for write operations, 404 `not_found` where a record or project is looked up, 422 `validation_failed` with per-field messages where input is validated, and 429 `rate_limited`. File downloads SHALL document their 401 and 429 responses as bodiless statuses, and their 404 as the application's HTML not-found page.

#### Scenario: Read-only token writes
- **WHEN** a reader looks up the 403 response of creating a task
- **THEN** the document describes the error envelope with the code `insufficient_scope`

#### Scenario: Validation errors
- **WHEN** a reader looks up the 422 response of creating a label
- **THEN** the document describes the error envelope with field messages keyed by field name

### Requirement: The document matches the API
A verification command SHALL check the whole document against the API and exit with a non-zero status, naming each problem, when:
- an action is opened to tokens without a documented operation, or a documented operation has no opened action;
- a documented operation has no example request, or its example made with an API token does not receive the documented success response;
- a response to such a request does not conform to the document, or a request the API accepted (2xx) does not.

#### Scenario: Endpoint opened without documentation
- **WHEN** a change opens a new action to API tokens without documenting it, and the verification command runs
- **THEN** the command exits with a non-zero status and names the method and path

#### Scenario: Response field renamed
- **WHEN** a change renames a field in a task response that the document describes, and the verification command runs
- **THEN** the command exits with a non-zero status, naming the operation and the field

#### Scenario: Undocumented status
- **WHEN** a documented operation answers an example request with a status the document does not list for it
- **THEN** the verification command exits with a non-zero status, naming the operation and the status

#### Scenario: Operation without an example
- **WHEN** a documented operation has no example request in the verification suite
- **THEN** the verification command exits with a non-zero status and names the operation

### Requirement: Verification runs on demand
The verification SHALL be one command that a developer runs by hand or from a git hook. It SHALL run offline, without a running server, and SHALL NOT be part of the default test suite or continuous integration.

#### Scenario: Verification passes
- **WHEN** a developer runs the verification command while the document matches the API
- **THEN** it exits with status 0

#### Scenario: Default test run unaffected
- **WHEN** the default test suite runs, as in continuous integration, while the document disagrees with the API
- **THEN** the run does not fail because of the document

### Requirement: Error responses are verified
The verification command SHALL also fail when an operation does not list the error responses that "Documented error responses" requires of it, or when an example of each error kind does not conform to its documented response:
- 401 `invalid_token`;
- 403 `insufficient_scope`;
- 404 `not_found`;
- 422 `validation_failed`;
- 429 `rate_limited`;
- the bodiless 401 and the HTML 404 of file downloads.

#### Scenario: Missing error response
- **WHEN** a write operation in the document lists no 403 response
- **THEN** the verification command exits with a non-zero status and names the operation

#### Scenario: Error envelope changed
- **WHEN** a change renames the `message` field of the error envelope, and the verification command runs
- **THEN** the command exits with a non-zero status, naming the error response and the field

### Requirement: Interactive API documentation
`/api/docs` SHALL show the document in an interactive viewer to signed-in users, and `/api/openapi.yaml` SHALL return the document itself to signed-in users. A visitor without a session SHALL be sent to sign-in and brought back to `/api/docs` afterwards, or SHALL receive HTTP 401 for the document itself. A request with an API token SHALL receive HTTP 403 on both, as for every endpoint not opened to tokens.

#### Scenario: Signed-in user opens the docs
- **WHEN** a signed-in user opens `/api/docs`
- **THEN** the token API's operations are listed, grouped by resource, with their parameters, bodies and responses

#### Scenario: Visitor without a session
- **WHEN** a visitor who is not signed in opens `/api/docs`
- **THEN** they are sent to sign-in and, after signing in, see the documentation

#### Scenario: Download the document
- **WHEN** a signed-in user requests `/api/openapi.yaml`
- **THEN** the OpenAPI document is returned as YAML

#### Scenario: Token request
- **WHEN** a request with a valid API token asks for `/api/docs` or `/api/openapi.yaml`
- **THEN** the response is HTTP 403 with the error code `token_not_allowed`

### Requirement: Trying requests from the documentation
Requests sent from the documentation page SHALL be authenticated only by an API token that the user enters on the page. They SHALL never carry the session cookie, so they behave exactly as requests from an external client. The page SHALL NOT store the entered token in the browser beyond the open page.

#### Scenario: Try with a token
- **WHEN** a signed-in user enters a read-write token for GOAL and sends "create a task" from the page
- **THEN** the task is created in GOAL, attributed to the token's owner, and the page shows the 201 response

#### Scenario: Try without a token
- **WHEN** a signed-in user sends a request from the page without entering a token
- **THEN** the page shows the HTTP 401 response, although the user is signed in

#### Scenario: Token not kept
- **WHEN** a user enters a token on the page and then reloads it
- **THEN** no token is entered, and the token is not found in the browser's storage

### Requirement: Documentation page security
The documentation page SHALL follow the production Content Security Policy defined in `security-baseline` with no violations, and SHALL load every script, stylesheet, font and image from the application's own origin.

#### Scenario: No violations
- **WHEN** a signed-in user opens the documentation in a production build, expands an operation and sends a request with a token
- **THEN** the browser reports no CSP violations and requests nothing from another origin
