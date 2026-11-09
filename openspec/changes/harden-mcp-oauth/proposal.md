## Why

A code review of PR #29 (`add-mcp-oauth`) found 15 defects. Each was checked against the code on the `mcp-oauth` branch, and all 15 hold. Four of them break promises the specs make, or cut connections for no reason:
- an old refresh token keeps working when the new access token is only used to list tools;
- a wrong or rotating service key looks to every client like a dead token;
- rotating the signing key as the README says forces every connection to refresh;
- a client named after a long host fails every tool call with a 500.

The others leave unbounded outbound fetches, a disconnect that a refresh can undo, a redirect that IPv6 loopback clients can never complete, a flaky test, and clean-up gaps. All of them should be fixed before the OAuth work ships.

## What Changes

- **Refresh rotation finishes on any use.** The MCP server confirms a new access token with Goalner on its first request of any kind, not only on tool calls. Refreshing with the new refresh token also ends the refresh token before it. Both happen through the existing exchange and the token endpoint.
- **Refreshing and ending a connection cannot interleave.** The token endpoint and every path that ends connections take a lock on the user's row: disconnect, password change and the 90-day purge. A refresh in flight therefore either fails or has its token revoked.
- **The exchange tells a bad service key from a dead token.** Only `invalid_token` counts as refused. Any other 401 from the exchange makes the MCP server answer 503 "Goalner is unavailable", so clients do not refresh in a loop or send users back to sign-in.
- **The exchange accepts tokens signed with a previous key.** It finds the token by its digest, which already proves Goalner issued it, and checks only its claims. Key rotation as the README describes then causes no forced refresh.
- **Client names are cut to 100 characters** when they fall back to a host name, in both DCR and CIMD. Connection tokens cut theirs too.
- **CIMD fetches are bounded.** One URL is fetched at most once a minute, whether the fetch succeeds or fails. One user may cause at most 10 fetches an hour. Responses must not be compressed, and a compressed or corrupt body is refused like any other bad document.
- **IPv6 loopback redirect URIs are not supported.** DCR refuses them and CIMD documents ignore them, because the consent page's Content Security Policy cannot name them and the browser would block the redirect.
- **Housekeeping keeps the right rows.**
  - A DCR client that was ever authorized is never deleted as "unused".
  - Authorization codes that were never redeemed are deleted after 30 days.
- **Smaller fixes:**
  - Rails takes the issuer from `MCP_ISSUER`, as the MCP server does, instead of from the mailer host.
  - Tests never reach the network for CIMD documents.
  - The connections list reads only the columns it needs.
  - The MCP server builds its 401 challenges with the SDK's `Challenge`.
  - Read-only tools are decided by one predicate.

A second review of PR #29 asked to stop fetching URLs that clients name:
- **CIMD is paused.** The metadata no longer offers client ID metadata documents, so clients register dynamically, and a client id that is a URL gets the error page. The code and its tests stay, behind `config.x.oauth.client_metadata_documents`.
- **Smaller changes:**
  - the exchange moves to `POST /internal/mcp_token_exchange`;
  - `User#api_tokens` holds personal tokens, and `of_connections` replaces that condition;
  - one name limit serves client names and token names.

Not included:
- an MCP server that accepts several service keys at once. Rotating the service key still means a short outage for connections, now reported as 503 rather than as a dead token;
- refusing a revoked connection's tool list while its connection token is still cached (see design.md, "Risks / Trade-offs");
- refresh-token family revocation (ending every descendant when an old refresh token is replayed).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

`mcp-authorization` is introduced by `add-mcp-oauth` and is not yet in `openspec/specs/`. These deltas apply to it once that change is archived.

- `mcp-authorization`:
  - **Client ID metadata documents:** paused. Also, for when they return: fetch limits per URL and per user, compressed documents refused, IPv6 loopback entries ignored.
  - **Authorization server metadata:** `client_id_metadata_document_supported` is false.
  - **Dynamic client registration:**
    - IPv6 loopback redirect URIs are refused;
    - a host used as the name is cut to 100 characters;
    - authorized clients are kept.
  - **Refresh tokens:** the previous refresh token also stops working when the new refresh token is used, and when the new access token is used for any request, tool lists included.
  - **Connection lifetime:** a refresh in flight cannot outlive a disconnect or password change.
- `mcp-server`:
  - **Authentication:** Goalner refusing the MCP server's own service key, or being unreachable while it confirms a connection access token, answers 503, not 401.
  - **Protected resource metadata:** the challenge's parameters are no longer fixed to one order.
- `api-tokens`:
  - **Connection tokens:** the exchange accepts an access token signed with a previous signing key.

## Impact

- **Main application:**
  - `Internal::McpTokenExchangesController` and `Oauth::TokensController`;
  - `Oauth::JwtGenerator`, `Oauth::ClientMetadataDocument` and `Oauth::RegistrationsController`;
  - `Oauth.allowed_redirect_uri?`, `ApiToken.issue_for_connection!` and `McpConnection`;
  - `PurgeMcpConnectionsJob` and `config/initializers/doorkeeper.rb`;
  - one migration: `oauth_applications.first_authorized_at`.
- **MCP server:** `Authentication`, `ConnectionTokens`, `Credential`, `ToolCall`, `ScopedServer` and `ToolBuilder`. `Challenge` is removed.
- **Configuration:**
  - the web role gains `MCP_ISSUER` in `config/deploy.yml`, `RequiredSecrets` and `config/credentials.example.yml`;
  - the README's key rotation section changes.
- **Tests:**
  - test-wide stubs for the CIMD resolver and transport;
  - fixtures that look freshly fetched in every test;
  - new tests for each fix.
- **Depends on:** `add-mcp-oauth`, which must be archived first. Its `mcp-authorization`, `mcp-server` and `api-tokens` deltas define the requirements modified here.
