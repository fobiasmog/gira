# Tasks

## 1. Token model

- [ ] 1.1 Add a migration creating `api_tokens` with the columns, foreign keys and indexes from design.md (decision 6). Add the `ApiToken` model:
  - `access` enum `read`/`read_write`;
  - `active` scope;
  - a class method that issues a `glnr_` + `SecureRandom.base58(40)` value, storing only the SHA-256 digest and the last four characters;
  - `find_active_by_value`;
  - `touch_last_used!`, which writes at most hourly;
  - validations: name 1 to 100 characters, expiry from 1 to 365 days after creation.

  Add `has_many :api_tokens, dependent: :delete_all` to `User` and `Project`, and fixtures in `test/fixtures/api_tokens.yml`.

  Verify that `bin/rails db:migrate` updates `db/schema.rb`, that `bin/rails db:rollback && bin/rails db:migrate` succeeds, and that `test/models/api_token_test.rb` covers:
  - the value's prefix and length;
  - the stored row containing neither the value nor anything that authenticates;
  - lookup by value;
  - an expired token not being found;
  - the name and expiry bounds;
  - `last_used_at` written once within an hour.
- [ ] 1.2 Add `PurgeExpiredApiTokensJob` and schedule it in `config/recurring.yml` (production, inherited by development). Verify that `test/jobs/purge_expired_api_tokens_job_test.rb` deletes expired tokens and keeps active ones.

## 2. Password re-entry and revocation

- [ ] 2.1 Add `User#verify_reentered_password` (design.md, decision 7) and change the unlock email's `en`/`ru` text from failed sign-in attempts to failed password attempts. Verify `test/models/user_test.rb` cases for:
  - a locked account (returns false, count unchanged);
  - a wrong password (counted, and the tenth one locks and enqueues the unlock email);
  - a correct password (count reset).

  Verify that `test/mailers/mailers_test.rb` passes.
- [ ] 2.2 Make `Api::Me::PasswordsController#update` check the password with `verify_reentered_password` before saving the new password. A refusal is 422 on `current_password` with the same message whether the account is locked or the password is wrong. Verify request tests in `test/controllers/api/me/passwords_controller_test.rb` for these user-auth scenarios, and that the existing tests there still pass:
  - "Wrong current passwords in settings";
  - "Re-entered password while locked";
  - "Wrong current password".
- [ ] 2.3 Delete all of a user's API tokens in an `after_update_commit` on `User` when `password_digest` changed. Verify:
  - a `user_test.rb` case where a profile update keeps the tokens and a password update deletes them;
  - a request test for the user-auth scenario "API tokens revoked", with the current session still signed in;
  - a `test/controllers/passwords_controller_test.rb` case for "Reset completes", with the tokens deleted.
- [ ] 2.4 Delete the member's tokens for the project inside `Project#remove_member!`, and all of the project's tokens in `Project#archive!`. Verify `test/models/project_test.rb` cases for leaving, removal and archiving, each checking that the user's tokens for other projects and other members' tokens are kept.

## 3. Token authentication

- [ ] 3.1 Give `Current` an `api_token` attribute, a `user` that comes from the session or the token, and a `projects` method (design.md, decision 3). Switch `ProjectScoped#set_project`, `Api::ProjectsController#index`, `Api::CommentsController#set_comment` and `FilesController#visible?` to `Current.projects`. Verify that `bin/rails test` passes with no test changes, since session mode is unaffected.
- [ ] 3.2 Add the `ApiTokenAuthentication` concern (design.md, decisions 1, 2, 4 and 12):
  - token mode only for the `Bearer` scheme;
  - token authentication with no cookie fallback;
  - `resume_session` returning nil in token mode;
  - `skip_forgery_protection if: :bearer_token_request?`;
  - the `allow_token_access` macro;
  - 403 `token_not_allowed` and `insufficient_scope`;
  - a `last_used_at` touch;
  - the new error messages.

  Include the concern in `Api::BaseController` and open `route_not_found`. Verify that `test/integration/api_token_authentication_test.rb`, a `ForgeryProtectedIntegrationTest`, covers:
  - the api-tokens scenarios "Write without a CSRF token", "Invalid token with a valid session cookie", "Expired token", "Token in the query string" and "Web client unchanged";
  - the security-baseline scenario "Token request with a session cookie";
  - an `Authorization: Basic` header with a valid session cookie and CSRF token being authenticated by the session;
  - an unknown API path with a valid token answering 404;
  - a revoked token answering 401.
- [ ] 3.3 Add the per-token request rate limit to the concern (design.md, decision 11). Verify a test where the 301st request with one token within a minute receives 429 with no effect, another token is not affected, and session requests are not limited.
- [ ] 3.4 Declare `allow_token_access` on every controller in the design.md decision 4 table. Verify request tests covering:
  - the api-tokens scenarios "Another project of the owner", "Project list", "Comment in another project", "Read-only token writes", "Read-only token reads", "Attribution", "Member list" and "Own profile";
  - the security-baseline scenario "Foreign id with a token", using a label and a sprint from another project of the owner on a task update.
- [ ] 3.5 Add two cross-cutting tests to `test/integration/api_token_authentication_test.rb` (design.md, decision 4):
  - **Route table:** every API route whose action is not opened answers a read-write `Bearer` request with 403, and no record count changes.
  - **Snapshot:** the set of opened `controller#action` pairs equals the expected list.

  Verify that both pass. Then temporarily remove one `allow_token_access` entry and confirm that the snapshot test fails.
- [ ] 3.6 Include the concern in `FilesController` and open `show`. Check comment attachments against `Current.projects`, and avatars against the user and the members of `Current.projects`. Verify cases in `test/controllers/files_controller_test.rb` for:
  - the api-tokens scenarios "Attachment in the token's project" and "Attachment in another project";
  - a project member's avatar (200);
  - a teammate's avatar outside the token's project (404);
  - an invalid token (401).
- [ ] 3.7 Verify the "Token storage and secrecy" scenario "Logged request":
  - extend `test/integration/log_filtering_test.rb` so the log of a `Bearer` request does not contain the token value;
  - extend `test/initializers/sentry_test.rb` so an error event from a `Bearer` request carries no `Authorization` header.

## 4. Token management API

- [ ] 4.1 Add `resources :api_tokens, only: %i[index create destroy], module: :me` under `resource :me`, plus `Api::Me::ApiTokensController` and `ApiTokenSerializer`, following the order in design.md decision 10. The plain value is returned only from `create`. Verify request tests in `test/controllers/api/me/api_tokens_controller_test.rb` for:
  - the api-tokens scenarios "Successful creation", "Expiry over a year", "No expiry", "Project the user does not belong to", "Token limit", "Wrong password", "Locked account", "Listing does not reveal values", "Revoke", "Another user's token" and "Creation burst";
  - expired tokens missing from the list and not counting toward the limit.
- [ ] 4.2 Add an "API tokens" section to `README.md`. It covers where tokens are created, the `Authorization: Bearer` header, read-only versus read-write, the one-project limit, the endpoints available, the 401/403/404/429 answers, and a `curl` example that creates a task. Verify the `curl` example against the dev server with a token from task 4.1.

## 5. Settings screen

- [ ] 5.1 Add `api/apiTokens.ts` (list, create, revoke) and the `ApiToken`/`NewApiToken` types in `api/types.ts`. Verify that `npm run typecheck` passes.
- [ ] 5.2 Add `ApiTokensSettingsPage.vue` at `/settings/api-tokens`, linked from a third tab in `SettingsTabs.vue` (design.md, decision 13). Add the password-change note to `SecuritySettingsPage.vue`, and add `en`/`ru` strings. Verify:
  - `test/system/api_tokens_test.rb` covers the web-client scenarios "Create and copy", "Value not shown again", "Wrong password", "Revoke" and "Password change warning";
  - `npm test` passes, including the i18n key-parity test;
  - `test/system/accessibility_test.rb` passes with the new screen added to its pages.

## 6. Integration

- [ ] 6.1 Run the whole suite and the security gates. Verify that `bin/rails test`, `bin/rails test:system`, `npm test`, `npm run typecheck`, `npm run build`, `bin/brakeman` and `bin/bundler-audit` all pass, and `openspec validate add-personal-api-tokens --strict` reports the change as valid.
- [ ] 6.2 On the dev server, run these steps with `curl`:
  1. Create a read-only and a read-write token for one project in settings.
  2. Read that project's board with each.
  3. Create a task with the read-write token.
  4. Check that the read-only token gets 403 on creation, that another project of the same user gives 404, and that project archiving gives 403.
  5. Change the password and check that both tokens get 401 while the browser session stays signed in.

## Workflow follow-up

- Release note: wrong current passwords on the password-change form now count toward the 10-attempt lockout, and changing or resetting a password revokes all API tokens.
- Sync the delta specs and archive the change after review.
