## MODIFIED Requirements

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
