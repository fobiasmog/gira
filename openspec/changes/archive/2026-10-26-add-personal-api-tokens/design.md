# Design

## Context

See proposal.md for the motivation and specs/api-tokens/spec.md for the behavior. This is how a request is authenticated today:

- **CSRF check first.** The `action_controller.request_forgery_protection` initializer installs `protect_from_forgery with: :exception` on `ActionController::Base` when it loads. So `verify_authenticity_token` is the first `before_action` of every controller, ahead of authentication.
- **Then authentication.** `Authentication#require_authentication` resumes the session from the signed `session_id` cookie into `Current.session`, and `Current.user` is delegated to it. `Api::BaseController#request_authentication` answers 401 JSON instead of redirecting.
- **The locale wrapper reads the cookie too.** `ApplicationController#switch_locale` calls `authenticated?`, which goes through `resume_session` and the cookie again.
- **Project scoping happens in four places:** `ProjectScoped#set_project`, `Api::ProjectsController#index`, `Api::CommentsController#set_comment` and `FilesController#visible?`, all through `Current.user.projects.kept`. Statistics and teammates span every project of the user.
- **`Current.session` is used directly** only in `Authentication` and `Api::Me::PasswordsController`. The admin jobs dashboard is behind `AdminConstraint`, which reads the cookie in the router and never reaches a controller.
- **Wrong passwords count only at sign-in.** `User#register_failed_sign_in!` handles the 10-strike lockout and is called only by `SessionsController#create`. `Api::Me::PasswordsController` checks the current password through `password_challenge` and does not count failures.
- **Existing pieces that already fit:**
  - Sentry's `before_send` already drops `Authorization` headers (`config/initializers/sentry.rb`).
  - `rate_limit` already accepts `scope:` and `if:`, and production rate-limit counters live in Solid Cache.
  - `allow_browser versions: :modern` blocks only known browsers below the minimum version, so HTTP clients such as curl are not affected.
  - There is no CORS middleware.

## Goals / Non-Goals

**Goals:**
- One place decides whether a request is in token or session mode, and the two modes never mix.
- Deny by default is structural: an action refuses tokens unless it is opened to them, and a route-table test enforces this.
- The web client, its requests and its existing tests are unchanged.

**Non-Goals:**
- Page controllers other than `FilesController` do not accept tokens, and neither do the admin jobs dashboard or `AdminConstraint`.
- No per-IP limit on invalid tokens. Guessing a value with more than 200 random bits is not feasible, and the request limit applies once a token is found.
- No OAuth, token refresh or token rotation endpoint.

## Decisions

### 1. The `Bearer` scheme selects token mode

A new concern, `ApiTokenAuthentication`, is included only in `Api::BaseController` and `FilesController`. A request is in token mode when its `Authorization` header uses the `Bearer` scheme. In token mode:

- `require_authentication` authenticates by the token, or answers 401 `invalid_token`. It never calls the session path.
- `resume_session` returns `nil`, so `authenticated?` (called by `switch_locale`) cannot load a session from the cookie after the token was checked.

The mode depends on the scheme, not on the mere presence of an `Authorization` header. Browsers attach `Basic` credentials automatically once a user has authenticated to an origin, for example a staging server behind HTTP basic auth. Switching on any `Authorization` header would put the web client into token mode there and break it. Browsers never attach `Bearer` on their own.

- *Alternative: try the token, then fall back to the cookie.* Rejected. A bad token with a valid cookie would act as the user's session without CSRF protection (see decision 2).
- *Alternative: a separate `/api/v1` namespace with its own controllers for tokens.* Rejected. It would duplicate every endpoint, and the two copies would drift apart.

### 2. CSRF is skipped in token mode, decided by the header

`Api::BaseController` declares `skip_forgery_protection if: :bearer_token_request?`. The condition looks at the header, not at a token-authenticated user, because forgery protection runs before authentication (see Context).

This is safe because token mode never reads the cookie (decision 1). A forged cross-site request only works by riding credentials the browser attaches automatically. A page on another origin can send a `Bearer` header only with a value it picked itself, and without a real token that request gets 401. The safety comes from ignoring the cookie, not from the absence of CORS.

`FilesController` serves only GET requests, which are never checked for CSRF.

### 3. `Current` knows the user, the credential and the reachable projects

`Current` gains an `api_token` attribute alongside `session`. Its methods:

- `user` returns the session's user or the token's user.
- `projects` returns `user.projects.kept`, narrowed to `where(id: api_token.project_id)` when a token authenticated the request.

The four scoping points switch from `Current.user.projects.kept` to `Current.projects`, and `FilesController#visible?` checks avatars against the members of `Current.projects`. Request-time scoping is the first line of defense. Deleting tokens when access ends (decision 8) is the second.

Session-only code keeps using `Current.session` and `Current.user` directly. Examples are the teammates list, statistics and the password change, which reads `Current.session.id`.

### 4. Actions opt in to tokens, and the method decides the access needed

`ApiTokenAuthentication` adds a class macro, `allow_token_access only: %i[...]`, which accumulates a set of actions in a `class_attribute`. The set starts empty, and `Api::BaseController` opens `route_not_found` so unknown paths still answer 404.

After finding the token, the concern refuses:
- an action outside the set, with 403 `token_not_allowed`;
- any method other than GET or HEAD from a read-only token, with 403 `insufficient_scope`.

Deriving the access level from the method is sound because `security-baseline` already forbids state changes on GET and HEAD, and `RequestForgeryTest` enforces that.

These actions are opened (spec api-tokens, "Endpoints available to tokens"):

| Controller | Actions |
|---|---|
| `Api::ProjectsController` | `index`, `show` |
| `Projects::BoardsController` | `show` |
| `Projects::MembersController` | `index` |
| `Projects::TasksController` | all |
| `Projects::Tasks::*Controller` (placement, subtasks, completion, label, sprint, comments) | all |
| `Api::CommentsController` | all |
| `Projects::LabelsController` | all |
| `Projects::MilestonesController` | all |
| `Projects::Milestones::RecoveriesController` | all |
| `Projects::SprintsController` | all |
| `Projects::Sprints::*Controller` | all |
| `Api::MeController` | `show` |
| `FilesController` | `show` |

Two tests guard the list:
- A route-table test sends a `Bearer` request to every API route whose action is not opened, and expects 403 with no change.
- A snapshot test compares the set of opened actions with the list above, so opening a new action shows up as a reviewed change to a test.

Board columns (`StatusesController`) stay session-only. The user asked for "no administration" through tokens, and columns are the board's structure. They can be opened later without changing anything else.

- *Alternative: a deny list of administrative actions.* Rejected. Every endpoint added later would be reachable by tokens by default.
- *Alternative: separate scope names per resource (`tasks:write`, `comments:read`, ...).* Rejected for now. Read or read-write per project covers the stated uses. Finer scopes can later replace the `access` column without changing how requests are authenticated.

### 5. One project per token

`api_tokens.project_id` is a required column. There is no join table.

- *Alternative: several projects per token.* Deferred. It needs a join table, a multi-select in the form, and a choice between per-token and per-project access. Widening later is a plain migration (create the join table and copy `project_id` into it) and existing tokens keep working. Narrowing later would break every multi-project token already issued.
- *Alternative: tokens that reach all of the user's projects, including future ones.* Rejected. Joining a project would silently widen what an existing token can reach.

### 6. Token value and storage

The value is `glnr_` followed by `SecureRandom.base58(40)`, about 234 bits of randomness. Base58 has no `-`, so double-clicking selects the whole value, and the prefix lets secret scanners and log reviewers recognise it.

The `api_tokens` table has these columns:
- `user_id` and `project_id`, both foreign keys with indexes;
- `name`;
- `access`, an enum of `read` and `read_write`;
- `token_digest`, a SHA-256 hex digest with a unique index;
- `last_characters`, the value's last four characters;
- `expires_at`, indexed;
- `last_used_at` and timestamps.

Lookup is `ApiToken.active.find_by(token_digest: Digest::SHA256.hexdigest(value))`. `User` and `Project` get `has_many :api_tokens, dependent: :delete_all`.

- *Alternative: bcrypt digests.* Rejected. A slow hash protects low-entropy secrets such as passwords. For a 234-bit random value it adds nothing, and it prevents an indexed lookup.
- *Alternative: an HMAC keyed by `secret_key_base`.* Rejected. It ties every token to that key's rotation and gives no benefit for random values.
- *Alternative: `has_secure_token`, or signed tokens from `generates_token_for`.* Rejected. The first stores the value in plain text. The second cannot be listed or revoked one by one.

### 7. Password re-entry shares the sign-in lockout

`User#verify_reentered_password(password)` handles the password check for both forms:
- When the account is locked, it returns false without counting the attempt.
- When the password is wrong, it calls `register_failed_sign_in!` and returns false. The tenth failure locks the account and sends the unlock email.
- When the password is correct, it calls `reset_failed_sign_ins!` and returns true.

Both `Api::Me::PasswordsController#update` and `Api::Me::ApiTokensController#create` check the password before anything else. A refusal is always a 422 error on `current_password` with the same message, whether the account is locked or the password is wrong. The password change then saves the new password without `password_challenge`, since the challenge already happened.

The unlock email currently says "too many failed sign-in attempts". Its `en` and `ru` text becomes "too many failed password attempts", because attempts in settings now count too.

### 8. Revocation happens where access ends

- **Password changed or reset.** An `after_update_commit` callback on `User` deletes all of the user's tokens when `password_digest` changed. This covers settings, reset and the console. Sessions keep their explicit per-controller handling, because a password change must keep the current session. Tokens have no such exception.
- **Leaving or being removed.** `Project#remove_member!` already handles both, so it deletes `api_tokens.where(user:)` in its transaction.
- **Archiving.** `Project#archive!` deletes all of the project's tokens.

Deleting tokens, on top of request-time scoping, means a token never comes back to life when its owner rejoins a project or an operator restores an archived project. It also keeps the token list honest.

### 9. Lifetime, last use and purging

- **Expiry.** `POST /api/me/api_tokens` takes `expires_in_days`, an integer from 1 to 365, and stores `expires_at = Time.current + days`. Taking days rather than a date avoids time-zone questions. The client only offers 7, 30, 90 and 365.
- **Active tokens.** `ApiToken.active` is `where(expires_at: Time.current..)`. Only active tokens authenticate, are listed or count toward the limit of 20.
- **Last use.** Authentication updates `last_used_at` with `update_column` when it is empty or more than an hour old, the same rule `Session` uses for touches.
- **Purging.** `PurgeExpiredApiTokensJob` deletes expired rows daily at 3:15am, from `config/recurring.yml`.

### 10. Token management endpoints

`resources :api_tokens, only: %i[index create destroy], module: :me` goes under `resource :me`. These actions are not opened to tokens. `create` works in this order:

1. rate limit;
2. password re-entry (decision 7);
3. the project, looked up with `Current.user.projects.kept.find_by(id:)`, giving 422 on `project_id` when it is missing;
4. the limit of 20 active tokens, giving 422 on `base` when it is reached;
5. model validations: name 1 to 100 characters, `access` in the enum, expiry in range.

It answers 201 with the serialized token plus `token`, the plain value. No other response contains the value. `destroy` uses `Current.user.api_tokens.find`, so another user's id is a 404.

### 11. Rate limits

- **Creation.** `rate_limit_per_user to: 10, within: 1.hour, only: :create, scope: "api_tokens"`.
- **Requests.** The concern declares `rate_limit to: 300, within: 1.minute, by: -> { Current.api_token.id }, if: -> { Current.api_token }, scope: "api_token_requests"`. The concern is included after `require_authentication` is declared, so the limit runs after the token is known. The fixed scope makes API and file requests share one counter per token. Session requests are not limited.

### 12. Error codes

`Api::BaseController::MESSAGES` gains:
- `invalid_token` (401): "The API token is missing, invalid or expired."
- `token_not_allowed` (403): "This action is not available with an API token."
- `insufficient_scope` (403): "This API token is read-only."

`FilesController` answers token failures with bare 401 or 404 statuses, as it is not a JSON endpoint.

### 13. Settings screen

The new route is `/settings/api-tokens` (`settings-api-tokens`), served by `ApiTokensSettingsPage.vue` and linked from a third tab in `SettingsTabs.vue`.

- **Form.** Name, a project select from the projects store, read-only or read-write radio buttons, an expiry select (7, 30, 90 or 365 days) and the current password.
- **New value.** It is kept only in the page's component state, shown in a read-only field, and copied with `navigator.clipboard.writeText`, which needs no CSP change. Leaving the page drops it.
- **Revoking.** It goes through the existing `ConfirmDialog`.
- **Password warning.** `SecuritySettingsPage` gains a line saying that changing the password revokes all API tokens.
- **API wrapper.** It lives in `api/apiTokens.ts`.

## Risks / Trade-offs

- [Someone holding a hijacked session locks the account by entering wrong passwords in settings] → They can already act as the user. The lock lasts an hour, and the unlock email goes to the real owner, which also warns them.
- [Integrations break without notice when the owner changes their password] → This is intended. The password form says so before the change, and the token list is empty afterwards.
- [A new endpoint is opened to tokens without noticing that it exposes data from other projects] → Endpoints are session-only by default, and the snapshot test turns every opening into a reviewed change.
- [A token leaks into a CI log or a repository] → The `glnr_` prefix makes it findable by secret scanning, the expiry is at most a year, and revoking it takes effect on the next request.
- [Request-time scoping is missed somewhere a lookup does not go through `Current.projects`] → All four existing scoping points move to `Current.projects`. The spec scenarios for other projects of the owner run against each opened controller family.
- [A shared rate-limit counter in Solid Cache adds a write for every token request] → This is acceptable at the expected volume. The limit applies only to token requests.

## Migration Plan

1. Add the `api_tokens` table in an additive migration. Rolling back drops the table, and all tokens are lost.
2. Deploy. Wrong current passwords on the password-change form start counting toward lockout immediately, so this belongs in the release note.
3. Add `purge_expired_api_tokens` to `config/recurring.yml` for production. Development inherits it through the existing alias.

## Open Questions

- The per-token limit of 300 requests per minute is a starting value. It is a constant and can be tuned once real integrations exist, without changing anything else.
