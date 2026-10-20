# Spec Delta

## ADDED Requirements

### Requirement: Collapsible sidebar
On wide screens, the sidebar SHALL offer a control that collapses it to a narrow rail of icons, and from the rail a control that expands it again. The rail SHALL keep the logo, the project switcher (as the open project's initial), Dashboard, the open project's sections and "Write to us". Each of these SHALL keep its accessible name and SHALL show its label as a tooltip. The rail SHALL still mark the active section. The project list SHALL NOT be shown in the rail. The content area SHALL take the width the sidebar gives up. The choice SHALL be remembered in the browser across reloads. When browser storage is unavailable, the sidebar SHALL start expanded. The narrow-screen navigation SHALL always show the full sidebar and SHALL NOT offer the collapse control.

#### Scenario: Collapse the sidebar
- **WHEN** a member on a wide screen with the "Goalner" board open activates "Collapse menu"
- **THEN** the sidebar narrows to icons, the section labels and the project list are no longer visible, the "Backlog" link is still reachable by its name, and the board area is wider than before

#### Scenario: Navigate from the rail
- **WHEN** the sidebar is collapsed and the member activates the "Backlog" icon
- **THEN** the backlog opens and its icon is marked as the active section

#### Scenario: Switch project from the rail
- **WHEN** the sidebar is collapsed and the member activates the project switcher
- **THEN** the menu of the member's projects opens, and choosing one opens its board

#### Scenario: Expand the sidebar
- **WHEN** the sidebar is collapsed and the member activates "Expand menu"
- **THEN** the full sidebar with labels and the project list is shown again, and keyboard focus stays on the toggle

#### Scenario: Choice remembered
- **WHEN** a member collapses the sidebar and reloads the page
- **THEN** the sidebar is still collapsed

#### Scenario: Narrow screen
- **WHEN** a member who collapsed the sidebar opens the menu on a narrow screen
- **THEN** the navigation shows full labels and the project list, with no collapse control
