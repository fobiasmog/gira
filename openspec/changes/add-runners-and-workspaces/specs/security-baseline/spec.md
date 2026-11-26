## MODIFIED Requirements

### Requirement: Cross-site request forgery protection
Every POST, PUT, PATCH and DELETE request authenticated by a session cookie SHALL carry a valid CSRF token, in a form field or in the `X-CSRF-Token` header. Requests without a valid token SHALL be rejected with HTTP 422 and SHALL have no effect. Requests that carry an API token (spec `api-tokens`) or a runner secret (spec `agent-runners`) SHALL NOT need a CSRF token and SHALL never be authenticated by their session cookie.

#### Scenario: Forged API request
- **WHEN** a third-party site makes a signed-in user's browser POST to an API endpoint without the token
- **THEN** the request is rejected with HTTP 422 and nothing changes

#### Scenario: Token request with a session cookie
- **WHEN** a request carries an API token that is not valid, a valid session cookie and no CSRF token, and tries to change data
- **THEN** the request is rejected with HTTP 401 and nothing changes

#### Scenario: Runner request without a CSRF token
- **WHEN** a runner leases an agent with its secret and no CSRF token
- **THEN** the lease is created

### Requirement: Deny by default
Every endpoint other than the landing page, authentication flows, invitation landing, health check, and the OAuth metadata, registration, token and revocation endpoints (spec `mcp-authorization`) SHALL require a signed-in user, a valid API token where spec `api-tokens` allows one, or a valid runner secret on the runner endpoints (spec `agent-runners`, "Runner authentication"). The internal token exchange SHALL require the MCP server's service key instead. API requests with neither SHALL receive HTTP 401 with a JSON error, not a redirect. Every record lookup SHALL be scoped to records the current user, narrowed by the API token if any, may access, or, for a runner, to its own leases and workspaces and the agents its owner can see, and every record id supplied by a client SHALL be checked against that scope before use.

#### Scenario: Signed-out API call
- **WHEN** a request without a session or API token calls an API endpoint
- **THEN** the response is HTTP 401 with a JSON error body

#### Scenario: Foreign id in a payload
- **WHEN** a client submits an id of a record from a project the user does not belong to as any field of a request
- **THEN** the request is rejected and nothing is changed

#### Scenario: Foreign id with a token
- **WHEN** a client using an API token for one project submits, as any field of a request, the id of a record from another project its owner belongs to
- **THEN** the request is rejected and nothing is changed

#### Scenario: Token endpoint without a session
- **WHEN** an MCP client without a session or CSRF token exchanges a valid authorization code at the token endpoint
- **THEN** it receives its tokens

#### Scenario: Internal exchange without the service key
- **WHEN** a request to the internal token exchange carries a valid connection access token but no service key, even with a signed-in session
- **THEN** the response is HTTP 401 and no token is issued

#### Scenario: Runner reaching for another runner's workspace
- **WHEN** a runner reports a checkpoint for a workspace that another runner of the same owner recorded
- **THEN** the response is HTTP 404 and nothing changes
