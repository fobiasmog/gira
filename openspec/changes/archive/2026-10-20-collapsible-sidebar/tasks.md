# Tasks

## 1. State and strings

- [x] 1.1 Add `sidebarCollapsed` and `toggleSidebar()` to `stores/ui.ts`, read from and written to `localStorage` (`goalner.sidebarCollapsed`) with every access in `try`/`catch`; verify `npm run typecheck` passes
- [x] 1.2 Add `navigation.collapse` / `navigation.expand` to `i18n/en.ts` and `i18n/ru.ts`; verify `npm test` passes, including the key-parity test

## 2. Shell

- [x] 2.1 Add `--sidebar-rail-width` to `styles/tokens.css`. In `AppShell`, give the aside a collapsed modifier with the rail width, an `inline-size` transition (off for reduced motion) and `overflow-x: hidden`. Add the toggle after "Write to us" in the wide-screen footer, with both buttons on one shared style that hides labels in the rail. Pass `collapsed` only to the wide-screen `SideNav`
- [x] 2.2 Add a `collapsed` prop to `SideNav`: visually hidden labels, `title` tooltips, the switcher as the initial only (a `folder_open` icon without an open project), no project list, centred icons, `nowrap` labels; verify `npm run typecheck` and `npm run build` succeed

## 3. Verification

- [x] 3.1 Add system tests to `test/system/app_shell_test.rb` for the spec scenarios "Collapse the sidebar", "Navigate from the rail", "Switch project from the rail", "Expand the sidebar", "Choice remembered" and "Narrow screen"; verify `bin/rails test test/system/app_shell_test.rb` passes
- [x] 3.2 Run the full system suite and `npm run policy` to check that nothing else depends on the old sidebar markup and that no CSP or policy violation appears
