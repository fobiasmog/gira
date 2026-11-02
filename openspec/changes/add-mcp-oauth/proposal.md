# Proposal

## Why

`add-mcp-server` serves MCP with personal API tokens. That works in Claude Code and Cursor, where users paste a header. claude.ai on the web, Desktop and mobile only connect to MCP servers that sign users in with OAuth: per-user request headers are not available there. A token also reaches only one project, while an assistant is most useful across a user's work.

Users should be able to add Goalner as a connector in claude.ai, sign in, choose read-only or read-write access, and have the assistant work across all of their projects without ever seeing a token.

## What Changes

- **Goalner becomes an OAuth 2.1 authorization server for MCP clients**, built on Doorkeeper in the main application:
  - discovery metadata at `/.well-known/oauth-authorization-server`;
  - authorization code with PKCE (S256 only);
  - access tokens as JWTs signed with an asymmetric key, valid for 1 hour, for the resource `https://goalner.com/mcp` only;
  - refresh tokens that rotate on every use;
  - token revocation.
- **Clients register in either of two ways:**
  - **CIMD:** a Client ID Metadata Document, a client id that is an HTTPS URL Goalner fetches. Claude's apps and Claude Code use this;
  - **DCR:** Dynamic Client Registration at `/oauth/register`, which other clients use.

  Claude's callback URL and loopback redirects on any port, for both `localhost` and `127.0.0.1`, are supported.
- **Consent page.** A signed-in user, or one sent through sign-in and back, sees a consent page:
  - the client's name and, prominently, the host it will redirect to, with a warning when that is only a local address;
  - the statement that the client will reach all of their projects, including ones they join later;
  - a choice between read-only (the default) and read-write.

  No password is asked. The decision is the user's, made with an active session.
- **An MCP connection** (one user and one client) reaches every non-archived project the user belongs to, at the chosen access level, with every rule of the token API.
  - **It ends when:** the user disconnects it, changes or resets their password, or leaves it unused for 90 days.
  - **Leaving a project** narrows its reach instead of ending it.
- **The MCP server:**
  - accepts these access tokens next to personal tokens and verifies them with the public key;
  - publishes its protected resource metadata;
  - answers missing or expired tokens with 401 and a `WWW-Authenticate` pointer, so clients start sign-in or refresh;
  - lists only read tools to read-only connections.
- **Connection tokens.** To call the API, the MCP server exchanges a connection's access token for a short-lived connection token. The exchange goes through a private endpoint protected by a service key.
  - **Shape:** a connection token is an API token without a project, valid no longer than the access token.
  - **Storage:** the API stores only its digest, as for every token.
  - **Cache:** the MCP server keeps it in Redis, encrypted with a key derived from the access token, so a Redis dump alone is useless.
- **Settings → Connected apps** lists the user's connections: client, redirect host, access, connected and last active. Any of them can be disconnected.
- **Deployment:**
  - a Redis (Valkey) accessory;
  - the signing key and service key as secrets;
  - nginx routes `/.well-known/oauth-protected-resource*` to the MCP server and refuses `/internal/*` from outside.

Not included:
- choosing individual projects at consent. Every connection reaches all of the user's projects;
- listing Goalner in the Claude connector directory, and Anthropic-held client credentials;
- OpenID Connect (ID tokens, userinfo), the client credentials grant, and token introspection for third parties;
- OAuth access to `/api` directly. Connection access tokens are only accepted by the MCP server;
- an audit trail of what connections changed. Changes are attributed to the user, as with tokens.

## Capabilities

### New Capabilities

- `mcp-authorization`: OAuth for MCP clients. Covers:
  - discovery metadata;
  - client registration (CIMD and DCR);
  - the authorization request and consent;
  - access and refresh tokens;
  - what a connection reaches;
  - connection lifetime and revocation;
  - the connections list and disconnecting.

### Modified Capabilities

- `mcp-server`:
  - authentication accepts connection access tokens next to personal tokens;
  - the server publishes protected resource metadata and answers with an OAuth challenge;
  - tool calls act as the connection's user;
  - read-only connections see only read tools.
- `api-tokens`:
  - a new kind of token, the connection token: issued only to the MCP server, reaching all of the owner's projects;
  - project reach, the token list, the limits and the revocation rules are restated for personal tokens.
- `user-auth`: changing or resetting the password also ends every MCP connection.
- `web-client`:
  - the settings gain a Connected apps screen;
  - the password change warning mentions connected apps.
- `security-baseline`:
  - the OAuth endpoints and the internal exchange join the endpoints reachable without a session;
  - the consent page's Content Security Policy also allows form submissions to the redirect origin of the authorization being decided.

## Impact

- **Main application:**
  - Doorkeeper 5.9 (config, migrations, a controller subclass for authorize and token);
  - the CIMD fetcher, DCR, AS metadata, the JWT generator and the consent view;
  - `Internal::McpTokensController`;
  - `ApiToken` (`project_id` optional, `oauth_access_token_id`) and `Current#projects`;
  - the `User` password hook;
  - `Api::Me::ConnectionsController` and a purge job.
- **MCP server:**
  - JWT verification;
  - protected resource metadata;
  - the exchange client with an encrypted Redis cache;
  - scope-filtered tools.
- **Web client:** `ConnectedAppsSettingsPage.vue`, a settings tab and i18n.
- **Dependencies:** `doorkeeper` and `jwt` (main application); `jwt` and `redis` (`mcp` group).
- **Deployment:**
  - `config/deploy.yml` gains a Redis accessory and new secrets;
  - `config/credentials.example.yml` and `RequiredSecrets` gain the keys;
  - the README's nginx snippet changes.
- **Data:** new Doorkeeper tables; `api_tokens.project_id` becomes nullable, with a check constraint.
- **Depends on:**
  - `add-mcp-server`, which must be archived first;
  - `team-call`, which modifies the same Content Security Policy requirement and is expected to be archived first.
