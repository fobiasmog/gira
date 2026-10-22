# Proposal

## Why

Members who plan and track work on the board have to meet in a separate video tool, and there they cannot see the board while they talk. A call that opens next to the board lets the team talk while everyone looks at the same tasks. The same pieces (a media server, the permission to use camera and microphone, the call view in the shell) are also the base for the collaboration features planned later.

## What Changes

- Each project has one team call. Members start or join it from the board header, in both the kanban and the list layout. The header shows "Start call" when nobody is in the call, "Join call" with the participants' avatars when somebody is, and "In call" for a member who is already in it. The participant list is refreshed at least every 30 seconds while the board is visible.
- Audio and video go over WebRTC through a self-hosted LiveKit media server, which forwards each participant's streams to the others. The application decides who may join. It issues short-lived access tokens, only to project members, for their project's call only, and allowing camera and microphone only. It also asks the media server who is in a call.
- On wide screens, participants appear in a pane on the right side of the screen, and the content area narrows to make room. The pane can be resized with the pointer or the keyboard, and its width is remembered.
- On narrow screens, the call covers the whole screen. It can be shrunk to a bar of controls docked at the bottom of the screen, and the bar to a small tab, so the member can use the board while staying in the call. Wide screens offer the same bar and tab.
- Once joined, the call continues on every screen of the client, including other projects, until the member leaves it, closes or reloads the page, or signs out. The call view names its project and links to that project's board. A member is in at most one call: joining another project's call asks for confirmation first.
- Each participant is shown with their video, or their avatar while the camera is off, their name, a muted marker and a highlight while speaking. Members turn their microphone and camera on and off and choose which devices to use. Their choice is remembered for the next call. A member who refuses camera or microphone access still joins, without that device.
- A member who loses access to the project (removed, leaving, or the project archived) is taken out of the call. Joining the same call from a second tab ends the first tab's participation.
- Development setup: `bin/dev` starts a local LiveKit server in development mode when it is installed. A second test user makes two-browser testing possible. CI runs a pinned LiveKit server binary for the call system tests.
- `security-baseline`: the Permissions-Policy allows camera and microphone for the application's own origin. The Content Security Policy and the list of allowed browser destinations include the configured media server.
- `web-client`: `livekit-client` joins the allowed runtime dependencies.

Not included: screen sharing, chat, recording, background effects, end-to-end encryption, guests who are not project members, live board collaboration, testing on real phones, and production deployment of the media server (Kamal accessory, TLS, TURN, open ports). The deployment is a separate change. Until then production has no media server configured, and calls are not offered there.

## Capabilities

### New Capabilities

- `team-call`: a project's audio and video call: who may start and join it, the board indicator, the call views in the shell (wide-screen pane, narrow-screen overlay, bar and tab), microphone and camera controls, how long a call lasts for a member, and how losing access ends it.

### Modified Capabilities

- `security-baseline`: the Permissions-Policy allows camera and microphone for the own origin; the Content Security Policy and the allowed third-party destinations include the configured media server.
- `web-client`: the dependency policy allows `livekit-client`.

## Impact

- Backend: a small hand-written LiveKit client (access tokens, room API calls), a project call model, `GET /api/projects/:project_id/call` (availability and participants) and `POST /api/projects/:project_id/call/token`, routes, a background job that takes members out of a call, hooks in member removal, leaving and project archiving, `config.x.livekit` settings, the CSP and Permissions-Policy initializers, `config/credentials.example.yml`.
- Frontend: the `livekit-client` dependency (loaded only when a member joins), `stores/call.ts`, call components under `components/call/`, a third column in `AppShell.vue`, the call control in the `BoardPage.vue` header, `api/call.ts`, new icons in the sprite, `i18n/en.ts` and `i18n/ru.ts`.
- Development and CI: `README.md`, `bin/dev`, `Makefile`, `.github/workflows/ci.yml` (pinned LiveKit binary), `script/check-frontend-policy.mjs` (allowlist).
- No database changes.
- The in-flight `sprint-based-backlog` change edits board files too. The overlap is the board header in `BoardPage.vue`.
