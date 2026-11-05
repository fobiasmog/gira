# Spec Delta

## ADDED Requirements

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

## MODIFIED Requirements

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
