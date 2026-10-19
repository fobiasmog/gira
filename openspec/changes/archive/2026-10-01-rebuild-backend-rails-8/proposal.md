## Why

The backend is frozen at Ruby 2.5.7 / Rails 5.2.6 (both end-of-life since 2021–2022), cannot be booted on current machines, and has no tests. An exact-version scan of `Gemfile.lock` against OSV.dev found 25 vulnerable gems with 137 distinct advisories (5 critical: rack, puma request smuggling, nokogiri/libxml2, activerecord, activestorage). A manual review found application-level defects that no upgrade would fix: CSRF protection disabled for the whole API, state-changing GET endpoints, an invite flow that creates accounts and emails plaintext passwords for arbitrary addresses, an unauthenticated `/sidekiq` dashboard, an over-privileged Google OAuth scope with tokens stored in plaintext, and missing authorization checks on task references and statistics. There is no production data or database to preserve, so the cheapest safe path is a rebuild on Rails 8.1 that ports the domain logic and fixes these defects by design.

## What Changes

- **BREAKING** Replace the Rails 5.2 application with a freshly generated Rails 8.1 application on Ruby 4.0, porting models, services and mailers. The old code is kept under `legacy/` (not loaded or built) as reference until the frontend rebuild completes.
- **BREAKING** New database schema from fresh migrations; no data migration. Dead tables (`categories`, `inboxes`, `moods`, legacy `subtasks`, `task_types`, `task_projects`) and OAuth token columns are dropped; task descriptions and comments are stored as Markdown text.
- **BREAKING** Redesigned JSON API under `/api`: resource-oriented routes with correct HTTP verbs (no state change on GET), CSRF verification on every non-GET request, consistent error envelope that never exposes exception messages.
- **BREAKING** Email-and-password authentication only, built on the Rails 8 authentication generator (database-backed sessions, `has_secure_password`, built-in password reset). We add sign-up, email confirmation, account lockout and change-password on top. Passwords need at least 12 characters, and sign-in, sign-up, password reset and invitations are rate-limited. Google sign-in is removed, along with every third-party sign-in.
- Project invitations replace account auto-creation: invitees receive a tokenized link and must accept; responses never reveal whether an email is registered; no password is ever emailed.
- Authorization: every record lookup is scoped through the current user's project memberships, including foreign keys supplied by clients (status, executor, milestone, sprint, label) and teammate statistics.
- Background jobs move from Sidekiq + Redis to Solid Queue; the jobs dashboard (Mission Control) is restricted to administrators.
- Comment attachments get size and content-type limits and are served only to project members through an authenticated endpoint.
- Security baseline: strict Content Security Policy (`'self'` plus the error-tracking ingest host only), HTTPS enforcement with HSTS, secure cookies, filtered logs, error tracking with PII disabled.
- Server-rendered landing page with sign-in/sign-up forms (no SPA on public pages); the Vue SPA is served from `/app` via Vite (the SPA itself is rebuilt in the `rebuild-frontend-vue-3` change).
- Test suite (model, request and system tests) and CI with security gates: brakeman, bundler-audit, OSV scan of both lockfiles, RuboCop.
- Removed: Devise and Google sign-in (omniauth-google-oauth2, with its oauth2/jwt/faraday chain), Sidekiq/Redis, sentry-raven, influxdb-rails, mailgun-ruby (replaced by SMTP), mini_magick (replaced by vips), acts_as_paranoid (replaced by explicit archive columns), Sprockets, sass-rails, uglifier, Webpacker, ActionCable, Spring, third-party analytics (Yandex Metrika, Google Analytics, Hotjar), and the debug endpoint `send_test_mail`.

## Capabilities

### New Capabilities
- `user-auth`: registration, email confirmation, sign-in/out, sessions, lockout, password reset and change, rate limits.
- `user-profile`: name, language, contact links, avatar.
- `projects`: create, list, view, rename, leave/archive projects; project short names.
- `project-membership`: invitations, acceptance, member listing and removal, ownership rules.
- `project-board`: board statuses (columns), their ordering and the done column, task placement and ordering on the board, backlog.
- `tasks`: task lifecycle, fields, subtasks, assignment, Markdown descriptions, archive and restore.
- `sprints`: sprint creation, activation, archiving, and carrying tasks over.
- `milestones`: milestone creation, progress, deletion and recovery.
- `labels`: project labels and their assignment to tasks.
- `comments`: Markdown comments on tasks, editing/deleting own comments, attachments.
- `notifications`: assignment emails and in-app announcements.
- `statistics`: personal dashboard of assigned tasks and upcoming deadlines, including teammates' views.
- `feedback`: in-app feedback sent to the operators.
- `security-baseline`: cross-cutting rules for CSRF, CSP, transport security, error handling, rate limiting, uploads, admin surfaces and dependency hygiene.

### Modified Capabilities
<!-- None: the repository has no existing specs. -->

## Impact

- Code: every file under `app/`, `config/`, `db/`, `lib/`, `bin/`, `test/`; `Gemfile`/`Gemfile.lock` regenerated. The old `app/javascript` SPA stops building at this point and is moved to `legacy/` until `rebuild-frontend-vue-3` replaces it.
- API: all endpoints change shape or verb; the frontend rebuild consumes the new contract.
- Dependencies: 123 locked gems (25 vulnerable) → ~122 locked gems on current versions with 0 known advisories at planning time (2026-10-01).
- Infrastructure: Redis no longer required; PostgreSQL also hosts Solid Queue tables and sign-in sessions. SMTP credentials, new Sentry projects and a new `secret_key_base` are required. The previous Google OAuth client (consented for `contacts.readonly`) is no longer used and must be deleted by the owner.
- Deployment configuration is out of scope (Rails 8 defaults are kept; hosting decided separately).
