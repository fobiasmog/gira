# Design

## Context

`AppShell` renders the navigation in one of two ways. It uses `useMediaQuery("(min-width: 1024px)")` to choose. On wide screens it is a sticky `<aside class="shell__sidebar">` with a fixed width of `--sidebar-width` (256px). On narrow screens it is an `AppDialog` drawer. Both cases render the same `SideNav`. `AppShell` fills the `footer` slot with the "Write to us" button, because that button opens a dialog `AppShell` owns. The shell grid is `auto minmax(0, 1fr)`, so the main column already follows the sidebar's width.

The constraints of the `web-client` spec apply as before: no new dependencies, no inline `<style>`, a keyboard path to every control, accessible names for icon-only buttons, and progressive features only as enhancements.

## Goals / Non-Goals

**Goals:**
- Let wide-screen users switch between the full sidebar and an icon rail at any time, and keep their choice.
- Keep every destination of the full sidebar reachable from the rail, with the same accessible names.

**Non-Goals:**
- Changing the narrow-screen drawer.
- Syncing the preference across devices.

## Decisions

### State lives in the `ui` store and is remembered in `localStorage`
`useUiStore` gets `sidebarCollapsed` and `toggleSidebar()`. The initial value is read from `localStorage` under `goalner.sidebarCollapsed`, and each toggle writes it back. Every access is wrapped in `try`/`catch`, because storage can be blocked (private mode, site data disabled). In that case the sidebar starts expanded and the toggle still works for the session. The value is a layout preference with no personal data, so it is not cleared on sign-out.
*Alternative:* a column on the user's profile. Rejected for now: it needs an API and migration for a per-device habit. A wide desktop window and a laptop may well want different settings.

### `SideNav` gets a `collapsed` prop; `AppShell` owns the toggle
`SideNav` stays a presentational component. With `collapsed`, it adds `side-nav--collapsed` to its root and:
- wraps each label (logo name, switcher text, Dashboard, section labels) in a span with the global `visually-hidden` class, so names and existing system-test selectors stay the same;
- sets `title` to the label on icon-only links and on the switcher, so the label shows as a native tooltip. CSS tooltips would be clipped by the sidebar's scroll container, and the popover/anchor alternative depends on features the browser baseline does not guarantee;
- hides the "Projects" list (`v-if`), because the switcher above already lists the projects;
- shows the switcher as the project initial only, without the chevron. With no open project, a `folder_open` icon stands in for the initial. The `AppMenu` popover is in the top layer, so it opens at full width next to the rail.

`AppShell` passes `collapsed` only to the wide-screen `SideNav`, so the drawer always renders it expanded. In the footer slot it adds the toggle after "Write to us". Both buttons share one style and hide their labels in the rail the same way. The toggle's label reads "Collapse menu" or "Expand menu" to match the action, and its icon is `chevron_left` or `chevron_right` (both already in the sprite). It does not use `aria-expanded`: the navigation stays present in both states, so "expanded" would not describe it. The toggle element is not replaced when it is pressed, so keyboard focus stays on it.

### Width and motion
A new token `--sidebar-rail-width: 64px` sets the rail's width. In the rail, `SideNav` uses `--space-2` inline padding and centres the icons in its links and buttons. That leaves a 48px column, which fits the 30px logo mark, the 32px project initial with its padding, and the 36px targets. `.shell__sidebar` transitions `inline-size` over 150ms. It sets `overflow-x: hidden`, and labels use `white-space: nowrap`, so text appearing during an expand is clipped instead of wrapping. With `prefers-reduced-motion: reduce` the transition is off.

### Narrow screens and resizing
Nothing changes below 1024px. Resizing a collapsed window below the breakpoint shows the drawer button as today. The stored preference still applies when the window is widened again.

## Risks / Trade-offs

- [Native `title` tooltips are not shown on keyboard focus] → the accessible name is unchanged and the visible icons match the expanded sidebar. Screen-reader and keyboard users lose nothing, but sighted keyboard users get no visual label in the rail. That is acceptable for an opt-in mode that one button undoes.
- [The board reflows while the width animates] → the transition is short and runs only on an explicit click.
- [Stored preference makes the rail the default for anyone using the same browser profile] → it is a layout preference only, and one click restores the full sidebar.

## Migration Plan

Front-end only: ship in one deploy. No data or API migration. Rolling back the change makes the stored key unused, and it does no harm.
