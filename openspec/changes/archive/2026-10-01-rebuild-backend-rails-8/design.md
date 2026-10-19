## Context

See proposal.md (Why). Facts that shape the approach:

- Current code: Ruby 2.5.7 / Rails 5.2.6, ~2.3k lines of Ruby across 25 controllers, 23 models, a few services and mailers. There are 84 lines of tests and no test methods. Ruby 2.5 does not build cleanly on the development machine (arm64 macOS, Ruby 3.4 installed).
- There is **no production database or user data** to preserve, and no deployment configuration in the repository.
- The Vue SPA in `app/javascript` is rebuilt in the follow-up change `rebuild-frontend-vue-3`, which consumes the API defined here.
- Target versions were resolved and scanned on 2026-10-01: Rails 8.1.4, bcrypt 3.1.22, Puma 8.0.2, Solid Queue 1.7.0, sentry-ruby/rails 7.1.0. The final 122-gem lock had 0 OSV advisories at that time. It excludes Devise, OmniAuth, vite_rails and acts_as_paranoid (Decisions 3, 5 and 8).
- The Rails 8.1.4 authentication generator provides:
  - `User` (`has_secure_password`, normalized `email_address`), `Session` and `Current`;
  - an `Authentication` concern that stores the requested URL before redirecting to sign-in;
  - `SessionsController` with `rate_limit to: 10, within: 3.minutes`, using `User.authenticate_by`;
  - `PasswordsController` with reset tokens that expire after 15 minutes, are tied to the password salt, and destroy all sessions on reset.
- The generator does **not** provide sign-up, email confirmation, lockout or change-password.
- The repository is hosted on GitHub (`fobiasmog/goalner`).

## Goals / Non-Goals

**Goals:**
- A freshly generated Rails 8.1 app that implements the specs in this change, with every security requirement enforced in shared code paths rather than per endpoint.
- A test suite that maps spec scenarios to request, model and system tests, and CI that blocks known-vulnerable dependencies.
- A small, conventional dependency set: Rails defaults first, gems only where they remove substantial risk or code.

**Non-Goals:**
- Hosting, deployment pipeline and production file-storage provider. Rails 8 defaults (Kamal, Thruster) are generated but not configured.
- Real-time updates (ActionCable is removed), multi-factor authentication, account deletion or data export, an admin UI for announcements. All are possible later and are not required by the specs.
- The SPA itself. This change only serves it and defines its API.

## Decisions

### 1. Rebuild with `rails new` rather than upgrading step by step
An in-place upgrade means seven Rails hops (5.2 → 8.1), each needing a bootable environment starting on Ruby 2.5, and no tests to catch regressions. Because there is no data, a fresh app with ported domain logic is cheaper and leaves no legacy configuration behind.
- The current tree is tagged `legacy-2021` and moved with `git mv` into `legacy/`, where nothing loads or builds it. It stays there as porting reference and is deleted at the end of `rebuild-frontend-vue-3`.
- The app is generated with PostgreSQL and Rails 8.1 defaults, minus Action Cable, Action Text, Action Mailbox, Hotwire, importmap and jbuilder.
- *Alternative considered:* stepwise upgrade. Rejected for the reasons above.

### 2. Ruby 4.0, with 3.4 as fallback
Ruby 4.0.x is the current stable line. The gem set was resolved on Ruby 3.4. If any gem fails on 4.0 during setup, pin 3.4.x (supported until 2028) and record the blocker. `.ruby-version` and the Gemfile `ruby` directive are the single source of the version.

### 3. Rails 8 authentication generator, extended in place (no Devise, no third-party sign-in)
`bin/rails generate authentication` is the base, and its code is kept and edited, not wrapped. With Google sign-in out of scope, Devise's main advantage is gone. The missing pieces are small when built on Rails primitives (`generates_token_for`, `authenticate_by`, `rate_limit`). The application owns all of its authentication code, with no Warden or Devise internals.

What we add on top of the generator:
- **Sign-up** (`RegistrationsController`): name, email, password.
  - Validation is `length: { minimum: 12 }`. `has_secure_password` already rejects passwords over 72 bytes, because of the bcrypt limit.
  - An already-registered email gets the normal "check your email" response, plus an "attempted registration" email to the existing owner (spec user-auth, non-enumeration).
- **Email confirmation:**
  - `confirmed_at` column, and `generates_token_for :email_confirmation, expires_in: 24.hours { email_address }`, so the token stops working once the address changes.
  - `SessionsController#create` refuses unconfirmed users after a successful password check and offers a re-send.
- **Lockout:**
  - `failed_login_attempts` and `locked_until` on `users`.
  - `SessionsController#create` looks up the user by email to increment the counter. Locking happens at 10 attempts for one hour and emails an unlock link (`generates_token_for :unlock, expires_in: 1.hour { locked_until }`).
  - A locked account gets the same generic error as a wrong password. A successful sign-in resets the counter.
- **Change password:** `PasswordChangesController` requires `authenticate(current_password)` and destroys every session except `Current.session`.
- **Password reset:** the generated flow is kept. The rate limit is changed to 5 per hour, and the 15-minute default lifetime is accepted (spec user-auth).
- **Password length:** 12 is a deliberate balance. NIST SP 800-63B rev. 4 asks for 15 when the password is the only factor; it's a one-line change if you want stricter.
- *Alternative considered:* Devise 5. It provides confirmable/lockable out of the box, but adds Devise + Warden + responders, plus its conventions and generated views to override. The custom code it saves is about 150 lines, which the request tests cover scenario by scenario.

### 4. Server-side sessions with idle expiry and no IP storage
- **Session records:** the generated `sessions` table keeps `user_id`, `user_agent` and timestamps. The generated `ip_address` column is removed, so no IP addresses are stored.
- **Idle expiry:**
  - `resume_session` rejects sessions whose `updated_at` is older than 14 days.
  - It touches the session at most once per hour, and refreshes the cookie expiry at the same time.
  - The generator's 20-year `cookies.signed.permanent` becomes `expires: 14.days`, still `httponly` and `same_site: :lax`. `force_ssl` adds `Secure`.
- **Sign-out:** `DELETE /session` destroys the session record, so a replayed cookie finds no session.
- **Clean-up:** expired session rows are deleted by a daily Solid Queue recurring job.
- **API requests:** `Api::BaseController` uses the same `Authentication` concern, but overrides `request_authentication` to return 401 JSON instead of redirecting. HTML requests still store the return URL and redirect to sign-in, which is what the SPA's "reload on 401" relies on.

### 5. Server-rendered public pages; the SPA is mounted at `/app`
- **Public pages:** the landing page, authentication pages and the invitation landing are ERB with Propshaft-served CSS. They need no JavaScript, so the public surface has no SPA dependencies and works under the strict CSP.
- **SPA mount:** `GET /app/*path` renders a minimal layout with `<meta name="csrf-token">` and the Vite entry tags. The SPA bootstraps by calling `GET /api/me`, so no inline data is needed.
- **Vite integration is a hand-written `ViteHelper` (~40 lines, unit-tested).**
  - In production it reads Vite's `manifest.json` (built to `public/vite/`) and emits `<script type="module">`, `modulepreload` and stylesheet tags for an entry.
  - In development it emits tags pointing at the Vite dev server (`@vite/client` + the entry).
  - `bin/dev` starts Puma and `vite` together with a small shell script.
- *Alternative considered:* `vite_rails`. It works, but it adds four gems (`vite_ruby`, `dry-cli`, `rack-proxy`, …) and an npm dev dependency (`vite-plugin-ruby`). That goes against the frontend's minimal-dependency rule. It stays the fallback if the helper ever becomes a burden.

### 6. Resource-oriented JSON API under `/api`, no versioning
One first-party client ships in the same deploy, so a version prefix adds nothing. Route shape (finalised in code; specs define behaviour):

```
GET    /api/me                      PATCH /api/me     PUT /api/me/avatar    PATCH /api/me/password
GET    /api/teammates
GET    /api/projects                POST  /api/projects
GET    /api/projects/:id            PATCH /api/projects/:id   DELETE /api/projects/:id   (archive, owner)
GET    /api/projects/:id/board
DELETE /api/projects/:id/membership                          (leave)
GET    /api/projects/:id/members    DELETE /api/projects/:id/members/:user_id            (owner)
GET|POST /api/projects/:id/invitations   DELETE /api/projects/:id/invitations/:id
POST   /api/projects/:id/statuses   PATCH|DELETE /api/projects/:id/statuses/:id         (title, position)
GET    /api/projects/:id/tasks?view=board|backlog|archived   POST /api/projects/:id/tasks
GET|PATCH|DELETE /api/projects/:id/tasks/:ref                (ref = id or sequence number)
PATCH  /api/projects/:id/tasks/:id/placement                  { status_id | null, position }
GET|POST /api/projects/:id/tasks/:id/subtasks
PUT|DELETE /api/projects/:id/tasks/:id/label                  PUT /api/projects/:id/tasks/:id/sprint
GET|POST /api/projects/:id/tasks/:id/comments                 PATCH|DELETE /api/comments/:id
GET|POST /api/projects/:id/labels
GET|POST /api/projects/:id/milestones    GET|DELETE /api/projects/:id/milestones/:id    POST .../:id/recover
GET|POST /api/projects/:id/sprints?view=available|archived   POST .../:id/activation    POST .../:id/archive
GET    /api/statistics/overview?user_id=   GET /api/statistics/deadlines?user_id=
GET    /api/announcements           DELETE /api/announcements                          (dismiss all)
POST   /api/feedback
GET    /files/:signed_id[/variant]  (authorised attachment and avatar delivery)
GET    /invitations/:token          POST /invitations/:token/acceptance                  (HTML)
```

- **Serialization:** plain serializer objects (POROs) build JSON. No jbuilder or serializer gem.
- **Base controller:** `Api::BaseController` holds the error envelope (spec security-baseline). It maps `RecordNotFound` to 404, `RecordInvalid` to 422 with field errors, a custom `Forbidden` to 403, and anything else to 500 with a generic message reported to Sentry.
- **CSRF:** stays on everywhere. `protect_from_forgery with: :exception` is the default, and the SPA sends `X-CSRF-Token`.

### 7. Authorization through scoping concerns and model validations, no policy gem
- **Membership lookup:** `ProjectScoped` loads `@project = Current.user.projects.kept.find(params[:project_id])`. A failed lookup is a 404, which also covers "not a member". Owner-only actions call `require_owner!`, which raises 403.
- **Client-supplied ids:** they are validated in the models, so no endpoint can bypass the checks. A task's `status`, `milestone` (not deleted), `label`, `sprint` and `assignee` (a current member) must belong to the task's project.
- **Statistics:** the query intersects the requester's and the subject's project ids (spec statistics).
- **Files:** `FilesController` finds the attachment, resolves its record (comment → task → project, or avatar → user), checks membership or teammate relationship, then streams it with `disposition: :attachment`. Active Storage's public routes are disabled (`config.active_storage.draw_routes = false`).
- *Alternative considered:* Pundit or ActionPolicy. That's an extra dependency and pattern for about 15 controllers. Revisit if roles grow beyond owner/member/admin.

### 8. Fresh schema
Explicit foreign keys, `NOT NULL` where the specs require values, and unique indexes for invariants:

| Table | Notes |
|---|---|
| `users` | `email_address` (normalized, unique), `password_digest`, `confirmed_at`, `failed_login_attempts`, `locked_until`, `name`, `lang` (`en`/`ru`), `contact_links` jsonb, `admin` boolean |
| `sessions` | `user_id`, `user_agent`, timestamps (no `ip_address`; see Decision 4) |
| `projects` | `title`, `short_name`, `owner_id`, `last_task_number`, `archived_at` |
| `memberships` | `project_id`, `user_id`; unique pair |
| `invitations` | `project_id`, `inviter_id`, `email`, `token_digest`, `expires_at`, `accepted_at`, `revoked_at`; unique pending invitation per `(project_id, lower(email))` |
| `statuses` | `project_id`, `title`, `color`, `position`, `done` |
| `tasks` | `project_id`, `number` (unique per project), `title`, `description` (text, Markdown), `creator_id`, `assignee_id`, `status_id` (null = backlog), `position`, `parent_id` (subtask link), `sprint_id`, `milestone_id`, `label_id`, `origin_task_id` (sprint carry-over lineage), `deadline`, `important`, `completed_at`, `archived_at` |
| `sprints` | `project_id`, `title`, `starts_on`, `ends_on`, `active`, `archived_at`; partial unique index on `project_id WHERE active` |
| `milestones` | `project_id`, `title`, `deleted_at` |
| `labels` | `project_id`, `title`; unique on `(project_id, lower(title))` |
| `comments` | `task_id`, `author_id`, `body` (Markdown), `deleted_at`; attachments via Active Storage |
| `announcements`, `announcement_dismissals` | `body` (Markdown), `welcome` flag |

How this simplifies the old schema:
- The old join tables `task_projects`, `task_links`, `sprint_tasks`, `sprint_tasks_chains` and `task_labels` become plain columns. The specs require exactly one project, at most one parent, at most one sprint and at most one label per task.
- Task numbers come from an atomic `UPDATE projects SET last_task_number = last_task_number + 1 ... RETURNING`. That removes today's `max(iid) + 1` race and its off-by-one (the first task got number 2).
- Soft deletion uses explicit `archived_at`/`deleted_at` columns with named scopes instead of `acts_as_paranoid`. The specs give each "archive" its own meaning, and explicit scopes avoid default-scope surprises; the gem is dropped. `acts_as_list` is kept for contiguous positions.

### 9. Board placement
- **Moving a task:** `PATCH .../placement` runs in one transaction. It locks the affected status rows (`SELECT ... FOR UPDATE`), moves the task with `acts_as_list` `insert_at`, and sets or clears `completed_at` depending on whether the target is the done status.
- **Column changes:** inserting a new status puts it before the done status. Reordering or deleting recomputes `done` for the last status in the same transaction. Deleting a status nulls `status_id` on its tasks (moving them to the backlog) before removing the status.

### 10. Solid Queue in the primary database; Mission Control for administrators
Jobs are used for mail delivery and invitation clean-up.
- **Single database:** Solid Queue tables live in the primary database, so there is no Redis and no second database to run. At this scale a single database is enough; Rails' multi-database queue setup remains an option.
- **Jobs dashboard:** Mission Control Jobs is mounted at `/admin/jobs` inside a routing constraint that resolves `Session.find_by(id: cookies.signed[:session_id])` with the same idle-expiry rule, then checks `user.admin?`; everyone else gets a 404. The admin flag is set from the console.
- **Recurring jobs:** expired invitations and idle sessions are purged.

### 11. Rate limiting with the Rails 8 built-in
- **Mechanism:** `rate_limit` in controllers, backed by `Rails.cache` (Solid Cache in production, shared across processes). The generated sessions and passwords controllers already use it; their limits are adjusted to the spec values and added to registration, confirmation re-send and unlock re-send. The numbers are the ones in the specs (user-auth, project-membership, feedback).
- **Limit keys:** anonymous endpoints are limited per IP address, signed-in endpoints per user id.
- **Behind a proxy:** trusted proxies (private networks plus `TRUSTED_PROXIES`) are configured so the real client IP and scheme are used. `config.assume_ssl` stays off, because it marks every request as HTTPS and would disable the HTTP→HTTPS redirect that security-baseline requires.
- *Alternative considered:* rack-attack. That's an extra dependency, and the built-in covers the specs.

### 12. Files and images on vips
- **Processing:** `image_processing` with `ruby-vips` replaces ImageMagick (`mini_magick`). It's faster and has a smaller attack surface. Default avatars are a random solid-colour 256×256 PNG generated with vips.
- **Upload checks:** a small custom validator checks `blob.content_type` (detected from the content by Marcel when the blob is created) and `byte_size` against each allowlist in the specs. No validation gem is added.
- **Avatars:** re-encoded to 256×256 WebP on upload.
- **Storage:** the Disk service in development and test. The production storage service is deferred (see Non-Goals) and needs no code change.

### 13. Security headers and CSP in initializers
- **CSP:** `content_security_policy.rb` implements the security-baseline policy. The Sentry ingest host comes from credentials and is added to `connect-src`. `form-action` is `'self'` only, since there is no third-party sign-in. Development adds the Vite dev server origin for HTTP and WebSocket.
- **Other headers:** `permissions_policy.rb` sets the Permissions-Policy. `config.force_ssl = true` with HSTS for one year including subdomains.
- **Log filtering:** `filter_parameter_logging.rb` extends the defaults with `:email, :body, :description, :message`.

### 14. Mail over SMTP; Sentry with personal data disabled
- **Mail:** ActionMailer over SMTP, configured from credentials and environment variables, replaces `mailgun-ruby` and its `rest-client` dependency tree. All mail uses `deliver_later`. Templates exist in `en` and `ru` and follow `user.lang`.
- **Sentry:** `sentry-ruby` + `sentry-rails` with personal data collection off, plus a `before_send` that strips request bodies, cookies and IP addresses. sentry-ruby 7.1 deprecates `send_default_pii`, so this is configured through its replacement, `config.data_collection` (user info, cookies, HTTP bodies, frame variables and query data all off). Users are identified by id only.

### 15. Tests and CI
- **Tests:** Minitest with fixtures, as in the Rails default.
  - Request tests cover every API scenario in the specs. Authorization and CSRF cases are tested explicitly; request tests run with forgery protection on in a dedicated test class.
  - Model tests cover invariants such as numbering, placement and the done column.
  - System tests (Capybara with headless Chrome) cover sign-up, confirmation, sign-in, lockout and unlock, reset, change password, sign-out, idle session expiry and invitation acceptance.
- **CI (GitHub Actions):** a `test` job (Postgres service) and a `security` job:
  - `brakeman --no-pager` with a reviewed `config/brakeman.ignore`;
  - `bundler-audit check --update`;
  - `osv-scanner` over `Gemfile.lock` and `package-lock.json`, with ignores carrying a `reason` and an `ignoreUntil` date;
  - `rubocop`.
- **Dependabot:** weekly updates for bundler, npm and github-actions.
- **Secrets:** everything lives in `config/credentials/production.yml.enc`, with keys documented in `config/credentials.example.yml`. The production database uses `DATABASE_URL` with no default.

## Risks / Trade-offs

- **[Scope creep in a rebuild]** → Port only behaviour that the specs describe; anything else goes to a follow-up change. Spec scenarios define "done".
- **[Ruby 4.0 gem incompatibility]** → Pin Ruby 3.4.x and record why (Decision 2).
- **[Hand-written authentication extensions are security-sensitive]** (sign-up, confirmation, lockout, change password, session expiry) → They're built only on Rails primitives (`generates_token_for`, `authenticate_by`, `has_secure_password`, `rate_limit`), kept to about 150 lines, covered by request and system tests for every user-auth scenario, and checked by brakeman. They're implemented and tested before any domain work is built on top.
- **[Behaviour changes versus the old app]** (columns inserted before Done; deleting a column moves tasks to the backlog instead of deleting them; carry-over copies only unfinished tasks; subtasks one level deep; invitations need acceptance; project settings owner-only) → Deliberate and captured in the specs. Review them when reading this change.
- **[Rate-limit and job state in PostgreSQL]** → Fine at current scale. Solid Cache and Solid Queue can move to dedicated databases without code changes.
- **[Strict CSP breaks a client library]** → tiptap injects a `<style>` tag by default. The frontend change disables `injectCSS` and ships its CSS in the bundle. The CSP spec has tests asserting the header.
- **[The SPA is unusable between this change and the frontend change]** → Acceptable: there are no users. The public pages and API work and are tested on their own.
- **[Old Google OAuth client still exists with contacts consent]** → It's no longer used; the owner deletes it in Google Cloud Console (task 1.2).

## Migration Plan

No data migration: this is a greenfield deployment.
- Rollback during development: check out tag `legacy-2021`.
- The first production deployment happens after `rebuild-frontend-vue-3`. Hosting is decided separately.

## Open Questions

- Production hosting and Active Storage service (Disk on a volume or S3-compatible). Deferrable: neither changes code structure.
- SMTP provider and sending domain (SPF/DKIM/DMARC). Configuration only.
