# mcp-authorization Specification

## Purpose
Lets users connect MCP clients such as claude.ai to Goalner by signing in and consenting, instead of handling tokens. Covers client registration, the OAuth flow, what a connection may reach, and how connections end.

## Requirements

### Requirement: Authorization server metadata
`/.well-known/oauth-authorization-server` SHALL publish OAuth authorization server metadata. It SHALL contain:
- the issuer (the application's origin);
- the authorization, token, registration and revocation endpoints;
- response type `code`;
- the grant types `authorization_code` and `refresh_token`;
- `S256` as the only code challenge method;
- `none` as the token endpoint authentication method;
- the scopes `read` and `write`;
- `client_id_metadata_document_supported` set to false while client ID metadata documents are paused, so that clients register dynamically.

#### Scenario: Metadata
- **WHEN** a client requests `/.well-known/oauth-authorization-server`
- **THEN** the JSON contains the issuer `https://goalner.com`, the four endpoints, `code_challenge_methods_supported` equal to `["S256"]`, `token_endpoint_auth_methods_supported` containing `none`, and `client_id_metadata_document_supported` set to false

### Requirement: Client ID metadata documents
A client whose client id is an HTTPS URL SHALL be identified by the JSON document at that URL. The document SHALL be accepted only when its `client_id` equals the URL, it lists the requested redirect URI, and it asks for no client secret. Goalner SHALL fetch it only over HTTPS from a public address, within a size limit and a timeout, and SHALL NOT follow redirects.

#### Scenario: Claude Code
- **WHEN** Claude Code starts an authorization with the client id `https://claude.ai/oauth/claude-code-client-metadata` and a loopback redirect URI that the document lists
- **THEN** the consent page names the client as its document does

#### Scenario: Mismatched client id
- **WHEN** the document at a client id URL declares a different `client_id`
- **THEN** an error page is shown, the browser is not redirected, and no authorization is possible

#### Scenario: Private address
- **WHEN** a client id URL's host resolves to a private or loopback address
- **THEN** an error page is shown and no request is made to that address

#### Scenario: Unlisted redirect URI
- **WHEN** an authorization request uses a redirect URI that the client's document does not list
- **THEN** an error page is shown and the browser is not redirected

### Requirement: Dynamic client registration
`POST /oauth/register` SHALL register a public client from a JSON body with a client name and redirect URIs, and SHALL return its client id. Redirect URIs SHALL use HTTPS, or HTTP on `localhost` or an IPv4 loopback address. A client registered without a name SHALL be named after the host of its first redirect URI, cut to 100 characters. Each IP address SHALL be limited to 20 registrations an hour. A registered client that has no authorization within 24 hours SHALL be deleted. A client that was authorized at least once SHALL NOT be deleted for lack of use.

#### Scenario: Registration
- **WHEN** a client registers with the name "Cursor" and the redirect URI `http://127.0.0.1/callback`
- **THEN** the response is HTTP 201 with a client id and `token_endpoint_auth_method` `none`

#### Scenario: Plain HTTP redirect
- **WHEN** a client registers with the redirect URI `http://example.com/callback`
- **THEN** the response is HTTP 400 with the error `invalid_redirect_uri` and nothing is registered

#### Scenario: Registration burst
- **WHEN** one IP address sends a 21st registration within an hour
- **THEN** the response is HTTP 429 and nothing is registered

#### Scenario: Unused client
- **WHEN** 24 hours pass after a registration without any authorization for that client
- **THEN** the client is deleted

#### Scenario: Name from a long host
- **WHEN** a client registers without a name and with a redirect URI whose host has 130 characters, a user connects it, and it calls a tool
- **THEN** the client's name is the first 100 characters of that host, and the tool call succeeds

#### Scenario: Authorized client kept
- **WHEN** a user connects a dynamically registered client, disconnects it, and 60 days later starts an authorization with the same client id
- **THEN** the consent page is shown

### Requirement: Authorization requests
An authorization request SHALL be accepted only when all of the following hold:
- the response type is `code`;
- it carries an S256 PKCE challenge;
- its redirect URI is registered for the client. A loopback redirect URI matches on any port, for both `localhost` and `127.0.0.1`;
- any `resource` it names is `https://goalner.com/mcp`.

A refused request SHALL be answered with an error at the redirect URI when that URI is registered for the client, and with an error page otherwise.

#### Scenario: Missing PKCE
- **WHEN** a registered client starts an authorization without a code challenge
- **THEN** the browser is redirected to the client's redirect URI with the error `invalid_request`

#### Scenario: Plain challenge
- **WHEN** a client uses the code challenge method `plain`
- **THEN** the request is refused with `invalid_request`

#### Scenario: Loopback on any port
- **WHEN** Claude Code starts an authorization with the redirect URI `http://localhost:51234/callback`, while its document lists `http://localhost/callback`
- **THEN** the consent page is shown

#### Scenario: Other resource
- **WHEN** an authorization request names the resource `https://other.example/mcp`
- **THEN** the browser is redirected to the client with the error `invalid_target`

### Requirement: Sign-in before consent
A visitor without a session who opens an authorization request SHALL be sent to sign-in, and SHALL be brought back to the same authorization request after signing in.

#### Scenario: Signed out
- **WHEN** a visitor who is not signed in follows claude.ai's authorization link and signs in
- **THEN** they see the consent page for that request

### Requirement: Consent page
The consent page SHALL show the client's name and, more prominently, the host of its redirect URI. It SHALL state that the client will reach all of the user's projects, including projects they join later. It SHALL offer read-only access, preselected, and read-write access when the client asked for the `write` scope. When every redirect URI of the client is a loopback address, the page SHALL warn that only an app on this device will receive access. It SHALL NOT ask for a password.

#### Scenario: claude.ai
- **WHEN** a signed-in user opens an authorization request from claude.ai asking for `read write`
- **THEN** the page shows the host `claude.ai`, the client's name, the all-projects statement, and read-only preselected with read-write available

#### Scenario: Loopback client
- **WHEN** a signed-in user opens an authorization request from a client whose only redirect URIs are loopback addresses
- **THEN** the page shows the warning about an app on this device

#### Scenario: Read scope only
- **WHEN** a client asks only for the `read` scope
- **THEN** the page offers no read-write option

### Requirement: Consent decision
Approving SHALL redirect to the client with an authorization code bound to the user, the client, the PKCE challenge and the chosen access. The code SHALL be usable once, within 10 minutes. Denying SHALL redirect to the client with the error `access_denied` and SHALL create nothing.

#### Scenario: Approve read-only
- **WHEN** a user approves read-only access and the client exchanges the code
- **THEN** the issued access token carries only the `read` scope

#### Scenario: Deny
- **WHEN** a user denies the request
- **THEN** the browser is redirected to the client with `access_denied`, and no connection appears in the user's connected apps

#### Scenario: Code reused
- **WHEN** a client exchanges the same authorization code a second time
- **THEN** the token endpoint answers `invalid_grant`

### Requirement: Access tokens
The token endpoint SHALL exchange an authorization code and its PKCE verifier for an access token and a refresh token. It SHALL accept form-encoded requests from public clients without a secret. Access tokens SHALL be JWTs signed with an asymmetric key. Each SHALL name the issuer, the user, the client, the granted scope and the audience `https://goalner.com/mcp`, and SHALL expire 1 hour after issue. They SHALL authenticate only at the MCP server.

#### Scenario: Code exchange
- **WHEN** a client exchanges a valid code with its verifier
- **THEN** it receives an access token whose audience is `https://goalner.com/mcp` and which expires in 1 hour, and a refresh token

#### Scenario: Wrong verifier
- **WHEN** a client exchanges a code with a verifier that does not match its challenge
- **THEN** the token endpoint answers `invalid_grant` and issues nothing

#### Scenario: Access token at the API
- **WHEN** a client sends a valid connection access token as a Bearer token to `/api/me`
- **THEN** the response is HTTP 401

### Requirement: Refresh tokens
Refreshing SHALL return a new access token and a new refresh token with the same scope. The previous refresh token SHALL stop working no later than the first of these:
- the first request to the MCP server made with the new access token, of any kind, including requests that only list tools;
- the first use of the new refresh token.

A refresh token that stopped working, or whose connection ended, SHALL receive `invalid_grant`.

#### Scenario: Refresh
- **WHEN** a client refreshes with a valid refresh token
- **THEN** it receives a new access token with the same scope and a new refresh token

#### Scenario: Old refresh token
- **WHEN** a client uses a new access token and then refreshes with the refresh token it replaced
- **THEN** the token endpoint answers `invalid_grant`

#### Scenario: Old refresh token after listing tools
- **WHEN** a client refreshes, lists tools with the new access token without calling any tool, and then refreshes with the refresh token it replaced
- **THEN** the token endpoint answers `invalid_grant`

#### Scenario: Old refresh token after the next refresh
- **WHEN** a client refreshes twice without using either new access token, and then refreshes with the first refresh token
- **THEN** the token endpoint answers `invalid_grant`

### Requirement: Connection reach
An MCP connection SHALL reach every non-archived project its user is a member of, including projects joined after connecting, with the access level chosen at consent. Every rule of spec `api-tokens` on allowed endpoints, access level, rate limit and attribution SHALL apply to it as to a token.

#### Scenario: Project joined later
- **WHEN** a user with a connection accepts an invitation to TEST and the client then lists projects through the MCP server
- **THEN** TEST is listed

#### Scenario: Project left
- **WHEN** a user with a connection leaves TEST and the client then lists TEST's tasks
- **THEN** the result is a tool error with the code `not_found`, and the connection keeps working for the user's other projects

#### Scenario: Project administration
- **WHEN** a read-write connection tries to archive a project or invite a member through any tool or request
- **THEN** no such tool exists, and the API refuses such requests with HTTP 403

### Requirement: Connection lifetime
A connection SHALL end, and every token issued for it SHALL stop working, when one of these happens:
- the user disconnects it;
- the user's password is changed or reset;
- it has not been used for 90 days.

An ended connection SHALL NOT work again. The client has to ask for authorization anew. This SHALL also hold for a refresh or code exchange that is in progress when the connection ends: either it fails, or the tokens it returns do not work.

#### Scenario: Disconnected
- **WHEN** a user disconnects claude.ai and claude.ai then calls a tool and tries to refresh
- **THEN** the tool call receives HTTP 401 and the refresh receives `invalid_grant`

#### Scenario: Password changed
- **WHEN** a user with two connections changes their password
- **THEN** both connections end

#### Scenario: Unused
- **WHEN** a connection has not been used for 90 days
- **THEN** it ends and no longer appears in the user's connected apps

#### Scenario: Disconnected during a refresh
- **WHEN** a user disconnects claude.ai while a refresh request from claude.ai is being processed
- **THEN** either the refresh answers `invalid_grant`, or the access and refresh tokens it returns are refused at their first use, and the connection no longer appears in the user's connected apps

### Requirement: Token revocation endpoint
A client SHALL be able to revoke its own access or refresh token at the revocation endpoint, after which the token SHALL stop working.

#### Scenario: Client revokes
- **WHEN** a client revokes its refresh token
- **THEN** refreshing with it receives `invalid_grant`

### Requirement: Connected apps
A signed-in user SHALL be able to list their connections and disconnect any of them. Each connection SHALL show the client's name, its redirect host, the access level, when it was connected, and when it was last active to within one hour. A user SHALL NOT be able to see or disconnect another user's connections. These endpoints SHALL NOT be open to API tokens or connections.

#### Scenario: List
- **WHEN** a user who connected claude.ai read-write lists their connections
- **THEN** the list shows claude.ai's client name, the host `claude.ai`, read-write, and the connection and last-active times

#### Scenario: Another user's connection
- **WHEN** a user asks to disconnect a connection id that belongs to another user
- **THEN** the response is HTTP 404 and the connection keeps working

#### Scenario: Token request
- **WHEN** an API token requests the connections list
- **THEN** the response is HTTP 403

### Requirement: Client metadata document fetches
Goalner SHALL fetch one client ID metadata document URL at most once a minute, whether the fetch succeeds or fails. It SHALL fetch at most 10 documents an hour on behalf of one user. It SHALL ask for an uncompressed document and SHALL refuse a compressed one. An authorization request that needs a fetch beyond these limits SHALL get the error page, without any request to the URL.

#### Scenario: Unreachable document
- **WHEN** a signed-in user opens two authorization requests within a minute for a client id URL whose host does not answer
- **THEN** both show an error page, the browser is not redirected, and Goalner tries to reach that host once

#### Scenario: Many documents
- **WHEN** one user opens authorization requests for 11 different client id URLs, none stored yet, within an hour
- **THEN** the 11th shows an error page and no request is made to its URL

#### Scenario: Compressed document
- **WHEN** the document at a client id URL is served gzip-compressed
- **THEN** an error page is shown and the browser is not redirected

### Requirement: No IPv6 loopback redirect URIs
A redirect URI on an IPv6 loopback address, such as `http://[::1]:8080/callback`, SHALL NOT be usable. Dynamic registration SHALL refuse it. A client ID metadata document that lists one SHALL be accepted without it, as long as the document lists another valid redirect URI. An authorization request that names one SHALL get the error page.

#### Scenario: Registration with an IPv6 loopback URI
- **WHEN** a client registers with the redirect URI `http://[::1]:8080/callback`
- **THEN** the response is HTTP 400 with the error `invalid_redirect_uri` and nothing is registered

#### Scenario: Document with an IPv6 loopback URI
- **WHEN** a client's document lists `http://127.0.0.1/callback` and `http://[::1]/callback`, and authorization requests use `http://127.0.0.1:8080/callback` and `http://[::1]:8080/callback`
- **THEN** the first shows the consent page, and the second shows an error page without redirecting the browser

### Requirement: Client ID metadata documents paused
Goalner SHALL NOT fetch client ID metadata documents until a later change turns them back on. An authorization request whose client id is an HTTPS URL SHALL get the error page with `invalid_client`, without a request to the URL and without a redirect, even when a document for that URL was stored earlier. Clients SHALL register dynamically instead. While documents are paused, the requirements "Client ID metadata documents" and "Client metadata document fetches" describe the code kept for that later change, not the running service.

#### Scenario: Document URL while paused
- **WHEN** a signed-in user opens an authorization request whose client id is `https://inspector.example/oauth/metadata`
- **THEN** an error page with `invalid_client` is shown, the browser is not redirected, and no request is made to that URL

#### Scenario: Stored document client while paused
- **WHEN** a signed-in user opens an authorization request for a client stored from a metadata document before the pause, and then approves the same request
- **THEN** both show an error page, and no code is issued

#### Scenario: Registered client while paused
- **WHEN** a signed-in user opens an authorization request for a dynamically registered client
- **THEN** the consent page is shown
