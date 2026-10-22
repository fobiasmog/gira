# Spec Delta

## MODIFIED Requirements

### Requirement: Content Security Policy
Every HTML response SHALL carry a Content Security Policy that allows scripts, styles, fonts and frames only from the application's own origin, allows images only from the own origin plus `data:` and `blob:`, allows network connections only to the own origin, the configured error-tracking ingest host and the configured media server (its WebSocket and HTTP addresses), allows form submissions only to the own origin, forbids plugins (`object-src 'none'`), restricts `base-uri` to the own origin, and forbids framing (`frame-ancestors 'none'`). The policy SHALL NOT contain `'unsafe-inline'` or `'unsafe-eval'` for scripts. In development only, the policy SHALL additionally allow the local frontend dev server origin (HTTP and WebSocket) and a per-request nonce for `style-src`, exposed to the page so the dev server can inject stylesheets, and nothing else.

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

#### Scenario: Media server in the policy
- **WHEN** a media server is configured and any HTML page is requested
- **THEN** the policy's `connect-src` contains the media server's WebSocket and HTTP addresses, and no other host besides the own origin and the error-tracking ingest host (plus the dev server in development)

#### Scenario: No media server configured
- **WHEN** no media server is configured and any HTML page is requested
- **THEN** the policy's `connect-src` contains only the own origin and the error-tracking ingest host (plus the dev server in development)

### Requirement: Transport and browser hardening
In production the application SHALL redirect HTTP to HTTPS, send `Strict-Transport-Security` with a max-age of at least one year including subdomains, and send `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin` and a `Permissions-Policy` that allows camera and microphone only for the application's own origin and disables geolocation and payment.

#### Scenario: Plain HTTP request
- **WHEN** a client requests any URL over HTTP in production
- **THEN** it is redirected to the HTTPS URL

#### Scenario: Camera and microphone for own pages only
- **WHEN** any page is requested
- **THEN** the `Permissions-Policy` header allows `camera` and `microphone` for `self` only, and disables `geolocation` and `payment`

### Requirement: No third-party scripts or trackers
Pages SHALL NOT load scripts, stylesheets, fonts or tracking pixels from third-party origins. The only third-party network destinations allowed from the browser SHALL be the configured error-tracking ingest host and the configured media server, including the media connections it negotiates for calls. Call audio and video SHALL be exchanged only with the media server, never directly between participants' browsers.

#### Scenario: Page resources
- **WHEN** any page is loaded
- **THEN** every script, stylesheet, font and image is requested from the application's own origin, except `data:`/`blob:` images

#### Scenario: Media during a call
- **WHEN** members are in a call
- **THEN** each participant's browser sends and receives audio and video only through the media server, and no browser connects to another participant's address
