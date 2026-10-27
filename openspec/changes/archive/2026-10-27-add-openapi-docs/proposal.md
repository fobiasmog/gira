# Proposal

## Why

Personal API tokens (change `add-personal-api-tokens`) opened about 35 actions to scripts and integrations. The only documentation is a short README section that points readers to `config/routes.rb`. Integrators cannot see request parameters, response fields or error shapes, and there is no quick way to try a call. Nothing checks that the API keeps its shape either, so a renamed serializer field would silently break integrations.

## What Changes

- A hand-written OpenAPI 3.1 document, `docs/openapi.yaml`, describes the token API: every method and path opened to API tokens, and nothing else. Each operation describes:
  - its parameters and request body;
  - its success response;
  - its error responses (401, 403, 404, 422 and 429), using the API's JSON error envelope;
  - Bearer token authentication.
- A command, `bin/openapi-verify`, checks the whole document against the API and exits non-zero, naming each mismatch, when:
  - an action is opened to tokens without a documented operation, or a documented operation has no opened action;
  - an operation has no example request, or its example does not get the documented success response;
  - a response, or an accepted request, does not match the document;
  - an operation does not list its error responses, or an error example does not match them.

  It runs offline in a few seconds and is meant to be run by hand or from a git pre-push hook. It is not part of `bin/rails test` or CI, so an out-of-date document never blocks CI.
- `GET /api/docs` shows the document in Swagger UI to signed-in users. Anonymous visitors are sent to sign-in. A request with an API token gets 403, as for every endpoint not opened to tokens.
- `GET /api/openapi.yaml` serves the raw document to signed-in users, for import into Postman, Insomnia or code generators.
- "Try it out" in Swagger UI uses only an API token the user pastes:
  - the session cookie is never sent, so calls behave exactly as they would from an external client;
  - the token is not stored beyond the page.
- Swagger UI is self-hosted and runs under the production Content Security Policy. It comes from npm as `swagger-ui-dist`, pinned and audited like other frontend packages, and only the docs page loads it.
- The API tokens settings screen and the README link to the documentation.

Not included:
- documenting session-only endpoints (projects administration, members, invitations, columns, account, statistics);
- public, anonymous access to the documentation;
- downloading the document with an API token;
- API versioning, generated client SDKs, or generating the document from code;
- running the verification in CI;
- installing the git pre-push hook, which will be added separately.

## Capabilities

### New Capabilities

- `api-documentation`: the OpenAPI description of the token API, how it is kept in sync with the implementation, and the interactive documentation page with its "Try it out" behavior.

### Modified Capabilities

- `web-client`:
  - "Dependency policy" allows `swagger-ui-dist`, but only the API documentation entrypoint may import it, never the single-page application;
  - "API tokens screen" links to the API documentation.

## Impact

- **New files:**
  - `docs/openapi.yaml`;
  - `Api::DocsController` (the HTML page) and `Api::OpenapiController` (the YAML), with a docs layout;
  - the Vite entrypoint `app/frontend/entrypoints/api-docs.ts`.
- **Changed files:**
  - `config/routes.rb`, with the two routes ahead of the API catch-all;
  - `vite.config.ts`, with a second build input;
  - `ApiTokensSettingsPage.vue`, `en`/`ru` strings, `README.md`.
- **Dependencies:**
  - npm `swagger-ui-dist`, at an exact version;
  - the `openapi_first` gem, in the test group only, for request and response validation.
  - `script/check-frontend-policy.mjs` allows the npm package and restricts where it can be imported.
- **Verification:** `bin/openapi-verify` and a contract suite in `test/openapi/` that only the command runs:
  - a validation hook used by that suite alone;
  - a route-to-document parity test;
  - one example request per documented operation, plus one per error kind.
- **Tests run in CI:**
  - request tests for the two new endpoints;
  - system tests for the docs page, "Try it out" and CSP compliance.
- **Existing behavior:** API responses are unchanged. If writing the document reveals responses that are inconsistent, they are reported rather than silently changed.
