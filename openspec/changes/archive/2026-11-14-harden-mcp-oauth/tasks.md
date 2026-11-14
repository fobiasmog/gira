# Tasks

## 1. Tests that cannot reach the network

- [x] 1.1 Make the default CIMD resolver and transport raise in `test/test_helper.rb`, and add a `setup` to `OauthTestHelper` that marks the CIMD fixtures as just fetched (design.md, decision 10). Comment the ERB timestamp in `test/fixtures/oauth/applications.yml`. Verify:
  - a new test in `test/integration/oauth_authorization_request_test.rb` travels 2 minutes ahead, then requests `claude_code` with `http://localhost:51234/other`, and still gets `invalid_redirect_uri`, with no fetch;
  - `test/models/oauth/client_metadata_document_test.rb` still passes with its own stubs;
  - `bin/rails test` passes.

## 2. Refresh rotation, connection ending and the exchange

- [x] 2.1 In `Oauth::TokensController#create`, for the `authorization_code` and `refresh_token` grants, find the owner by digest, then run `super` in a transaction that first locks the user's row. For a refresh token, also call `revoke_previous_refresh_token!` (decisions 1 and 2). Verify in `test/integration/oauth_flow_test.rb`:
  - the mcp-authorization scenario "Old refresh token after the next refresh";
  - "Refresh", "Old refresh token", "Code exchange" and "Code reused" still pass;
  - an unknown refresh token still answers `invalid_grant`.
- [x] 2.2 Make `McpConnection.revoke` take the user and lock its row before deleting connection tokens and revoking. Pass the user from `#disconnect!`, `.end_all_for` and `PurgeMcpConnectionsJob#end_unused_connections` (decision 2). Verify:
  - a non-transactional test (`self.use_transactional_tests = false`) with two threads covers the mcp-authorization scenario "Disconnected during a refresh". A latch inside `Oauth::AccessToken.create_for` holds the refresh while the other thread disconnects. The refresh's new token ends up revoked, and the connection is not listed;
  - the same test in the other order: the disconnect commits first, and the refresh answers `invalid_grant`;
  - the existing connections, purge and password tests pass.
- [x] 2.3 Replace `Oauth::JwtGenerator.decode` with `.claims`, which checks `iss` and `aud` without verifying the signature, and use it in `Internal::McpTokenExchangesController`. Move the `oauth_flow_test` assertions to `decode_access_token` (decision 4). Verify in `test/controllers/internal/mcp_token_exchanges_controller_test.rb`:
  - the api-tokens scenario "Previous signing key": issue a token, swap the private key the generator uses, and the exchange answers 201;
  - a live token row whose JWT has another `aud` answers 401.
- [x] 2.4 In `ConnectionTokens#exchange`, raise `Refused` only for a 401 with `{"error":"invalid_token"}`. Any other 401 is logged and raises `ApiClient::Unavailable` (decision 3). Verify in `test/mcp/connection_tokens_test.rb`:
  - a 401 with `invalid_service_key` raises `Unavailable`;
  - a 401 with an empty body raises `Unavailable`;
  - a 401 with `invalid_token` raises `Refused`;
  - the log line contains neither key nor token.
- [x] 2.5 In `Authentication`, confirm every connection credential before calling the app, memoize the result on `Credential#upstream_token`, and have `ToolCall` use it (decision 1). Verify in `test/mcp/oauth_authentication_test.rb` and `test/mcp/connection_tokens_test.rb`:
  - `tools/list` with a JWT not seen before makes one exchange, and a later `tools/call` with the same JWT makes none;
  - the mcp-server scenarios "Ended connection, new access token" (401 `invalid_token` on `tools/list`) and "Service key refused" (503, no `invalid_token`);
  - with the exchange rate limited, `tools/list` still lists tools and `tools/call` returns the `rate_limited` tool error with one exchange in total;
  - personal tokens make no exchange.

  Together with the existing "Old refresh token" test in `test/controllers/internal/mcp_token_exchanges_controller_test.rb`, this covers the mcp-authorization scenario "Old refresh token after listing tools".

## 3. Client registration and documents

- [x] 3.1 Cut host fallback names to 100 characters in `Oauth::RegistrationsController` and `Oauth::ClientMetadataDocument`, and the connection token's name in `ApiToken.issue_for_connection!` (decision 5). Verify:
  - `test/controllers/oauth/registrations_controller_test.rb` stores a 100-character name for a 130-character host;
  - the CIMD model test does the same for a document without `client_name`;
  - `test/controllers/internal/mcp_token_exchanges_controller_test.rb` answers 201 for an application whose stored name has 130 characters. This covers the mcp-authorization scenario "Name from a long host".
- [x] 3.2 Add the per-user and per-URL fetch counters to `ClientMetadataDocument.resolve(url, redirect_uri:, user:)`, and pass `Current.user` from `Oauth::AuthorizationsController` (decision 6). Verify in the CIMD model test, with `Rails.cache.clear` in `setup`:
  - the mcp-authorization scenarios "Unreachable document" (two resolves within a minute make one transport call) and "Many documents" (the 11th URL makes no transport call);
  - a stored copy older than 24 hours whose host fails is fetched at most once a minute;
  - a copy fetched within the minute is reused without touching the counters.
- [x] 3.3 Send `Accept-Encoding: identity` from `HttpTransport`, add the response's content encoding to `Response`, refuse any encoding other than `identity`, and rescue `Zlib::Error` (decision 6). Verify:
  - the mcp-authorization scenario "Compressed document" through `FakeTransport`;
  - a test of `HttpTransport` against a local plain-HTTP server thread on `127.0.0.1` shows that the request carries `Accept-Encoding: identity`, and that a gzip-encoded answer raises `Error` without inflating it.
- [x] 3.4 Refuse bracketed hosts in `Oauth.allowed_redirect_uri?`, and drop IPv6 loopback entries in `ClientMetadataDocument#redirect_uris` before validating (decision 7). Verify:
  - the mcp-authorization scenario "Registration with an IPv6 loopback URI" in the registrations test;
  - "Document with an IPv6 loopback URI" in the CIMD model test (stored without `[::1]`) and in `test/integration/oauth_authorization_request_test.rb` (consent for `127.0.0.1:8080`, error page for `[::1]:8080`).

## 4. Housekeeping

- [x] 4.1 Add `oauth_applications.first_authorized_at` with its backfill, set it from `Oauth::AccessGrant`'s `after_create`, delete only never-authorized DCR clients, and purge grants created more than 30 days ago (decision 8). Verify:
  - `bin/rails db:migrate` and `db:rollback` both run;
  - `test/jobs/purge_mcp_connections_job_test.rb` covers the mcp-authorization scenario "Authorized client kept" (connect, disconnect, travel 60 days, run the job, then the authorization request shows consent) and "Unused client";
  - an unredeemed grant older than 30 days is deleted, and a client whose only grant was unredeemed counts as authorized.

## 5. Configuration and cleanups

- [x] 5.1 Read the issuer from `MCP_ISSUER` in `config/initializers/doorkeeper.rb`. Add `MCP_ISSUER` to `RequiredSecrets::ENV_KEYS` and `config/credentials.example.yml`, and move `MCP_ISSUER` and `MCP_RESOURCE_URL` to the top-level `env.clear` of `config/deploy.yml` (decision 9). Verify:
  - `test/initializers/required_secrets_test.rb` names `MCP_ISSUER` when it is missing;
  - `MCP_ISSUER=https://example.test bin/rails runner 'puts Oauth.issuer'` prints that URL;
  - `bin/kamal config` shows both variables for the web and mcp roles.
- [x] 5.2 Make `McpConnection.for` pluck the four columns, and `McpConnection.find` query only the requested application (decision 11). Verify:
  - `test/controllers/api/me/connections_controller_test.rb` passes unchanged;
  - a test counting `instantiation.active_record` events shows that listing builds no `Oauth::AccessToken` objects.
- [x] 5.3 Remove `GoalnerMcp::Challenge`, and have `Authentication` call the SDK's `Challenge` with `scope: "read write"` and the metadata URL (decision 11). Verify:
  - `test/mcp/authentication_test.rb` and `test/mcp/oauth_authentication_test.rb` cover the mcp-server scenario "Challenge", parsing the header's parameters without depending on their order;
  - `error="invalid_token"` appears only once a token was refused.
- [x] 5.4 Set `read_only_hint` from `Operation#read_only?` in `ToolBuilder` (decision 11). Verify that a test in `test/mcp/scopes_test.rb` checks, for every generated tool, that the annotation equals the operation's `read_only?`, and that the read-only list equals the tools `ToolCall` lets a read-only connection call.

## 6. Documentation and integration

- [x] 6.1 Update the README's MCP section:
  - "Rotating keys": no forced refresh for the signing key, and for the service key a window of 503 answers without sign-outs;
  - `MCP_ISSUER` for both roles;
  - IPv6 loopback redirect URIs are not supported.

  Update the comments that describe rotation as finishing on a tool call (`config/initializers/doorkeeper.rb`, `Internal::McpTokenExchangesController`, `ConnectionTokens`, `McpConnection`). Verify by reading the section against decisions 1, 3, 4 and 9.
- [ ] 6.2 Run `bin/ci`, `bin/rails test:system` and `openspec validate harden-mcp-oauth`. Verify all pass and that Brakeman reports no new warnings.

  Status on 2026-11-04, left open:
  - Passing: RuboCop, Brakeman (0 warnings), `bin/rails test` (630 runs, also with `CI=true`), seeds, and `openspec validate`.
  - `bin/ci` fails at "Security: Gem audit" on advisories published during the run, in gems this change does not touch: `rack` 3.2.7 (4, one High; fixed in >= 3.2.8) and `addressable` 2.9.0 through `capybara` (7; fixed in >= 2.9.1). The bumps go in a separate PR.
  - `bin/rails test:system`: 2 of 143 fail, identically on the unchanged branch head: `DashboardTest` "deadlines show date tiles with today highlighted" and `TaskPageTest` "post a comment with an attachment, edit it and delete it".

  Check this off once the gem bumps land and both system tests pass, or are fixed elsewhere.
- [ ] 6.3 Against `bin/dev`, with the MCP Inspector's OAuth flow:
  - connect read-only and force a refresh;
  - list tools with the new token only, then refresh with the old refresh token using curl. Verify the refresh answers `invalid_grant`;
  - restart `bin/mcp` with a wrong `MCP_SERVICE_KEY`, force a refresh, and list tools. Verify the answer is 503 and the Inspector does not start sign-in again.

## 7. Second review of PR #29

- [x] 7.1 Pause CIMD behind `config.x.oauth.client_metadata_documents` (false), read through `Oauth.client_metadata_documents?`. Use it in the metadata and in `Oauth::AuthorizationsController#resolve_client_metadata_document`. Turn it on in `OauthTestHelper` (decision 12). Verify:
  - `test/integration/oauth_client_metadata_documents_paused_test.rb` covers the metadata and the mcp-authorization scenarios "Document URL while paused", "Stored document client while paused" and "Registered client while paused";
  - removing the controller's check makes that test fail.
- [x] 7.2 Comment each of `Oauth::ClientMetadataDocument::BLOCKED_RANGES`, and add `fec0::/10` and `3fff::/20` (decision 12). Verify that the CIMD model test refuses `fec0::1`, `3fff::1`, `100.100.100.200` and `192.0.0.192` without a request.
- [x] 7.3 Move the exchange to `resource :mcp_token_exchange` (`Internal::McpTokenExchangesController`), with `ConnectionTokens::EXCHANGE_PATH`, the README and the tests (decision 11). Verify that `test/mcp` and `test/controllers/internal` pass, and `test/integration/request_forgery_test.rb` lists the new endpoint.
- [x] 7.4 Scope `User#api_tokens` to `personal`, drop `.personal` from `Api::Me::ApiTokensController`, and have `of_connections` unscope the `oauth_access_token_id` condition. Add `Oauth::MAX_NAME_LENGTH` as `ApiToken::MAX_NAME_LENGTH` (decision 11). Verify:
  - `test/models/api_token_test.rb` shows that `user.api_tokens` leaves out the user's connection token and `user.api_tokens.of_connections` finds only it;
  - `test/integration/connection_token_access_test.rb` and `test/models/user_test.rb` pass.
- [ ] 7.5 Against `bin/dev`, connect Claude Code (`/mcp` → Authenticate) and the MCP Inspector. Verify that both register at `/oauth/register` and reach the consent page.

## Workflow follow-up

- Archive `add-mcp-oauth` before this change. Its `mcp-authorization`, `mcp-server` and `api-tokens` deltas define the requirements modified here.
