## ADDED Requirements

### Requirement: Agent tokens at the MCP endpoint
An agent token issued for the MCP channel (spec `agents`) SHALL authenticate at `/mcp` as a personal API token does. Tool calls made with it SHALL act as the agent within the projects the token reaches. An agent token issued for the API only SHALL receive HTTP 401 at `/mcp`, including for tool lists. Every request the MCP server makes to the API SHALL carry the MCP server's service key, so that the API can tell requests made through MCP from direct ones. The service key SHALL NOT authenticate a request by itself.

When the API refuses the MCP server's own service key, the request SHALL NOT be answered as if the token were invalid:
- a request that the MCP server has yet to authenticate SHALL receive HTTP 503 with a generic message that reveals no internal detail;
- a tool call SHALL return a tool error saying that Goalner is unavailable.

#### Scenario: MCP token
- **WHEN** a client calls `createTask` at `/mcp` with a read-write MCP token of agent Fish
- **THEN** the task is created and its creator is Fish

#### Scenario: API-only token
- **WHEN** a client lists tools at `/mcp` with an API-only token of agent Fish
- **THEN** the response is HTTP 401 with a `WWW-Authenticate: Bearer` header, and no tools are listed

#### Scenario: Personal tokens unchanged
- **WHEN** a client lists tools at `/mcp` with a valid personal API token
- **THEN** the tools are listed

#### Scenario: Service key alone
- **WHEN** a request to the API carries the MCP server's service key and no token
- **THEN** the response is HTTP 401

#### Scenario: Service key refused
- **WHEN** the API refuses the MCP server's service key, and a client lists tools with a valid MCP-only agent token that the MCP server has not seen before
- **THEN** the response is HTTP 503 with a message that Goalner is unavailable, and it carries no `error="invalid_token"`

#### Scenario: Service key refused during a tool call
- **WHEN** the API starts refusing the MCP server's service key after a client has listed tools with a valid MCP-only agent token, and the client then calls a tool
- **THEN** the result is a tool error saying that Goalner is unavailable, and the request is not answered with HTTP 401
