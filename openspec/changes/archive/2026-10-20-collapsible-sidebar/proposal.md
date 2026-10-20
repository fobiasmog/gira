# Proposal

## Why

On wide screens the sidebar always takes 256px. It only goes away when the window is narrower than 1024px, and then it turns into a drawer. Users who want more room for the board, or who know the sections by icon, cannot shrink it. A collapse control that turns the sidebar into a narrow strip of icons gives them that room and keeps every section one click away.

## What Changes

- A "Collapse menu" button at the bottom of the wide-screen sidebar turns the sidebar into an **icon rail**. The rail shows the logo mark, the open project's initial (still the project switcher), Dashboard, the project sections, "Write to us" and an "Expand menu" button. The "Projects" list is hidden, since the switcher lists the same projects. The content area gets the freed width.
- In the rail, labels are hidden visually but stay as the controls' accessible names, and each icon shows its label as a tooltip. The active section is still highlighted.
- The width change is animated briefly. There is no animation when the user prefers reduced motion.
- The choice is remembered in the browser and applies again after a reload or the next sign-in on the same device. If browser storage is unavailable, the sidebar starts expanded.
- Narrow screens are unchanged. The drawer always shows the full navigation and has no collapse control.

Not included: a keyboard shortcut, collapsing on hover, resizing by dragging, and storing the preference on the server.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `web-client`: adds a collapsible wide-screen sidebar.

## Impact

- Code: `components/shell/AppShell.vue` (rail width, footer buttons, toggle), `components/shell/SideNav.vue` (collapsed rendering), `stores/ui.ts` (remembered state), `styles/tokens.css` (rail width token), `i18n/en.ts` / `i18n/ru.ts` (two strings).
- Tests: new system tests in `test/system/app_shell_test.rb`. Existing shell tests run against the expanded default and should not change.
- No API, database, dependency, icon or CSP changes. This is the first use of `localStorage` in the client. It holds only this non-sensitive layout preference.
