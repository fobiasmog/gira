# security-baseline Specification

## Purpose

Defines the security rules every endpoint and page must follow — request forgery protection, authorization defaults, safe errors, browser hardening headers, transport security, operational surfaces, secrets and dependency hygiene — so that individual features cannot silently weaken them.

## Requirements

### Requirement: Safe methods never change state
GET and HEAD requests SHALL NOT create, modify or delete any data or send any email. Every state change SHALL use POST, PUT, PATCH or DELETE.

#### Scenario: Crafted GET link
- **WHEN** a signed-in user's browser loads a third-party page that embeds a GET request to any application URL
- **THEN** no data changes and no email is sent

### Requirement: Cross-site request forgery protection
Every POST, PUT, PATCH and DELETE request authenticated by a session cookie SHALL carry a valid CSRF token, in a form field or in the `X-CSRF-Token` header. Requests without a valid token SHALL be rejected with HTTP 422 and SHALL have no effect.

#### Scenario: Forged API request
- **WHEN** a third-party site makes a signed-in user's browser POST to an API endpoint without the token
- **THEN** the request is rejected with HTTP 422 and nothing changes

### Requirement: Deny by default
Every endpoint other than the landing page, authentication flows, invitation landing and health check SHALL require a signed-in user. API requests without a session SHALL receive HTTP 401 with a JSON error, not a redirect. Every record lookup SHALL be scoped to records the current user may access, and every record id supplied by a client SHALL be checked against that scope before use.

#### Scenario: Signed-out API call
- **WHEN** a request without a session calls an API endpoint
- **THEN** the response is HTTP 401 with a JSON error body

#### Scenario: Foreign id in a payload
- **WHEN** a client submits an id of a record from a project the user does not belong to as any field of a request
- **THEN** the request is rejected and nothing is changed

### Requirement: Safe error responses
API errors SHALL use one JSON envelope containing an error code and a human-readable message: 401 for missing authentication, 403 for an authenticated member lacking a permission, 404 for missing or inaccessible records, 422 with per-field messages for validation errors, 429 for rate limits, and 500 for unexpected errors. Responses SHALL NOT contain exception messages, stack traces, SQL or internal class names.

#### Scenario: Unexpected exception
- **WHEN** an unexpected exception occurs while handling an API request
- **THEN** the response is HTTP 500 with a generic message, and the exception is recorded only in server-side logs and error tracking

### Requirement: Content Security Policy
Every HTML response SHALL carry a Content Security Policy that allows scripts, styles, fonts and frames only from the application's own origin, allows images only from the own origin plus `data:` and `blob:`, allows network connections only to the own origin and the configured error-tracking ingest host, allows form submissions only to the own origin, forbids plugins (`object-src 'none'`), restricts `base-uri` to the own origin, and forbids framing (`frame-ancestors 'none'`). The policy SHALL NOT contain `'unsafe-inline'` or `'unsafe-eval'` for scripts. In development only, the policy SHALL additionally allow the local frontend dev server origin (HTTP and WebSocket) and a per-request nonce for `style-src`, exposed to the page so the dev server can inject stylesheets, and nothing else.

#### Scenario: Production policy has no dev server
- **WHEN** an HTML page is requested in production
- **THEN** the policy does not mention any localhost origin and carries no nonce

#### Scenario: Development styles from the dev server
- **WHEN** a page of the client is requested in development
- **THEN** its `style-src` carries a nonce generated for that response, and the stylesheets the dev server injects with that nonce are applied

#### Scenario: Injected inline script
- **WHEN** a page somehow contains an inline `<script>` or an `onerror=` attribute
- **THEN** the browser refuses to execute it because of the policy

#### Scenario: Header present
- **WHEN** any HTML page is requested
- **THEN** the response includes the policy with `script-src 'self'`, `form-action 'self'` and `frame-ancestors 'none'`

### Requirement: Transport and browser hardening
In production the application SHALL redirect HTTP to HTTPS, send `Strict-Transport-Security` with a max-age of at least one year including subdomains, and send `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin` and a `Permissions-Policy` that disables camera, microphone, geolocation and payment.

#### Scenario: Plain HTTP request
- **WHEN** a client requests any URL over HTTP in production
- **THEN** it is redirected to the HTTPS URL

### Requirement: No third-party scripts or trackers
Pages SHALL NOT load scripts, stylesheets, fonts or tracking pixels from third-party origins. The only third-party network destination allowed from the browser SHALL be the configured error-tracking ingest host.

#### Scenario: Page resources
- **WHEN** any page is loaded
- **THEN** every script, stylesheet, font and image is requested from the application's own origin, except `data:`/`blob:` images

### Requirement: Operational surfaces are administrator-only
The background jobs dashboard and any other operational interface SHALL be reachable only by signed-in users flagged as administrators. All other users and anonymous visitors SHALL receive HTTP 404. No debug or test endpoints SHALL exist in production.

#### Scenario: Non-admin opens jobs dashboard
- **WHEN** a signed-in non-administrator requests the jobs dashboard URL
- **THEN** the response is HTTP 404

### Requirement: Privacy-preserving logs and error tracking
Logs and error reports SHALL filter passwords, tokens, secrets, keys, email addresses and comment, description or message bodies. Error reports SHALL identify users only by internal id and SHALL NOT include cookies, IP addresses or request bodies.

#### Scenario: Failed sign-in logged
- **WHEN** a sign-in request with a password is logged
- **THEN** the log shows the password and email as filtered

### Requirement: Secrets management
No secret (API keys, SMTP credentials, database passwords, error-tracking credentials, `secret_key_base`) SHALL be committed in plaintext to the repository. The application SHALL refuse to start in production when a required secret is missing instead of falling back to a default.

#### Scenario: Missing database password
- **WHEN** the production database password is not configured
- **THEN** the application fails to boot with an explicit error rather than using a default password

### Requirement: Dependency and static security gates
Continuous integration SHALL fail when any locked Ruby or JavaScript dependency has a known security advisory, or when static security analysis reports an unreviewed warning. Exceptions SHALL be listed in a versioned ignore file with a justification and an expiry date. JavaScript dependencies SHALL be installed from the lockfile without running package install scripts.

#### Scenario: Vulnerable gem introduced
- **WHEN** a change adds a gem version with a published advisory
- **THEN** the CI security job fails and names the gem and advisory
