# Spec Delta

## MODIFIED Requirements

### Requirement: Authentication
Every request to `/mcp` SHALL carry, in the header `Authorization: Bearer <token>`, either a personal API token (spec `api-tokens`) or an access token of an MCP connection (spec `mcp-authorization`). A request with no such token, or with one that is malformed, expired, revoked, issued for another audience, or rejected by the API, SHALL receive HTTP 401 and no MCP result. This includes requests that only list tools. A token sent in the URL or the request body SHALL NOT authenticate.

A connection access token SHALL be confirmed with Goalner before the MCP server first answers a request made with it, whatever the request. When Goalner cannot be reached to confirm it, or refuses the MCP server's own service key, the request SHALL receive HTTP 503 with a generic message that reveals no internal detail. It SHALL NOT be answered as if the token were invalid.

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

#### Scenario: Connection access token
- **WHEN** claude.ai lists tools with a valid access token of the user's connection
- **THEN** the tools are listed

#### Scenario: Expired access token
- **WHEN** a client sends an access token whose expiry has passed
- **THEN** the response is HTTP 401 with `error="invalid_token"` in the `WWW-Authenticate` header

#### Scenario: Token for another audience
- **WHEN** a client sends a JWT signed by Goalner's key whose audience is not `https://goalner.com/mcp`
- **THEN** the response is HTTP 401

#### Scenario: Connection ended between calls
- **WHEN** a user disconnects claude.ai while its access token has not yet expired, and claude.ai then calls a tool
- **THEN** the response is HTTP 401 and nothing changes

#### Scenario: Ended connection, new access token
- **WHEN** a client lists tools with an access token that the MCP server has not seen before, of a connection that has ended
- **THEN** the response is HTTP 401 with `error="invalid_token"` in the `WWW-Authenticate` header

#### Scenario: Service key refused
- **WHEN** Goalner refuses the MCP server's service key, and a client sends a request with a valid connection access token the MCP server has not seen before
- **THEN** the response is HTTP 503 with a message that Goalner is unavailable, and it carries no `error="invalid_token"`

### Requirement: Protected resource metadata
The MCP server SHALL publish OAuth protected resource metadata at `/.well-known/oauth-protected-resource` and at `/.well-known/oauth-protected-resource/mcp`. The metadata SHALL name the resource `https://goalner.com/mcp`, Goalner as its only authorization server, the scopes `read` and `write`, and the `Authorization` header as the only way to send tokens. Every HTTP 401 from `/mcp` SHALL point to this metadata in its `WWW-Authenticate` header and name the scopes `read write`.

#### Scenario: Metadata
- **WHEN** a client requests `/.well-known/oauth-protected-resource/mcp`
- **THEN** the JSON names the resource `https://goalner.com/mcp` and the authorization server `https://goalner.com`

#### Scenario: Challenge
- **WHEN** a client sends a request to `/mcp` without a token
- **THEN** the HTTP 401 carries a `WWW-Authenticate: Bearer` challenge with the parameters `resource_metadata="https://goalner.com/.well-known/oauth-protected-resource/mcp"` and `scope="read write"`, in either order, and no `error` parameter
