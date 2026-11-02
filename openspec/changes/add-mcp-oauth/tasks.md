# Tasks

## 1. OAuth core and browser risks first

- [ ] 1.1 Add `doorkeeper` (exactly `5.9.9`) and `jwt` to the `Gemfile`, and `jwt` to the `mcp` group. Generate the Doorkeeper migrations with the PKCE columns, and add `registration` (`cimd` or `dcr`) and `metadata_fetched_at` to `oauth_applications` (design.md, decision 1). Verify:
  - `bin/bundler-audit` passes;
  - `bin/rails db:migrate` and `db:rollback` both run;
  - `bin/rails test` still passes.
- [ ] 1.2 Configure Doorkeeper as in decision 1. Add `Oauth::JwtGenerator` (decision 2, with a test key pair in `config/credentials/test`), the `use_doorkeeper` routes with skipped controllers, and the `Oauth::AuthorizationsController` and `Oauth::TokensController` subclasses. Verify `test/integration/oauth_flow_test.rb` with a fixture public application:
  - a signed-in user approves, and the code plus verifier, form-encoded, yields a JWT with the claims of decision 2 that validates with the public key, and a refresh token;
  - the consent POST without a CSRF token is rejected with 422, and the token endpoint needs none;
  - `/oauth/applications`, `/oauth/authorized_applications` and `/oauth/token/info` answer 404.

  Update `test/integration/request_forgery_test.rb` and the route-table checks with an explicit, commented list of the OAuth and internal endpoints that take no session.
- [ ] 1.3 Make the `new` action set `form-action 'self' <redirect origin>` (decision 6). Verify `test/system/oauth_consent_test.rb` in Chrome against a production build:
  - approving and denying with a loopback redirect URI served by the test server reaches that URI;
  - the page reports no `securitypolicyviolation`;
  - the policy on `/oauth/authorize` contains exactly `'self'` and that origin, while the sign-in page keeps `form-action 'self'`.

  This covers the spec security-baseline scenarios "Consent page form action" and "Consent redirect in the browser". If Chrome still blocks the redirect, stop and bring the alternatives in decision 6 back to the user.
- [ ] 1.4 In `mcp/`, configure the SDK's `JWTVerifier` with a static public key and `ProtectedResourceMetadataMiddleware` (decision 9), behind the existing verifier list. Verify with curl against `bin/mcp`:
  - `/.well-known/oauth-protected-resource/mcp` returns the document;
  - a request without a token gets the exact `WWW-Authenticate` header of the spec scenario "Challenge";
  - a JWT from task 1.2's generator lists tools;
  - an expired one gets `error="invalid_token"`.

  Record the requests and responses in the change's notes.

## 2. Discovery and client registration

- [ ] 2.1 Add `Oauth::MetadataController` for `/.well-known/oauth-authorization-server` (decision 3). Verify the spec mcp-authorization scenario "Metadata" in `test/controllers/oauth/metadata_controller_test.rb`, including that `offline_access` is absent and `response_modes_supported` is `["query"]`.
- [ ] 2.2 Add `Oauth::ClientMetadataDocument` with the URL rules, the resolved-address checks, connecting to the resolved IP, the 3-second and 5 KB limits, no redirects, the document checks, and the upsert with a 24-hour reuse window and at most one refetch a minute (decision 4). Verify `test/models/oauth/client_metadata_document_test.rb` with a stubbed resolver and HTTP:
  - the scenarios "Claude Code", "Mismatched client id", "Private address" (IPv4, IPv6, IPv4-mapped, and a resolver that answers public then private) and "Unlisted redirect URI";
  - a 6 KB document, a slow response and a 302 are each refused;
  - an unlisted redirect URI triggers exactly one refetch.
- [ ] 2.3 Add `Oauth::RegistrationsController` with the 20-an-hour per-IP limit (decision 5). Verify `test/controllers/oauth/registrations_controller_test.rb`:
  - the scenarios "Registration", "Plain HTTP redirect" and "Registration burst";
  - a request asking for `client_secret_basic` is registered as `none`;
  - the response carries no secret.
- [ ] 2.4 Add the `resource` and `response_mode` checks to the authorize and token subclasses, and the `localhost` loopback patch (decisions 1 and 6). Verify `test/integration/oauth_authorization_request_test.rb`:
  - the scenarios "Missing PKCE", "Plain challenge", "Loopback on any port" (for `localhost` and `127.0.0.1`) and "Other resource";
  - `response_mode=form_post` is refused;
  - a test that fails once `Doorkeeper::OAuth::Helpers::URIChecker` matches `localhost` ports on its own, so the patch gets removed.

## 3. Consent

- [ ] 3.1 Build the consent view in `en` and `ru`, with the hidden original parameters, the access choice and the scope narrowing on `create` (decision 6). Verify `test/integration/oauth_consent_test.rb` covers these mcp-authorization scenarios:
  - "Signed out" (sign-in, then back to the same request);
  - "claude.ai", "Loopback client" and "Read scope only";
  - "Approve read-only", "Deny" and "Code reused";
  - "Code exchange", "Wrong verifier" and "Refresh";
  - "Client revokes".

  Also verify that a hand-edited `access=read_write` on a request that only asked for `read` still issues `read`. Add a consent page check to `test/system/accessibility_test.rb`.

## 4. Connection tokens and the exchange

- [ ] 4.1 Make `api_tokens.project_id` nullable, add `oauth_access_token_id` (cascade) and the one-of check constraint, and add the `personal` and `connection` scopes to `ApiToken`. Update `find_active_by_value` (revoked OAuth token join), `Current#projects` and `Api::Me::ApiTokensController` to use `personal` (decision 8). Verify:
  - new tests for the api-tokens scenarios "Connection token project list", "Connection token after leaving", "Connection token outlives no project", "Not a personal token" and "Connection token id";
  - a database test that a row with both or neither of `project_id` and `oauth_access_token_id` is rejected;
  - `test/integration/api_token_authentication_test.rb`, `test/integration/api_token_access_test.rb` and `OPENED_TO_TOKENS` are unchanged and pass.
- [ ] 4.2 Add `Internal::McpTokensController` with the service key check, the access token lookup, `revoke_previous_refresh_token!`, the 60-an-hour limit and connection token issuance (decision 8). Verify `test/controllers/internal/mcp_tokens_controller_test.rb` covers:
  - the api-tokens scenarios "Exchange", "Wrong service key", "Ended connection", "Disconnected while in use", "Read-only connection" and "Exchange burst";
  - the security-baseline scenario "Internal exchange without the service key";
  - the mcp-authorization scenarios "Access token at the API" and "Old refresh token" (an exchange with the new access token makes the old refresh token answer `invalid_grant`).

## 5. Connections in the account

- [ ] 5.1 Add `McpConnection` (decision 7), `Api::Me::ConnectionsController` (`index` and `destroy`, session-only) and `McpConnection.end_all_for` in `User`'s password hook. Verify:
  - the mcp-authorization scenarios "List", "Another user's connection", "Token request", "Disconnected" and "Password changed";
  - the user-auth scenarios "Connections end on reset" and "Connections ended".
- [ ] 5.2 Add `PurgeMcpConnectionsJob` and its `config/recurring.yml` entry (decision 10). Verify `test/jobs/purge_mcp_connections_job_test.rb`:
  - the scenarios "Unused" (90 days) and "Unused client" (24 hours);
  - CIMD applications without tokens for 90 days are deleted;
  - revoked rows older than 30 days are deleted together with their connection tokens;
  - an expired, unrevoked access token whose refresh token still works is kept, and refreshing it succeeds.
- [ ] 5.3 Add `ConnectedAppsSettingsPage.vue`, `app/frontend/api/connections.ts`, the route `/settings/connected-apps`, the settings tab, the `en` and `ru` strings, and the new password warning text (`settings.passwordRevokesTokens` mentions connected apps). Verify:
  - Vitest tests for the page;
  - `test/system/settings_test.rb` covers the web-client scenarios "List connections", "Disconnect", "No connections" and "Password change warning";
  - `app/frontend/i18n/i18n.test.ts` passes for both languages.

## 6. MCP server

- [ ] 6.1 Put the JWT verifier, the metadata and the challenge from task 1.4 into production configuration from `MCP_JWT_PUBLIC_KEYS`, `MCP_ISSUER`, `MCP_RESOURCE_URL` and `MCP_PUBLIC_URL`, refusing to start in production when any is missing (decisions 9 and 11). Verify `test/mcp/oauth_authentication_test.rb` covers the mcp-server scenarios:
  - "Connection access token", "Expired access token" and "Token for another audience";
  - "Metadata" and "Challenge".
- [ ] 6.2 Add the exchange client to `UpstreamCredential`, with the encrypted cache: Redis from `REDIS_URL`, otherwise the in-memory LRU (decision 9). Verify `test/mcp/connection_tokens_test.rb`:
  - a second tool call with the same JWT makes no exchange;
  - the stored cache value contains neither the connection token nor the JWT, and cannot be decrypted with another JWT;
  - the mcp-server scenarios "Connection ended between calls" and "Connection across projects";
  - the mcp-authorization scenarios "Project joined later" and "Project left";
  - a cache that raises on every call still serves tool calls through the exchange.
- [ ] 6.3 Filter tools by scope (decision 9). Verify the mcp-server scenarios "Read-only connection lists tools" and "Read-only connection calls a write tool" (the API request count stays at zero), and that personal tokens still list all tools.

## 7. Deployment and documentation

- [ ] 7.1 Add the keys to `RequiredSecrets` and `config/credentials.example.yml`. In `config/deploy.yml`, add the Valkey accessory, the `mcp` role's secrets and the web role's `MCP_SERVICE_KEY` (decision 11). Verify:
  - `test/initializers/required_secrets_test.rb` names each new key when it is missing;
  - `bin/kamal config` shows the accessory and gives `REDIS_URL` and `MCP_SERVICE_KEY` only to the roles that need them.
- [ ] 7.2 Extend the README's MCP section with:
  - adding Goalner as a claude.ai custom connector and in Claude Code without a header;
  - Connected apps;
  - the nginx locations for protected resource metadata and the `/internal/` deny;
  - the environment variables and the key rotation steps.

  Verify by following it against `bin/dev`: Claude Code (`claude mcp add --transport http goalner-dev http://localhost:3100/mcp`) signs in through the browser, approves read-only, lists projects, sees no write tools, and the connection appears under Settings → Connected apps.

## 8. Integration

- [ ] 8.1 Run `bin/ci`, `bin/openapi-verify` and `bin/rails test:system`. Verify all pass and that Brakeman reports no new warnings for the OAuth and internal controllers.
- [ ] 8.2 Using the MCP Inspector's OAuth flow against `bin/dev`, connect read-write, create a task in two projects, disconnect in Settings, and call a tool again. Verify the call answers 401, the refresh answers `invalid_grant`, and the Inspector starts sign-in anew.

## Workflow follow-up

- Archive `team-call` and `add-mcp-server` before archiving this change. Archiving the `mcp-server` delta is refused until that spec exists, and the `security-baseline` CSP block assumes `team-call`'s text.
- After deploying as in design.md, "Migration Plan", add `https://goalner.com/mcp` as a claude.ai custom connector and repeat task 8.2's checks there.
- When Doorkeeper 6.0 is released, propose a change that replaces the hand-written metadata, `resource` check, CIMD and localhost patch with Doorkeeper's own.
