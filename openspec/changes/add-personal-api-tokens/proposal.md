# Proposal

## Why

The API can only be used by the web client: every request is authenticated by the session cookie and must carry the page's CSRF token. Scripts and integrations (a CI job that opens tasks, a bot that posts comments, a sync with another tracker) have no way to call the API on a user's behalf. Users need a credential they can hand to such a program that is narrower than their account and that they can revoke, while the web client keeps working exactly as it does today.

## What Changes

- Signed-in users can create personal API tokens in settings. A token belongs to its creator and is limited to:
  - one project the creator is a member of;
  - read-only or read-write access;
  - an expiry of 1 to 365 days, which is required.
  Creating a token requires re-entering the current password. The token is shown once and only its digest is stored. Users can list and revoke their tokens. A user has at most 20 active tokens.
- API requests can be authenticated with `Authorization: Bearer <token>`. The header decides the mode:
  - **With the header:** only the token authenticates the request. The cookie is ignored and no CSRF token is needed.
  - **Without the header:** the request is authenticated by the session cookie with CSRF, as today.
  An unknown, expired or revoked token gets HTTP 401. It never falls back to the cookie.
- A token reaches only its own project, and only while its owner is still a member. GET requests need read access. Every other method needs read-write access.
- Only task-tracker endpoints accept tokens, through an explicit per-action allowlist: tasks, subtasks, placements, completions, task labels and sprints, comments with attachments, labels, milestones, sprints, the board, the member list, the project itself (read) and `GET /api/me`. Everything else answers a token with HTTP 403:
  - project creation, settings and archiving;
  - members, invitations and leaving;
  - board columns;
  - profile, password, avatar and token management;
  - teammates, statistics, announcements and feedback.
  New endpoints are session-only unless they opt in.
- File downloads (`/files/...`) accept tokens, so attachments and avatars linked from API responses can be fetched.
- Tokens stop working, or are deleted:
  - when they expire;
  - when the owner revokes them;
  - when the owner's password is changed or reset (all of their tokens);
  - when the owner leaves or is removed from the token's project;
  - when that project is archived.
- **BREAKING** Wrong current passwords on the password-change form now count toward the 10-attempt account lockout. While the account is locked, the current password is refused, even when correct. Token creation follows the same rule.
- Changing or resetting the password deletes all of the user's API tokens, in addition to ending sessions as today.
- Rate limits: token creation is limited to 10 per hour per user. Requests made with a token are limited to 300 per minute per token.
- A new "API tokens" tab in settings for creating, copying (once), listing and revoking tokens.

Not included:
- tokens covering several projects (the data model can be widened later without breaking existing tokens);
- tokens that create projects, manage members or reach account settings;
- cross-origin browser access (CORS);
- email notifications about token creation or upcoming expiry;
- marking activity as made through the API.

## Capabilities

### New Capabilities

- `api-tokens`: personal API tokens. Covers creation with password re-entry, listing and revocation, Bearer authentication, project and access limits, the endpoints that accept tokens, storage and secrecy, lifetime and revocation triggers, and rate limits.

### Modified Capabilities

- `user-auth`:
  - wrong current passwords on password-change and token-creation forms count toward account lockout, and a locked account refuses them;
  - changing or resetting the password deletes all API tokens.
- `security-baseline`:
  - API requests may be authenticated by a session or by an API token;
  - token-authenticated requests are exempt from CSRF tokens and are never authenticated by the cookie.
- `web-client`: settings gain an API tokens screen.

## Impact

- **Database:** a new `api_tokens` table with these columns:
  - user, project, name, access, token digest (unique), display hint;
  - expiry, last use, timestamps.
- **Backend authentication:**
  - `Authentication` concern, `Current` (user from a session or a token, plus the set of accessible projects), `Api::BaseController` (bearer mode, CSRF exemption, allowlist macro, error codes, per-token rate limit);
  - `ProjectScoped`, `Api::ProjectsController#index`, `Api::CommentsController`, `FilesController` (scoping through `Current`);
  - every controller that accepts tokens declares it.
- **Backend account flows:** `User` (token association, password re-entry with lockout), `Api::Me::PasswordsController`, `PasswordsController#update`, `Project#remove_member!` and `Project#archive!` (delete tokens).
- **New backend files:** `ApiToken` model, `Api::Me::ApiTokensController`, `PurgeExpiredApiTokensJob` in `config/recurring.yml`.
- **Frontend:**
  - new settings tab and page;
  - `api/me.ts` or a new `api/apiTokens.ts`, `api/types.ts`;
  - `SettingsTabs.vue`, router, `en`/`ru` strings;
  - a note on the security page that changing the password revokes tokens.
- **Tests:**
  - model tests for tokens and lockout;
  - request tests for both auth modes, the allowlist (a route-table test that every non-allowlisted action refuses tokens), scoping, revocation triggers and rate limits;
  - a system test for the settings screen.
  - Existing password-change tests need the lockout cases.
