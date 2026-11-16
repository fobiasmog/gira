# Spec Delta

## MODIFIED Requirements

### Requirement: Deny by default
Every endpoint other than the landing page, authentication flows, invitation landing, health check, and the OAuth metadata, registration, token and revocation endpoints (spec `mcp-authorization`) SHALL require a signed-in user, or a valid API token where spec `api-tokens` allows one. The internal token exchange SHALL require the MCP server's service key instead. API requests with neither SHALL receive HTTP 401 with a JSON error, not a redirect. Every record lookup SHALL be scoped to records the current user, narrowed by the API token if any, may access, and every record id supplied by a client SHALL be checked against that scope before use.

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

### Requirement: Content Security Policy
Every HTML response SHALL carry a Content Security Policy that allows scripts, styles, fonts and frames only from the application's own origin, allows images only from the own origin plus `data:` and `blob:`, allows network connections only to the own origin, the configured error-tracking ingest host and the configured media server (its WebSocket and HTTP addresses), allows form submissions only to the own origin, forbids plugins (`object-src 'none'`), restricts `base-uri` to the own origin, and forbids framing (`frame-ancestors 'none'`). On the OAuth consent page only, form submissions SHALL also be allowed to the origin of the redirect URI of the authorization the page shows, and to no other. The policy SHALL NOT contain `'unsafe-inline'` or `'unsafe-eval'` for scripts. In development only, the policy SHALL additionally allow the local frontend dev server origin (HTTP and WebSocket) and a per-request nonce for `style-src`, exposed to the page so the dev server can inject stylesheets, and nothing else.

#### Scenario: Production policy has no dev server
- **WHEN** an HTML page is requested in production
- **THEN** the policy does not mention any localhost origin and carries no nonce

#### Scenario: Development styles from the dev server
- **WHEN** a page of the client is requested in development
- **THEN** its `style-src` carries a nonce generated for that response, and the stylesheets the dev server injects with that nonce are applied

#### Scenario: Injected inline script
- **WHEN** a page somehow contains an inline `<script>` or an `onerror=` attribute
- **THEN** the browser refuses to execute it because of the policy

#### Scenario: Header present
- **WHEN** any HTML page is requested
- **THEN** the response includes the policy with `script-src 'self'`, `form-action 'self'` and `frame-ancestors 'none'`

#### Scenario: Media server in the policy
- **WHEN** a media server is configured and any HTML page is requested
- **THEN** the policy's `connect-src` contains the media server's WebSocket and HTTP addresses, and no other host besides the own origin and the error-tracking ingest host (plus the dev server in development)

#### Scenario: No media server configured
- **WHEN** no media server is configured and any HTML page is requested
- **THEN** the policy's `connect-src` contains only the own origin and the error-tracking ingest host (plus the dev server in development)

#### Scenario: Consent page form action
- **WHEN** a signed-in user opens the consent page of an authorization whose redirect URI is `https://claude.ai/api/mcp/auth_callback`
- **THEN** the page's `form-action` is `'self' https://claude.ai`, and every other page's `form-action` is still `'self'` alone

#### Scenario: Consent redirect in the browser
- **WHEN** a user approves or denies on the consent page in a browser that enforces `form-action` on redirects
- **THEN** the browser follows the redirect to the client, with no CSP violation
