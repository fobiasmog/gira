# mcp-server Specification

## Purpose

Lets AI assistants and other MCP clients use Goalner through the Model Context Protocol, by offering the API that personal tokens can use as tools, while every rule of that API keeps applying.

## Requirements

### Requirement: MCP endpoint
`/mcp` SHALL accept MCP requests sent as HTTP POST over the Streamable HTTP transport and answer each with a single JSON response. The server SHALL keep no session between requests: it SHALL NOT issue a session id, and any server instance SHALL be able to answer any request. GET and DELETE requests to `/mcp` SHALL receive HTTP 405.

#### Scenario: Listing tools
- **WHEN** a client with a valid personal API token sends a tools list request to `/mcp`
- **THEN** the response is a JSON body with the tools, and carries no session id

#### Scenario: Consecutive requests on different instances
- **WHEN** a client lists tools through one server instance and then calls a tool through another
- **THEN** both requests succeed

#### Scenario: Stream request
- **WHEN** a client sends a GET request to `/mcp`
- **THEN** the response is HTTP 405

### Requirement: Authentication by personal API token
Every request to `/mcp` SHALL carry a personal API token (spec `api-tokens`) in the header `Authorization: Bearer <token>`. A request without such a header, or with a token the API rejects as unknown, expired or revoked, SHALL receive HTTP 401 with a `WWW-Authenticate: Bearer` header and no MCP result. This includes requests that only list tools. A token sent in the URL or the request body SHALL NOT authenticate.

#### Scenario: No token
- **WHEN** a client sends a tools list request without an `Authorization` header
- **THEN** the response is HTTP 401 with a `WWW-Authenticate: Bearer` header, and no tools are listed

#### Scenario: Revoked token
- **WHEN** a user revokes their token "CI" and a client then lists tools with it
- **THEN** the response is HTTP 401

#### Scenario: Token revoked between calls
- **WHEN** a client lists tools with a valid token, the token is then revoked, and the client calls a tool with it
- **THEN** the tool call receives HTTP 401 and nothing changes

#### Scenario: Token in the query string
- **WHEN** a client sends a valid token only as a query parameter of `/mcp`
- **THEN** the response is HTTP 401

### Requirement: Tool calls act as the token
Each tool call SHALL make exactly one API request, authenticated by the caller's token. That request SHALL be subject to every rule of spec `api-tokens`: the token's project, its access level, the endpoints open to tokens, the rate limit and attribution to the token's owner. The MCP server SHALL reach Goalner data only through the API.

#### Scenario: Attribution
- **WHEN** a client calls `createTask` with a read-write token for GOAL owned by Alice
- **THEN** a task is created in GOAL and its creator is Alice

#### Scenario: Read-only token writes
- **WHEN** a client calls `createTask` with a read-only token for GOAL
- **THEN** the result is a tool error with the code `insufficient_scope`, and no task is created

#### Scenario: Another project of the owner
- **WHEN** a client calls `listTasks` with a token for GOAL and the id of TEST, a project its owner also belongs to
- **THEN** the result is a tool error with the code `not_found`

#### Scenario: Rate limit
- **WHEN** a client calls a tool with a token that has already made 300 requests within the last minute
- **THEN** the result is a tool error with the code `rate_limited`, and the call has no effect

### Requirement: Tools follow the API document
The server SHALL offer one tool for each operation of the API document (spec `api-documentation`) whose success response is JSON, and no other tool. Each tool SHALL be named by the operation's id and described by its summary and description. Each tool SHALL take the operation's path, query and body parameters as named arguments, with the document's types and required fields.

#### Scenario: Create task tool
- **WHEN** a client lists tools
- **THEN** `createTask` is listed with the required arguments `project_id` and `title`, and with `description`, `status_id` and the other body fields of the operation as optional arguments

#### Scenario: File downloads
- **WHEN** a client lists tools
- **THEN** no tool downloads a file

#### Scenario: Document changes
- **WHEN** an operation is added to or removed from the API document and the server is restarted
- **THEN** the tool list gains or loses the matching tool

### Requirement: Tool hints
Tools for GET operations SHALL be marked read-only. Tools for DELETE operations SHALL be marked destructive. All other tools SHALL be marked as neither read-only nor destructive. Every tool SHALL be marked as acting only within Goalner and not on the open world.

#### Scenario: Read tool
- **WHEN** a client lists tools
- **THEN** `listTasks` is marked read-only

#### Scenario: Deleting tool
- **WHEN** a client lists tools
- **THEN** `archiveTask` and `deleteComment` are marked destructive, and `createTask` is marked neither read-only nor destructive

### Requirement: Tool arguments
A tool call SHALL send only the arguments it was given. A body argument given as `null` SHALL be sent as `null`, and an omitted one SHALL NOT be sent. A call whose arguments do not match the tool's input schema SHALL return a tool error that names the offending arguments, without making an API request.

#### Scenario: Partial update
- **WHEN** a client calls `updateTask` with only a new title
- **THEN** the task's title changes and all its other fields keep their values

#### Scenario: Explicit null
- **WHEN** a client calls `setTaskSprint` with `sprint_id` set to `null`
- **THEN** the task is taken out of its sprint

#### Scenario: Task key as id
- **WHEN** a client calls `showTask` with the id `GOAL-12`
- **THEN** the result is task GOAL-12

#### Scenario: Missing required argument
- **WHEN** a client calls `createTask` without `title`
- **THEN** the result is a tool error naming `title`, and no API request is made

### Requirement: Tool results
A successful tool call SHALL return the API response body unchanged, as JSON text. A successful call whose API response has no body SHALL return a short confirmation.

#### Scenario: Show task
- **WHEN** a client calls `showTask` for a task of the token's project
- **THEN** the result contains the same fields and values as the API's response for that task

#### Scenario: No content
- **WHEN** a client calls `archiveTask` for a task of the token's project
- **THEN** the result is a confirmation and the task is archived

### Requirement: Tool errors
An API error response other than HTTP 401 SHALL become a tool error. The tool error SHALL carry the error envelope's code, message and per-field messages. An HTTP 401 from the API SHALL fail the MCP request with HTTP 401. When the API cannot be reached, times out or answers with a server error, the tool error SHALL carry a generic message that reveals no internal detail.

#### Scenario: Validation error
- **WHEN** a client calls `createLabel` with an empty name
- **THEN** the result is a tool error with the code `validation_failed` and a message for the field `name`

#### Scenario: API unavailable
- **WHEN** a client calls a tool while the API does not answer
- **THEN** the result is a tool error saying that Goalner is unavailable, with no host names, addresses or exception text

### Requirement: Browser origins
A request whose `Origin` header names a different origin than the application's own SHALL receive HTTP 403 and have no effect. Requests without an `Origin` header SHALL be processed.

#### Scenario: Foreign origin
- **WHEN** a web page on another origin makes a browser send a tool call with a valid token to `/mcp`
- **THEN** the response is HTTP 403 and nothing changes

#### Scenario: Native client
- **WHEN** a client that sends no `Origin` header calls a tool with a valid token
- **THEN** the call is processed

### Requirement: Privacy of MCP logs
For each request, the MCP server's logs and error reports SHALL record only the MCP method, the tool name, the API response status and the duration. They SHALL NOT contain token values, tool arguments or tool results.

#### Scenario: Logged tool call
- **WHEN** a client calls `createTask` with the title "Quarterly plan" and a valid token
- **THEN** the log line names `createTask` and the API status, and contains neither the token's value nor "Quarterly plan"

### Requirement: Isolation from the database
The MCP server SHALL run as a process separate from the main application. It SHALL have no database credentials and SHALL obtain every piece of Goalner data through the API.

#### Scenario: Started without a database
- **WHEN** the MCP server is started without any database configuration and a client calls `listProjects` with a valid token
- **THEN** the token's project is returned
