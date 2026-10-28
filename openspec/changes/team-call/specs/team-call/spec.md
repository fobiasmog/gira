# Spec Delta

## Purpose

Lets the members of a project talk to each other with audio and video right next to their board, in one call per project that stays with them while they work in the client.

## ADDED Requirements

### Requirement: One call per project
Each project SHALL have one call, and every member of the project SHALL be able to start it or join it. Users who are not members SHALL NOT be able to join a project's call or learn who is in it: such requests, and requests for the call of an archived project, SHALL receive HTTP 404. Calls SHALL be offered only when the application has a media server configured. Without one, no call control SHALL be shown, and requests to join a call SHALL receive HTTP 404.

#### Scenario: Start a call
- **WHEN** a member of "Website relaunch" activates "Start call" on its board while nobody is in the call
- **THEN** the member is in the project's call, and another member who opens the board sees them in it

#### Scenario: Join a running call
- **WHEN** Alice is in the call of "Website relaunch" and Bob, a member, activates "Join call" on its board
- **THEN** Alice and Bob each see and hear the other

#### Scenario: Not a member
- **WHEN** a signed-in user who is not a member of "Website relaunch" asks to join its call or to see who is in it
- **THEN** the request receives HTTP 404 and grants no access

#### Scenario: Archived project
- **WHEN** a member asks to join the call of an archived project
- **THEN** the request receives HTTP 404

#### Scenario: No media server configured
- **WHEN** no media server is configured and a member opens a board
- **THEN** no call control is shown

### Requirement: Call access tokens
The application SHALL grant access to a call only through access tokens it issues to members of the call's project. A token SHALL be valid only for the call of the project it was issued for, SHALL allow sending only camera video and microphone audio, SHALL identify the member only by their internal user id and their display name, and SHALL expire at most 10 minutes after it was issued. A user SHALL be able to request at most 20 tokens per minute; further requests SHALL receive HTTP 429.

#### Scenario: Token for another project
- **WHEN** a member presents a token issued for the call of project A to join the call of project B
- **THEN** the media server refuses the connection

#### Scenario: Screen sharing refused
- **WHEN** a participant's client tries to send a screen share
- **THEN** the media server refuses it and no other participant receives it

#### Scenario: No personal data beyond the name
- **WHEN** a member is issued a token
- **THEN** the token carries their internal user id and display name, and no email address, avatar or other personal data

#### Scenario: Expired token
- **WHEN** a token issued more than 10 minutes ago is used to join a call
- **THEN** the media server refuses the connection

#### Scenario: Too many token requests
- **WHEN** a user requests a twenty-first token within one minute
- **THEN** the request receives HTTP 429 and no token is issued

### Requirement: Call indicator on the board
The board header SHALL show the state of the project's call in both the kanban and the list layout: "Start call" when nobody is in the call, "Join call" with the participants' avatars and their number when somebody is, and "In call" when the member is in it. Activating "In call" SHALL show the expanded call view. Only current members of the project SHALL be listed as participants. While the board is visible, the participants shown SHALL be at most 30 seconds out of date, without a page reload.

#### Scenario: Nobody in the call
- **WHEN** a member opens the board and nobody is in the project's call
- **THEN** the header offers "Start call" and shows no participants

#### Scenario: Somebody in the call
- **WHEN** Alice and Bob are in the call and Carol opens the board
- **THEN** the header offers "Join call" with the avatars of Alice and Bob and the number 2

#### Scenario: Participants refresh
- **WHEN** Carol has the board open and Dave joins the call
- **THEN** within 30 seconds Carol's board shows Dave among the participants, without a reload

#### Scenario: Member already in the call
- **WHEN** Alice, who is in the call, opens the board
- **THEN** the header shows "In call", and activating it shows the expanded call view

### Requirement: Microphone and camera
Joining SHALL turn the member's microphone and camera on or off according to their last choice in this browser, and both on the first time. During the call the member SHALL be able to turn each on and off and to choose among the available microphones and cameras. The choice SHALL be remembered in the browser for the next call. When the browser refuses access to a device, or no such device is present, the member SHALL still join without it, SHALL be told why it is off, and SHALL see and hear the others. When the browser blocks sound playback, the call SHALL offer a control that starts it.

#### Scenario: First call in a browser
- **WHEN** a member joins a call for the first time in this browser and allows camera and microphone access
- **THEN** the microphone and camera are on, and the other participants see their video and hear them

#### Scenario: Turn the camera off
- **WHEN** the member turns the camera off during the call
- **THEN** the other participants see the member's avatar instead of their video

#### Scenario: Mute
- **WHEN** the member turns the microphone off
- **THEN** the other participants no longer hear them and see a muted marker on their tile

#### Scenario: Choice remembered
- **WHEN** a member who left a call with the camera off and the microphone on joins a call again in the same browser
- **THEN** the camera is off and the microphone is on

#### Scenario: Camera access refused
- **WHEN** the member refuses camera access when joining
- **THEN** they are in the call with the camera off, they are told that the browser blocks the camera, and they see and hear the other participants

#### Scenario: Choose another microphone
- **WHEN** the member chooses another microphone during the call
- **THEN** the other participants hear them through the new microphone, without the member leaving the call

### Requirement: Participants in the call view
The call view SHALL show one tile per participant, with their video while their camera is on and their avatar otherwise, their name, a marker while their microphone is off, and a highlight while they speak. The member's own tile SHALL be labelled as their own, and their own video SHALL be shown mirrored. Tiles that do not fit SHALL be reachable by scrolling. Participants joining and leaving SHALL be announced to screen readers.

#### Scenario: Participant without camera
- **WHEN** Bob is in the call with his camera off
- **THEN** his tile shows his avatar and his name

#### Scenario: Speaking highlight
- **WHEN** Bob speaks
- **THEN** his tile is highlighted until he stops speaking

#### Scenario: Join announced
- **WHEN** Bob joins a call the member is in
- **THEN** screen readers announce that Bob joined the call

#### Scenario: Own tile
- **WHEN** the member is in the call with the camera on
- **THEN** their own tile is labelled "You" and shows their video mirrored

### Requirement: A call lasts until the member leaves
Once joined, a member SHALL stay in the call while moving to any screen of the client, including the screens of other projects, until they activate "Leave", close or reload the page, or sign out. The call view SHALL name the call's project and link to that project's board. A member SHALL be in at most one call: activating "Join call" for another project's call SHALL ask for confirmation first, and confirming SHALL leave the current call and join the other. After leaving, the member's camera and microphone SHALL be off. Reloading the page SHALL NOT join a call again without the member's action.

#### Scenario: Open a task during a call
- **WHEN** a member in the call of "Website relaunch" opens a task from its board
- **THEN** the task page is shown and the member is still in the call

#### Scenario: Another project during a call
- **WHEN** the member opens the board of another project
- **THEN** they are still in the call, and the call view names "Website relaunch" and links to its board

#### Scenario: Switch to another project's call
- **WHEN** a member in the call of "Website relaunch" activates "Join call" on the board of "Mobile app"
- **THEN** they are asked to confirm; confirming leaves the call of "Website relaunch" and joins the call of "Mobile app", and cancelling keeps them in the call of "Website relaunch"

#### Scenario: Leave
- **WHEN** the member activates "Leave"
- **THEN** the call view closes, their camera and microphone are off, and the other participants no longer see them in the call

#### Scenario: Reload during a call
- **WHEN** a member in a call reloads the page
- **THEN** after the reload they are not in the call, and their camera and microphone stay off until they join again

### Requirement: Call view on wide screens
On screens at least 1024 pixels wide, the expanded call view SHALL be a pane on the right side of the screen, and the content area SHALL narrow by the pane's width. The pane SHALL show the participants and the controls for the microphone, the camera, device choice, shrinking and leaving. Its width SHALL be adjustable between 240 and 480 pixels by dragging its edge and with the keyboard, and the chosen width SHALL be remembered in the browser.

#### Scenario: Pane appears
- **WHEN** a member joins a call on a wide screen with the board open
- **THEN** a pane with the participants appears on the right, the board area becomes narrower, and every column stays reachable by scrolling

#### Scenario: Resize with the keyboard
- **WHEN** the member moves keyboard focus to the pane's edge and presses the left arrow key
- **THEN** the pane becomes wider, and it has that width again the next time it is shown

#### Scenario: Width limits
- **WHEN** the member drags the pane's edge beyond 480 pixels
- **THEN** the pane stays 480 pixels wide

### Requirement: Call view on narrow screens
On screens narrower than 1024 pixels, the expanded call view SHALL cover the whole screen and SHALL be modal: keyboard focus SHALL stay inside it and the screen behind it SHALL NOT be operable. Pressing Escape or activating the shrink control SHALL shrink the call to the call bar without leaving it.

#### Scenario: Join on a phone
- **WHEN** a member joins a call on a narrow screen
- **THEN** the call covers the whole screen with the participants and the call controls

#### Scenario: Escape shrinks the call
- **WHEN** the member presses Escape in the full-screen call
- **THEN** the call bar is shown at the bottom of the screen, the member is still in the call, and the board can be used

### Requirement: Call bar and tab
On every screen width, the expanded call view SHALL be shrinkable to a bar docked at the bottom of the screen. The bar SHALL show the number of participants and controls for the microphone, the camera, expanding, hiding and leaving. Hiding the bar SHALL leave a small tab at the bottom edge that shows that the member is in a call, the number of participants and whether their microphone is off. Activating the tab SHALL bring the bar back, and expanding from the bar SHALL show the expanded call view again. The bar and the tab SHALL NOT hide page content: every part of the page SHALL be reachable by scrolling. Shrinking and hiding SHALL NOT change the state of the member's microphone and camera.

#### Scenario: Shrink the pane to the bar
- **WHEN** a member in a call on a wide screen activates the shrink control of the pane
- **THEN** the pane closes, the board area takes the full width, the call bar is shown at the bottom, and the microphone and camera stay as they were

#### Scenario: Hide the bar
- **WHEN** the member hides the call bar while their microphone is off
- **THEN** only the tab remains at the bottom edge, showing the number of participants and that the microphone is off

#### Scenario: Restore from the tab
- **WHEN** the member activates the tab and then the bar's expand control
- **THEN** the bar is shown again, and then the expanded call view

#### Scenario: Content stays reachable
- **WHEN** the call bar is shown and the member scrolls to the end of a long backlog
- **THEN** the last task is fully visible above the bar

### Requirement: Losing access ends the call
When a member is removed from a project or leaves it, they SHALL be taken out of the project's call within one minute and SHALL be told that they no longer have access. When a project is archived, its call SHALL end for every participant within one minute.

#### Scenario: Removed during a call
- **WHEN** the owner removes Bob from the project while Bob is in its call
- **THEN** within one minute Bob is out of the call and is told that he no longer has access, and the other participants no longer see him

#### Scenario: Leaving the project during a call
- **WHEN** a member in the project's call leaves the project
- **THEN** within one minute they are out of the call

#### Scenario: Project archived during a call
- **WHEN** the owner archives a project while members are in its call
- **THEN** within one minute every participant is out of the call

### Requirement: One connection per member
A member SHALL take part in a call from one page at a time. Joining from a second tab or device SHALL end the participation of the first page, which SHALL say that the call continues elsewhere.

#### Scenario: Join from a second tab
- **WHEN** a member in a call joins the same call from another browser tab
- **THEN** the second tab is in the call, and the first tab leaves it and says that the call continues in another tab or device

### Requirement: Connection problems
When the connection to the call is interrupted, the call view SHALL show that it is reconnecting and SHALL reconnect without action from the member when the network allows. When reconnecting fails, the member SHALL leave the call and see a short message. When the media server cannot be reached while joining, the member SHALL see a short, generic message and SHALL NOT be shown as being in the call.

#### Scenario: Short interruption
- **WHEN** a member's network drops for a few seconds during a call
- **THEN** the call view shows that it is reconnecting, and the member is back in the call when the network returns, without acting

#### Scenario: Media server unreachable
- **WHEN** a member activates "Start call" while the media server cannot be reached
- **THEN** a short, generic error message is shown and the member is not in a call
