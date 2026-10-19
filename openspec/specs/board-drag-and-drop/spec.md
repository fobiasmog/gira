# board-drag-and-drop Specification

## Purpose

Lets members rearrange their board directly — moving task cards between and within columns, reordering columns, and moving rows in the list layout — by drag and drop or by keyboard, with every move persisted and failed moves undone.

## Requirements

### Requirement: Drag task cards
On the kanban board a member SHALL be able to drag a task card by its drag handle to any position in any column. While dragging, the client SHALL show where the card will land. On drop the card SHALL appear at that position immediately and the move SHALL be saved.

#### Scenario: Move to another column
- **WHEN** a member drags GOAL-4 by its handle from "To Do" and drops it between the first and second cards of "Work"
- **THEN** GOAL-4 appears second in "Work" and stays there after reloading the page

#### Scenario: Dragging outside the handle
- **WHEN** a member presses on a card's title text and moves the pointer
- **THEN** no drag starts and text selection behaves normally

### Requirement: Reorder columns
A member SHALL be able to drag a column by its header handle to a new position among the columns, and the new order SHALL be saved.

#### Scenario: Move a column
- **WHEN** a member drags "Review" before "Work"
- **THEN** the columns show in the new order after reload, and the done column follows the board rules

### Requirement: Move rows in the list layout
In the list layout, which groups tasks by column, a member SHALL be able to drag a task row by its handle within its group or into another group, with the same persistence as on the kanban board.

#### Scenario: Row to another group
- **WHEN** a member drags a row from the "To Do" group into the "Done" group
- **THEN** the task is saved in the done column at the dropped position

### Requirement: Failed moves are rolled back
If the server rejects a move or the request fails, the client SHALL return the item to its original position and show an error message.

#### Scenario: Network failure
- **WHEN** a member drops a card while offline
- **THEN** the card returns to where it was and an error message is shown

### Requirement: Cancel and foreign drops
Pressing Escape during a drag or dropping outside any valid target SHALL leave the board unchanged. Drops that did not start from a draggable item of the same board — files, links, text or items from other windows — SHALL be ignored and SHALL NOT cause the browser to navigate or open anything.

#### Scenario: Drop a link from another tab
- **WHEN** a user drags a link from another browser tab onto a column
- **THEN** nothing changes on the board and the browser does not navigate

#### Scenario: Escape during a drag
- **WHEN** a member presses Escape while dragging a card
- **THEN** the card stays in its original position and no request is sent

### Requirement: Keyboard moves
When a card or list row has keyboard focus, Alt+Up and Alt+Down SHALL move it one position within its column, and Alt+Left and Alt+Right SHALL move it to the end of the previous or next column; when a column header has focus, Alt+Left and Alt+Right SHALL move the column. Each keyboard move SHALL be saved like a drag move and announced to screen readers with the item's new column and position.

#### Scenario: Move right by keyboard
- **WHEN** a member focuses GOAL-4 in "To Do" and presses Alt+Right
- **THEN** GOAL-4 moves to the end of "Work", keeps keyboard focus, and the screen reader announces "GOAL-4 moved to Work, position 3"

### Requirement: Scrolling during a drag
While a drag is in progress near the left or right edge of a horizontally scrollable board, the board SHALL scroll in that direction so that off-screen columns can be reached.

#### Scenario: Reach a hidden column
- **WHEN** a member drags a card and holds it near the right edge of a board whose last column is off-screen
- **THEN** the board scrolls right until the last column is reachable

### Requirement: Touch devices
On touch devices whose browser supports native drag and drop (Safari on iOS 15 or later, Chrome for Android), a long press on the drag handle SHALL start a drag without selecting text or opening a context menu. On browsers without native drag and drop on touch, tasks SHALL remain movable through the task's status control.

#### Scenario: Long press on iPhone
- **WHEN** a member long-presses a card's handle in Safari on iOS
- **THEN** the card lifts for dragging and no text-selection or context menu appears
