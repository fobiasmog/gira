# Design

## Context

- **`add-mcp-server`, archived first, provides:**
  - a separate MCP process (`mcp/`, `bin/mcp`) behind nginx at `/mcp`;
  - tools generated from `docs/openapi.yaml`;
  - a verifier list keyed by token shape;
  - `GoalnerMcp::UpstreamCredential.for(auth_info)`, which turns the verified credential into the Bearer value sent to the API.

  The MCP process has no database access and does not boot Rails.
- **Token code:**
  - Project reach is decided in one place, `Current#projects`.
  - `api_tokens` stores SHA-256 digests only and requires `project_id`.
  - Revocation hooks: `Project#archive!` and `#remove_member!` delete a project's tokens, and `User` deletes all tokens when the password digest changes. `PurgeExpiredApiTokensJob` runs daily.
- **Pages:**
  - Server-rendered pages (sign-in and so on) use `ApplicationController`, whose `Authentication#request_authentication` stores the GET URL and returns there after sign-in.
  - The CSP initializer sets `form-action 'self'` for every page.
  - Users choose `en` or `ru`.
- **Claude's connector requirements** (connector authentication docs, checked 2026-10-29):
  - CIMD is used when the metadata advertises `client_id_metadata_document_supported: true` and `none`, with DCR as the fallback;
  - callback `https://claude.ai/api/mcp/auth_callback`; Claude Code uses loopback redirects on any port for `localhost` and `127.0.0.1`;
  - S256 PKCE;
  - a `401` with `resource_metadata` starts sign-in;
  - refresh happens on `401` or close to expiry, and dead refresh tokens must answer `invalid_grant`;
  - a form-encoded token endpoint answering within 10 seconds;
  - egress from `160.79.104.0/21`, shared by every claude.ai user.
- **Libraries:**
  - Doorkeeper: 5.9.9 is the stable release. 6.0.0.rc2 adds RFC 8414 metadata and RFC 8707 resource indicators, but CIMD support and port-agnostic `localhost` are only on its unreleased main branch. In 5.9.9, loopback IP literals already match on any port.
  - The `mcp` gem 1.8 has a JWT verifier, protected resource metadata middleware and RFC 6750 challenges.
- **Decided while exploring:**
  - one connection reaches all of the user's projects;
  - read-only is offered at consent;
  - no password at consent;
  - CIMD and DCR are both supported;
  - the MCP server exchanges the access token for an API credential, cached in Redis.

## Goals / Non-Goals

**Goals:**
- **The API remains the only enforcer.** A connection is one more kind of token as far as `/api` is concerned. Allowlist, access level, rate limit and attribution are not reimplemented anywhere.
- **The MCP process gains no power of its own.** Without a live access token for a user, it cannot act as that user. Its service key alone opens nothing.
- **Nothing that authenticates is stored in readable form.** This holds in the database, in Redis and in logs.

**Non-Goals:**
- **No general OAuth provider for `/api`.** Connection access tokens authenticate only at the MCP server.
- **No consent per project and no fine-grained scopes.** Only `read` and `write`.
- **No upgrade to Doorkeeper 6.** It is a follow-up once 6.0 is final (decision 1).

## Decisions

### 1. Doorkeeper 5.9 in the main application, with the gaps written by hand

The application pins `doorkeeper` at `5.9.9` and configures it as follows:
- `base_controller "ApplicationController"`, which brings sign-in, layout, CSRF, CSP and locale;
- `resource_owner_authenticator { Current.user }`;
- `force_pkce` with `pkce_code_challenge_methods %w[S256]`;
- `grant_flows %w[authorization_code]` and `use_refresh_token`;
- `access_token_expires_in 1.hour` and `authorization_code_expires_in 10.minutes`;
- `hash_token_secrets` (SHA-256);
- `default_scopes :read`, `optional_scopes :write` and `enforce_configured_scopes`;
- `access_token_generator "Oauth::JwtGenerator"`;
- token introspection off.

Routes come from `use_doorkeeper`:
- `skip_controllers :applications, :authorized_applications, :token_info`, so there is no client admin UI and no introspection;
- `controllers authorizations: "oauth/authorizations", tokens: "oauth/tokens"`.

Written by hand:
- the authorization server metadata (decision 3);
- CIMD (decision 4) and DCR (decision 5);
- the `resource` check (decision 6);
- a port-agnostic match for `http://localhost` redirect URIs. This is a small module prepended to `Doorkeeper::OAuth::Helpers::URIChecker`, marked for removal when Doorkeeper releases its #1960.

Alternatives:
- *Doorkeeper 6.0.0.rc2.* Rejected for now. It is a release candidate in a security-critical path, and still lacks CIMD and `localhost` ports. The hand-written parts are small and are replaced when 6.0 is final.
- *A hand-written OAuth server.* Rejected. Code exchange, PKCE, refresh rotation and revocation are where subtle bugs live, and Doorkeeper has years of fixes there.
- *An external identity provider (Keycloak, WorkOS).* Rejected. Goalner owns its accounts, sessions, lockout and password rules, so federating them back would rebuild sign-in.

### 2. JWT access tokens signed with ES256

`Oauth::JwtGenerator.generate(...)` returns a JWT with these claims:
- `iss`: `https://goalner.com`;
- `sub`: the user id;
- `aud`: `https://goalner.com/mcp`;
- `client_id`: the application uid;
- `scope`: `read` or `read write`;
- `iat`, `exp` (1 hour) and a random `jti`.

Signing and keys:
- the token is signed with an EC P-256 private key from the credentials (`mcp.jwt_private_key`), with a `kid` equal to the key's SHA-256 thumbprint;
- Doorkeeper stores only the digest of the JWT (`hash_token_secrets`);
- the MCP server receives the public keys in `MCP_JWT_PUBLIC_KEYS` (PEM, several allowed, for rotation) and verifies `iss`, `aud`, `exp` (30 seconds of leeway) and the signature.

**What the MCP server checks locally.** The JWT lets it reject expired and foreign tokens without a network call, and gives it the scope for filtering tools (decision 9).

**What it cannot decide alone.** The JWT never authorizes a tool call by itself. The exchange (decision 8) looks the token up by digest in the database. A forged JWT, even one signed with a leaked key, can at most list tools; it can never call one.

Alternatives:
- *Opaque tokens that the MCP server introspects.* Rejected. Every MCP request, including tool lists, would cost a call to the main application, and listing tools by scope would need it too.
- *HS256 with a shared secret.* Rejected. The MCP process could then mint tokens for any user.

### 3. Authorization server metadata

`Oauth::MetadataController#show` serves `/.well-known/oauth-authorization-server` with:
- `issuer`;
- `authorization_endpoint`: `/oauth/authorize`;
- `token_endpoint`: `/oauth/token`;
- `registration_endpoint`: `/oauth/register`;
- `revocation_endpoint`: `/oauth/revoke`;
- `response_types_supported`: `["code"]`;
- `response_modes_supported`: `["query"]`;
- `grant_types_supported`: `["authorization_code", "refresh_token"]`;
- `code_challenge_methods_supported`: `["S256"]`;
- `token_endpoint_auth_methods_supported`: `["none"]`;
- `revocation_endpoint_auth_methods_supported`: `["none"]`;
- `scopes_supported`: `["read", "write"]`;
- `client_id_metadata_document_supported`: `true`.

`offline_access` is deliberately not listed: refresh tokens are always issued, and listing it would make Claude ask for a scope Doorkeeper does not know.

### 4. Client ID metadata documents

A `client_id` that is an `https://` URL is resolved before Doorkeeper builds the pre-authorization. `Oauth::ClientMetadataDocument.resolve(url)` works in three steps.

**Validate the URL:**
- `https` scheme;
- no userinfo or fragment;
- a non-root path;
- at most 255 characters.

**Fetch it safely:**
- resolve the host and refuse private, loopback, link-local, multicast, reserved and IPv4-mapped addresses;
- connect to the resolved address itself, with SNI and `Host` set to the original name, so a second DNS answer cannot redirect the request;
- 3 seconds in total, 5 KB at most, `application/json` only, no redirects.

**Check the document:**
- `client_id` equals the URL;
- `redirect_uris` is a non-empty array of HTTPS URIs or HTTP loopback URIs;
- `token_endpoint_auth_method` is absent or `none`;
- `client_name` is at most 100 characters, falling back to the URL's host.

**Store it.** An accepted document is upserted into `oauth_applications` with:
- `uid` set to the URL;
- `confidential: false`;
- `registration: "cimd"`;
- the redirect URIs;
- `metadata_fetched_at`.

**Refresh it.** The stored copy is used for 24 hours. A requested redirect URI that the stored copy does not list triggers one refetch, at most once a minute per URL.

**Failures.** Every failure renders the OAuth error page and never redirects, since nothing about the client can be trusted yet.

### 5. Dynamic client registration

`Oauth::RegistrationsController#create` (an `ActionController::API`, with no session and no CSRF) accepts a JSON body with:
- `client_name`;
- `redirect_uris`;
- optionally `grant_types`, `response_types` and `token_endpoint_auth_method`.

It applies the redirect URI rules of decision 4 and always registers a public client (`none`), whatever method was asked for, as RFC 7591 allows. It then answers 201 with:
- `client_id` (a random uid) and `client_id_issued_at`;
- the stored `client_name` and `redirect_uris`;
- `grant_types` `["authorization_code", "refresh_token"]` and `response_types` `["code"]`;
- `token_endpoint_auth_method` `none`.

There is no registration access token and no client management endpoint.

**Limits:**
- 20 registrations an hour per IP (`rate_limit` by `request.remote_ip`). claude.ai uses CIMD, so its shared egress range never hits this limit;
- `PurgeMcpConnectionsJob` (decision 10) deletes DCR applications with no grant 24 hours after registration.

### 6. Authorization: resource, response mode, consent and scope narrowing

`Oauth::AuthorizationsController < Doorkeeper::AuthorizationsController`.

**Checks before Doorkeeper's pre-authorization runs:**
- resolve a CIMD client (decision 4);
- refuse a `resource` other than `MCP_RESOURCE_URL` with `invalid_target`;
- refuse any `response_mode` other than `query`. Doorkeeper's `form_post` view needs inline script, which the CSP forbids.

**Consent is always shown.** Doorkeeper never auto-approves public clients; `skip_authorization` stays off.

**The consent view** (`app/views/oauth/authorizations/new.html.erb`, the application layout, `en` and `ru`) shows, in this order:
1. the redirect host, as the heading;
2. the client name;
3. for CIMD clients, the document's host;
4. the loopback warning, when every redirect URI of the client is a loopback address;
5. the all-projects statement;
6. the access choice: read-only preselected, and read-write only when `write` was requested;
7. Approve and Deny.

The form carries the original request parameters as hidden fields, plus `access`.

**Scope narrowing.** On `create`, a `before_action` rewrites `params[:scope]` to `read`, or to `read write` when `access` is `read_write` and `write` was requested. Doorkeeper then binds the code to that scope, and refresh keeps it.

**CSP.** The `new` action sets `form-action 'self' <redirect origin>` for that response only, with the origin taken from the validated redirect URI. Chrome and Firefox enforce `form-action` on the redirect that follows the form POST, so without this the approve and deny redirects to claude.ai would be blocked (spec security-baseline, "Consent page form action"). `oauth/tokens` checks `resource` the same way.

Alternatives:
- *Answer the consent POST with a page that links or meta-refreshes to the client.* Rejected. It is an extra click, or a navigation trick, to work around a policy we can state precisely instead.
- *Ask for the password on consent.* Rejected by the user. The session is the authentication; Connected apps and password change are the recovery.

### 7. A connection is a user and an application, not a new table

`McpConnection` is a plain object over Doorkeeper's tables:
- **List:** `McpConnection.for(user)` groups the user's non-revoked access tokens and grants by application.
- **Identity:** a connection's id is the application id, scoped to the current user.
- **Connected at:** the first token's `created_at`.
- **Last active:** the newest access token's `created_at`. Claude refreshes about hourly while in use, which meets "to within one hour".
- **Disconnect:** `#disconnect!` revokes every access token and grant for the pair and deletes the connection tokens that hang off them (decision 8).

`Api::Me::ConnectionsController` (`index` and `destroy`) is session-only. It is not opened with `allow_token_access`, so tokens and connections get 403.

**Password changes.** `User`'s existing `after_update_commit` on `password_digest` also calls `McpConnection.end_all_for(self)`.

**Edge case.** Two claude.ai accounts or two Claude Code machines of one user share a CIMD application, so they appear as one connection, and disconnecting ends both. This is acceptable: the user consented to "Claude" once per device, and disconnecting is meant to cut everything for that client.

### 8. Connection tokens and the exchange

**Schema:**
- `api_tokens.project_id` becomes nullable;
- a new `oauth_access_token_id` column references `oauth_access_tokens` with `on_delete: :cascade` and an index;
- a check constraint requires exactly one of the two to be set.

**`ApiToken`:**
- scopes `personal` and `connection`;
- `belongs_to :project, optional: true`;
- `belongs_to :oauth_access_token, optional: true`;
- personal tokens keep their validations, including `expires_in_days`.

**What changes elsewhere:**
- `Api::Me::ApiTokensController` uses `Current.user.api_tokens.personal` for the list, the limit of 20 and revocation.
- `ApiToken.find_active_by_value` refuses a connection token whose OAuth access token is revoked, using a join. Revocation is therefore immediate at the API, whatever the token's own `expires_at`.
- `Current#projects` gives connection tokens all of the user's kept projects. Personal tokens keep the `where(id: project_id)` narrowing, guaranteed by the constraint.
- `Project#archive!` and `#remove_member!` keep deleting by `project_id`, so they leave connection tokens alone. Their reach shrinks through `Current#projects` instead.

**The exchange:** `Internal::McpTokenExchangesController#create` at `POST /internal/mcp_token_exchange` (an `ActionController::API`, outside `/api`).
1. **Service key.** It compares `X-Goalner-Service-Key` with `MCP_SERVICE_KEY` using `secure_compare`. A mismatch answers 401.
2. **Access token.** It looks up `params[:access_token]` with `Doorkeeper::AccessToken.by_token` and requires it to be accessible and issued with `aud` = `MCP_RESOURCE_URL`. A failure answers 401 `invalid_token`.
3. **Refresh rotation.** It calls `revoke_previous_refresh_token!`. This exchange is the access token's first use in Goalner, which completes Doorkeeper's refresh rotation (spec mcp-authorization, "Old refresh token").
4. **Rate limit.** 60 exchanges an hour per access token.
5. **Issue.** It creates a connection token:
   - `name`: the application's name;
   - `access`: `read_write` when the scope includes `write`, else `read`;
   - `expires_at`: the access token's expiry;
   - `user`: the resource owner.

   It answers 201 with `{ token, expires_at, access }`.

nginx refuses `/internal/` from outside (decision 11), so the key is the second lock, not the only one.

Alternatives:
- *A per-user hidden token read from the database by the MCP process.* Rejected while exploring. The database would need readable credentials, and the MCP process would hold a skeleton key for every user.
- *The MCP server forwards the access token to `/api` together with the service key.* Workable, but it puts OAuth token handling into `ApiTokenAuthentication` and blurs the spec rule that MCP servers do not pass client tokens upstream.

### 9. MCP server: verification, exchange, cache and tool filtering

**Verification.** The verifier list gains a JWT verifier for any Bearer value without the `glnr_` prefix. It uses the SDK's `MCP::Server::OAuth::JWTVerifier` with the static public keys, and `ProtectedResourceMetadata` built with:
- `resource`: `MCP_RESOURCE_URL`;
- `authorization_servers`: `[MCP_ISSUER]`;
- `scopes_supported`: `["read", "write"]`;
- `bearer_methods_supported`: `["header"]`.

**Metadata routes.** `ProtectedResourceMetadataMiddleware` serves the document at both well-known paths.

**401 responses** carry `WWW-Authenticate: Bearer resource_metadata="<MCP_PUBLIC_URL>/.well-known/oauth-protected-resource/mcp", scope="read write"`, with `error="invalid_token"` when a token was present.

**`UpstreamCredential.for(auth_info)` for a JWT:**
1. Look up `mcp:ct:<sha256(jwt)>` in the cache and decrypt it.
2. On a miss, call the exchange with `MCP_SERVICE_KEY`, then store the result.
3. An exchange answer of 401 becomes HTTP 401 with the challenge, which makes Claude refresh. A 429 becomes the `rate_limited` tool error.

An API 401 during a tool call drops the cache entry and answers 401, as in `add-mcp-server`.

**Cache entries:**
- AES-256-GCM, with a key from HKDF-SHA256 over the JWT (fixed salt, info `goalner-mcp-connection-token`) and a random nonce;
- time to live: the connection token's expiry minus 30 seconds.

A Redis dump yields only ciphertext keyed by hashes. Decrypting an entry needs the JWT itself, which only the client holds.

**Where the cache lives.** Redis from `REDIS_URL`, or a bounded in-memory LRU when it is unset (development and test). Redis errors are logged and treated as misses; the exchange limit bounds the extra load.

**Tool filtering.** With a token whose scope lacks `write`:
- `tools/list` returns only the read-only tools;
- calling another tool returns the `insufficient_scope` tool error without an API request.

Personal tokens carry no scope, so they keep the full list, and the API decides as in `add-mcp-server`.

### 10. Housekeeping

`PurgeMcpConnectionsJob` runs daily at 3:45am (`config/recurring.yml`). It:
- disconnects connections whose newest access token is older than 90 days;
- deletes DCR applications with no grant 24 hours after registration;
- deletes CIMD applications with no tokens for 90 days;
- deletes grants and access tokens revoked more than 30 days ago, cascading to their connection tokens. Expired but unrevoked access tokens are kept, because Doorkeeper stores the refresh token in the same row and deleting it would end the connection early.

### 11. Deployment and secrets

**Main application:**
- `mcp.jwt_private_key` in the credentials;
- `MCP_SERVICE_KEY` and `MCP_RESOURCE_URL` in the environment;
- all three added to `RequiredSecrets` and `config/credentials.example.yml`.

**MCP role:**
- `MCP_SERVICE_KEY` and `REDIS_URL` as Kamal secrets;
- `MCP_JWT_PUBLIC_KEYS`, `MCP_ISSUER` and `MCP_RESOURCE_URL` as clear env.

The MCP process refuses to start in production when any of these is missing.

**Redis.** A Valkey 8 accessory with a password, on the private network only. It is used only by the MCP role.

**nginx (README snippet):**
- `/.well-known/oauth-protected-resource` and `/.well-known/oauth-protected-resource/` go to the MCP upstream;
- `location ^~ /internal/ { return 404; }`;
- everything else is unchanged.

**Key rotation.** Add the new public key to `MCP_JWT_PUBLIC_KEYS`, deploy, switch the private key, deploy, and remove the old public key after 1 hour.

## Risks / Trade-offs

- **[Hand-written OAuth pieces (metadata, CIMD, DCR, `resource`, the localhost patch) diverge from Doorkeeper 6]** → Each lives in its own small class with its own tests. Replacing them is a follow-up when 6.0 is final, and the localhost patch fails a test once Doorkeeper fixes it upstream.
- **[SSRF through CIMD URLs]** → Decision 4: resolved-address checks, connecting to the resolved IP, no redirects, size and time limits. Tests cover IPv4, IPv6, mapped and DNS-rebinding cases with a stubbed resolver.
- **[Phishing with a misleading client name ("Claude") on someone else's document]** → The redirect host is the heading, and the document's host is shown. A code sent to a redirect URI the attacker does not control is useless to them without the PKCE verifier.
- **[A stolen session can authorize a client without a password]** → Accepted. The connection appears in Connected apps, and a password change ends every connection.
- **[Rate limits keyed by IP would throttle every claude.ai user at once]** → No per-IP limit on the token endpoint, authorize or exchange. Only DCR is limited per IP, and claude.ai does not use DCR when CIMD is advertised.
- **[A disconnected client can still list tools until its JWT expires (up to 1 hour)]** → Tool calls fail at once, because the exchange and the API check revocation. The tool list reveals only the published document.
- **[Redis outage]** → Every tool call then exchanges again: one extra internal request, bounded by 60 an hour per access token. After that, tool calls get `rate_limited` until Redis returns.
- **[Leaked service key]** → It is useless without a live user access token. Rotate it by redeploying both roles.
- **[Leaked signing key]** → Forged JWTs list tools but fail at the exchange, which checks the database. Rotate as in decision 11.
- **[`api_tokens` migration on a live table]** → The table is small (at most 20 personal tokens per user). Making a column nullable and adding a constraint that existing rows satisfy needs no backfill.
- **[Spec merge order]** → `add-mcp-server` must be archived first, or archiving the `mcp-server` delta is refused. `team-call` must be archived first so the CSP requirement keeps its media-server text. If `team-call` changes its CSP text before archiving, rebase this delta.

## Migration Plan

1. **Main application.** Deploy the migrations, Doorkeeper, the new controllers and `RequiredSecrets` entries, with the new credentials and `MCP_SERVICE_KEY` set.
   - Existing personal tokens keep working (all have `project_id`).
   - Nothing is reachable yet, because the MCP server does not advertise OAuth.
2. **Redis and MCP role.** Boot the Redis accessory, then deploy the MCP role with the new env.
3. **nginx.** Add the protected-resource and `/internal/` locations, and reload.
4. **Claude Code.** Remove the header-based server, add `https://goalner.com/mcp` without a header, sign in, approve read-only, list projects, and check Connected apps.
5. **claude.ai.** Add a custom connector with the URL, approve read-write, create a task, disconnect, and confirm the next call asks to reconnect.

**Rollback.** Remove the protected-resource location in nginx: clients then see a 401 without a metadata pointer, and personal tokens keep working. The Doorkeeper tables and the nullable column can stay; reverting the migration requires deleting connection tokens first.
