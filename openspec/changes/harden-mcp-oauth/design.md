# Design

## Context

- **Where this lands.** `add-mcp-oauth` is implemented on the `mcp-oauth` branch (PR #29), with tasks 5.3, 7.2, 8.1 and 8.2 still open. Nothing of it is deployed. This change fixes the review findings listed in proposal.md, on top of that code. Decisions below refer to `add-mcp-oauth` design.md as "the OAuth design".
- **Refresh rotation today.** Doorkeeper 5.9.9 picks revoke-on-use because `oauth_access_tokens` has a `previous_refresh_token` column:
  - a refresh does not revoke the old row; it records the old refresh token on the new row;
  - Doorkeeper revokes the old row only when the new access token is used through its own `Doorkeeper::OAuth::Token.authenticate`, which Goalner never calls;
  - Goalner calls `revoke_previous_refresh_token!` itself, in `Internal::McpTokenExchangesController`. The MCP server reaches that only on `tools/call`, through `ToolCall#upstream_token`.

  On this path, Doorkeeper's refresh takes no lock (`RefreshTokenRequest#before_successful_response`).
- **Ending connections today.** `McpConnection.revoke` deletes connection tokens and runs `UPDATE … SET revoked_at` on the user's tokens and grants. Its callers are disconnect, `end_all_for` (from `User`'s `after_update_commit` on the password) and `PurgeMcpConnectionsJob#end_unused_connections`. Under Postgres READ COMMITTED, that `UPDATE` does not see a token row that another transaction inserts after the statement began.
- **The exchange today:**
  - a 401 from `/internal/mcp_token_exchange` means either `invalid_service_key` or `invalid_token`, and `ConnectionTokens#exchange` treats both as `Refused`;
  - it also calls `Oauth::JwtGenerator.decode`, which verifies the signature with the current private key only.
- **CIMD fetches today.** `Oauth::ClientMetadataDocument#resolve` fetches whenever no stored copy is reusable. Nothing records a failed or refused fetch. `Net::HTTP` asks for gzip by default and inflates transparently.
- **Caches.** `Rails.cache` is Solid Cache in production and `:memory_store` in development and test.
- **Deployment.** Both roles read the same top-level `env.clear` in `config/deploy.yml`, plus their own role env. `MCP_ISSUER` is set only on the `mcp` role. Rails builds its issuer from `credentials.mailer.host`.

## Goals / Non-Goals

**Goals:**
- Every fix comes with a test that fails on the current branch.
- No new tables, services or gems. One nullable column.
- The OAuth design's goals still hold. The API remains the only enforcer, the MCP process gains no power of its own, and nothing that authenticates is stored readable.

**Non-Goals:**
- Changing Doorkeeper's refresh mode (decision 1 explains why).
- Several live service keys, or zero-downtime service key rotation.
- Closing the cached tool list gap after a disconnect (see "Risks / Trade-offs").

## Decisions

### 1. Rotation completes on the first request of any kind, and on the next refresh

**MCP server.** `Authentication` confirms a connection credential with Goalner before handing the request to the transport, by calling `UpstreamCredential.for(credential)`.
- **Cache hit.** On a hit, nothing goes over the network. A hit proves that this access token was already exchanged, so the previous refresh token is already revoked.
- **Memoized per request.** The result is stored on the credential (`Credential#upstream_token`). `ToolCall` uses it and never exchanges a second time in the same request.
- **Failures:**
  - `Refused` answers 401 `invalid_token`;
  - `ApiClient::Unavailable` answers 503, through `Authentication`'s existing rescue;
  - `RateLimited` lets the request through with the failure memoized. A tool call then returns the `rate_limited` tool error as today, and `initialize` and `tools/list` still work.

Personal tokens are unaffected.

**Token endpoint.** When a refresh token is presented, `Oauth::TokensController` calls `revoke_previous_refresh_token!` on that token's row before Doorkeeper handles the request, inside decision 2's lock. Using refresh token B proves the client received B, so A's refresh token can end. Without this, a client that refreshes twice without using an access token leaves A's refresh token alive for good.

Together, these meet the spec's "first request of any kind, or the first use of the new refresh token".

Alternatives:
- *Immediate revocation*: drop `previous_refresh_token`, so that Doorkeeper revokes the old row at refresh time under a row lock. Rejected. A lost refresh response, or two refreshes of one connection in parallel (claude.ai's workers can do that), would end the connection and force sign-in. Doorkeeper's revoke-on-use mode exists to avoid this.
- *Only the token endpoint part.* Rejected. A's refresh token would stay alive for as long as the client keeps using B for tool lists, which breaks the spec.
- *A separate "touch" endpoint instead of the exchange.* Rejected. It costs the same round trip and adds a second internal endpoint. The exchange already looks the token up, revokes the previous refresh token and is rate limited.

### 2. Token issuance and connection ending serialize on the user's row

Both sides lock the user's row first: `User.lock.find(id)`, which is `SELECT … FOR UPDATE`.

**Issuance.** `Oauth::TokensController#create`, for the `authorization_code` and `refresh_token` grants:
1. Find the owner of the presented code or refresh token by digest, with `Oauth::AccessGrant.by_token` or `Oauth::AccessToken.by_refresh_token`.
2. In one transaction, lock that user and call `revoke_previous_refresh_token!` (decision 1). Then run `super`.

Doorkeeper loads the grant or refresh token after the lock is held. Its own checks therefore see any revocation committed before the lock: `validate_token`, the grant's `lock!` and `revoked?`. A request with an unknown code or token skips the lock, and Doorkeeper refuses it as today.

**Ending.** `McpConnection.revoke` takes the user and locks the row before its `delete_all` and `update_all`. If a refresh committed first, the `UPDATE`, run after the lock, sees the new row and revokes it. If the revoke committed first, the refresh reads a revoked token and answers `invalid_grant`. Every caller passes the user: disconnect, `end_all_for` and the 90-day purge.

**Ordering.** Both paths lock the user row first and token rows after, so they cannot deadlock. The password hook runs after its own commit, so the user row is free by then.

Alternatives:
- *Lock the old token row.* Rejected. The ending `UPDATE` still misses a row inserted after it started.
- *An after-commit check on new tokens that revokes them when their predecessor is revoked.* Rejected. It is still racy: both transactions can read each other's state from before commit.
- *A Postgres advisory lock keyed on (user, application).* Rejected. A password change would have to take one lock per application. Locking the user row covers all of them, and refreshes are about hourly per connection, so contention is negligible.

### 3. The MCP server tells a dead token from a refused service key

`ConnectionTokens#exchange` reads the body of a 401:
- `{"error":"invalid_token"}` raises `Refused`, as today;
- any other 401 (`invalid_service_key`, an empty body, or a proxy's page) is logged as "the exchange refused the MCP server's credentials" and raises `ApiClient::Unavailable`. With decision 1, the client gets 503 and keeps its tokens.

Rails is unchanged: the api-tokens scenario "Wrong service key" still answers 401.

Alternative: *Rails answers 403 for a bad service key.* Rejected. It changes a specified status, and the MCP side would still need to stop treating every 401 as `invalid_token`. Keying on the error code is the part that makes it robust.

### 4. The exchange checks claims, not the signature

`Internal::McpTokenExchangesController` already requires `Oauth::AccessToken.by_token(value)` to find a live row. Because the database stores only digests, that lookup proves Goalner issued this exact token. The extra signature check only breaks key rotation.

`Oauth::JwtGenerator.decode` is replaced with `Oauth::JwtGenerator.claims(token)`. It decodes without verifying the signature (`JWT.decode(token, nil, false)`) and returns the claims only when `iss` equals `Oauth.issuer` and `aud` equals `Oauth.resource`. The `oauth_flow_test` assertions that use `decode` move to the public-key helper `decode_access_token`.

Alternative: *verify against the current and previous private keys, kept in the credentials.* Rejected. It puts more key material on the web role and adds a second rotation list, for a check the database already makes.

### 5. Names fall back to at most 100 characters

When a client gives no name, these fallbacks keep the first 100 characters of the host:
- `Oauth::RegistrationsController#client_name` (DCR);
- `Oauth::ClientMetadataDocument#client_name` (CIMD).

`ApiToken.issue_for_connection!` also cuts the application's name to 100 characters, so a stored application with a longer name can never make the exchange raise. A name the client does give still has to be at most 100 characters, as the OAuth design specifies.

### 6. CIMD fetches are bounded, and only uncompressed

`ClientMetadataDocument.resolve(url, redirect_uri:, user:)` gains the requesting user. The controller passes `Current.user`, which is always present because sign-in runs first.

Before any fetch, in this order:
1. **Per user.** `Rails.cache.increment("oauth/cimd/user/#{user.id}", 1, expires_in: 1.hour)`. Above 10, it raises `Error`.
2. **Per URL.** `Rails.cache.increment("oauth/cimd/url/#{sha256(url)}", 1, expires_in: 1.minute)`. Above 1, it raises `Error`.

A refused attempt still counts toward the user's 10. `reusable?` is unchanged, so a copy fetched within the minute is reused without touching the counters. `Rails.cache` errors are not rescued. Solid Cache is the same database the request already needs.

The transport sends `Accept-Encoding: identity`, which also turns off `Net::HTTP`'s transparent inflation. A response with a `Content-Encoding` other than `identity` is refused. `Zlib::Error` joins the rescued errors as a backstop.

Alternatives:
- *Record failed fetches in `oauth_applications`.* Rejected. Unstored URLs have no row, and inserting rows for arbitrary URLs would let anyone grow the table.
- *A per-IP `rate_limit` on `/oauth/authorize`.* Rejected. It would also count ordinary consent page views. The per-user limit counts only real fetches.

### 7. IPv6 loopback redirect URIs are refused

CSP host sources cannot express an IPv6 literal. Chrome drops `http://[::1]:8080` from `form-action`, and would then block the consent redirect.

- `Oauth.allowed_redirect_uri?` returns false for a bracketed host. DCR refuses such a URI through its existing check.
- `ClientMetadataDocument#redirect_uris` removes IPv6 loopback entries first. The rest must be non-empty and valid, as today. The stored client never lists them, so an authorization request that names one fails Doorkeeper's redirect check and gets the error page.

Alternatives:
- *Allow the scheme source `http:` in `form-action` for those responses.* Rejected. It widens the consent page's policy beyond "the redirect origin and no other" (spec security-baseline, whose requirement `team-call` also modifies). No MCP client is known to need IPv6 loopback, and Claude Code uses `localhost` and `127.0.0.1`.
- *A link or meta-refresh page.* Rejected for the same reasons as in OAuth design decision 6.

### 8. Housekeeping keeps authorized clients, and purges stale codes

- **Migration.** `oauth_applications.first_authorized_at` (datetime, nullable). It is backfilled from the earliest grant or access token of each application.
- **Setting it.** `Oauth::AccessGrant` has an `after_create` that sets it when it is still null, with a single `UPDATE … WHERE first_authorized_at IS NULL`. A consent approval is an authorization, whether or not the code is ever redeemed.
- **`delete_unauthorized_clients`** deletes DCR applications with `first_authorized_at IS NULL` that were created more than 24 hours ago. The grant and token subqueries go away.
- **`delete_revoked`** also deletes grants created more than 30 days ago, revoked or not. Codes live for 10 minutes, so these are only unredeemed leftovers.

Alternative: *infer "ever authorized" from existing grants and tokens.* Rejected. They are purged after 30 days, which is the bug.

### 9. One issuer setting for both roles

- **Rails** reads `config.x.oauth.issuer` from `MCP_ISSUER`, as it already reads `MCP_RESOURCE_URL`. Development and test keep their current defaults. Production requires the variable: it joins `RequiredSecrets::ENV_KEYS`.
- **`config/deploy.yml`.** `MCP_ISSUER` and `MCP_RESOURCE_URL` move from the role envs to the top-level `env.clear`, so both roles read one definition.
- **`config/credentials.example.yml`** documents the variable.

Alternative: *keep the mailer host and compare the two at boot.* Rejected. The web role cannot see the `mcp` role's environment.

### 10. Tests never reach the network

- **`test/test_helper.rb`** sets the default `Oauth::ClientMetadataDocument.resolver` and `.transport` to stand-ins that raise "network access in tests". The model test already saves and restores its own stubs.
- **`OauthTestHelper`** gains a `setup` that marks the CIMD fixtures as just fetched: `Oauth::Application.cimd.update_all(metadata_fetched_at: Time.current)`. The transaction rolls it back after each test.
- **Fixture comment.** The ERB timestamp in `test/fixtures/oauth/applications.yml` stays, with a comment pointing to the hook.
- **Rate limit counters.** Tests that exercise them clear `Rails.cache` in their own `setup`.

### 11. Smaller cleanups

- **Connections list.** `McpConnection.for` plucks `application_id`, `created_at`, `revoked_at` and `scopes` instead of instantiating every row. `McpConnection.find` queries only the requested application.
- **Challenges.** `GoalnerMcp::Challenge` is removed. `Authentication` takes `resource_metadata_url:` and calls `MCP::Server::OAuth::Challenge.missing_token_response` and `.invalid_token_response` with `scope: "read write"`. The SDK puts `scope` before `resource_metadata` and quotes the values, which is why the spec scenario "Challenge" no longer fixes the order.
- **Read-only tools.** `ToolBuilder` sets `read_only_hint` from `Operation#read_only?` instead of from `HINTS`. `ScopedServer` (through the annotation) and `ToolCall` (directly) then rely on one predicate.
- **The exchange's route.** `POST /internal/mcp_token_exchange` (`Internal::McpTokenExchangesController#create`) replaces `POST /internal/mcp_tokens`. It is a singular resource named after what happens, like `activation` and `archival`. The MCP server's `ConnectionTokens::EXCHANGE_PATH` follows. Both roles ship from one image, and the exchange has not shipped yet.
- **A user's tokens are personal.** `User#api_tokens` is scoped to `personal`, so code that lists, counts or deletes a user's tokens cannot reach connection tokens by forgetting `.personal`, and `Api::Me::ApiTokensController` no longer calls it. `of_connections` unscopes the `oauth_access_token_id` condition before its own, so `user.api_tokens.of_connections` is that user's connection tokens rather than `IS NULL AND IS NOT NULL`. `ApiToken` has no default scope: authentication (`find_active_by_value`), connection ending (`McpConnection.revoke`) and `PurgeExpiredApiTokensJob` must see connection tokens.
- **One name limit.** `Oauth::MAX_NAME_LENGTH` is `ApiToken::MAX_NAME_LENGTH`, because a client's name becomes the name of its connection tokens. `Oauth::ClientMetadataDocument::MAX_NAME_LENGTH` is removed.

### 12. CIMD is paused, and DCR is the only registration

The second review of PR #29 asked that Goalner not fetch URLs that clients name, and that the CIMD code be kept.

- `config.x.oauth.client_metadata_documents` is false in `config/initializers/doorkeeper.rb`. Code reads it through `Oauth.client_metadata_documents?`.
- The metadata's `client_id_metadata_document_supported` follows the setting. MCP clients that see false register at `/oauth/register` instead.
- `Oauth::AuthorizationsController#resolve_client_metadata_document` refuses every client id that is an HTTPS URL with the error page, before any fetch. A CIMD client stored earlier is refused too, so nothing relies on a document that is no longer checked. Its existing tokens still refresh until `PurgeMcpConnectionsJob` ends them. Production has none, because the PR has not shipped.
- `Oauth::ClientMetadataDocument`, its tests and the CIMD fixtures stay. `OauthTestHelper` turns the setting on for every test, and `OauthClientMetadataDocumentsPausedTest` checks the default.
- The blocked ranges each get a comment, and add `fec0::/10` (deprecated site-local, which some networks still route) and `3fff::/20` (documentation, RFC 9637).

Alternatives:
- *An allowlist of document hosts.* Not now. A client that sees `client_id_metadata_document_supported: true` uses its document and does not fall back to DCR, so every client that is not on the list would fail to connect. An allowlist is the likely way to turn CIMD back on, for a short list such as `claude.ai`.
- *Delete the CIMD code.* Rejected, because the review asked to keep it.
- *Make the fixtures DCR clients.* Not now. Most OAuth tests do not depend on how the client registered, and the CIMD tests would then need fixtures of their own.

## Risks / Trade-offs

- **[Tool lists of connections now depend on Goalner]** → Only the first request per access token needs Goalner. Later requests use the cache, which lasts up to an hour. While Goalner is down, a client with a new token gets 503 instead of a tool list. Since every tool call needs Goalner anyway, nothing useful is lost. Personal tokens are unaffected.
- **[One connection token row per access token, even without tool calls]** → That is about 24 rows a day per active connection. `PurgeExpiredApiTokensJob` already deletes them daily once they expire.
- **[Lock contention on `users`]** → The lock is held only for a token request or a connection ending, which take milliseconds, about hourly per connection. Session sign-in and API requests do not take it.
- **[Accounts multiply the per-user fetch limit]** → The per-URL limit still applies to every account. Each fetch is bounded to 3 seconds and 5 KB, and sign-up has its own limits.
- **[Service key rotation is still an outage]** → It is now reported as 503 and leaves clients signed in. The README describes it as such.
- **[Existing spec conflict, not resolved here]** → The `mcp-server` requirement "Authentication" says a revoked token's tool list gets 401. A connection whose connection token is still cached can list tools for up to an hour after a disconnect, a gap the OAuth design already accepts in its risks. Decision 1 narrows the gap, since new access tokens are always confirmed, but does not close it. Closing it would need a call to Goalner on every request. If that matters, it should be a separate change.

## Migration Plan

1. Land this change on the `mcp-oauth` branch before PR #29 merges, so `add-mcp-oauth` is never deployed without it.
2. **Deploy.** The migration adds a nullable column with a backfill over a table that is empty in production. `MCP_ISSUER` must be in the top-level env in the same deploy: otherwise `RequiredSecrets` stops the web role from booting.
3. **Rollback.** Revert the code. The column can stay. Moving `MCP_ISSUER` back to the `mcp` role only is optional, since an extra variable is harmless.
