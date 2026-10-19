## Purpose

Lets a signed-in user manage how they appear to teammates (name, avatar, contact links) and which language the application uses for them.

## ADDED Requirements

### Requirement: View and update own profile
The system SHALL let a signed-in user read and update their own name (1 to 100 characters), interface language (`en` or `ru`) and contact links. The system SHALL NOT allow a user to change another user's profile.

#### Scenario: Update name and language
- **WHEN** a user submits a new name and language `ru`
- **THEN** the profile is saved and subsequent responses and emails for that user use Russian

#### Scenario: Unsupported language
- **WHEN** a user submits language `de`
- **THEN** the update is rejected with a validation error and the language is unchanged

### Requirement: Contact links
The system SHALL store optional contact links for the services fb, vk, tg, ig and slack. Each link SHALL be either empty or an `https` URL of at most 255 characters. Updating some links SHALL leave the others unchanged.

#### Scenario: Partial update
- **WHEN** a user who has a tg link submits only a new slack link
- **THEN** the slack link is saved and the tg link is unchanged

#### Scenario: Script URL rejected
- **WHEN** a user submits `javascript:alert(1)` as a contact link
- **THEN** the update is rejected with a validation error

### Requirement: Avatar
The system SHALL generate a default avatar for every new account. A user SHALL be able to replace it by uploading a PNG, JPEG or WebP image of at most 5 MB; the file type SHALL be determined from the file content, not from the client-supplied name or type, and the stored image SHALL be re-encoded to at most 256×256 pixels.

#### Scenario: Valid upload
- **WHEN** a user uploads a 2 MB JPEG
- **THEN** the avatar is replaced and the profile returns the new avatar URL

#### Scenario: Disguised file
- **WHEN** a user uploads an SVG or HTML file renamed to `avatar.png`
- **THEN** the upload is rejected and the previous avatar is kept

#### Scenario: Too large
- **WHEN** a user uploads a 6 MB PNG
- **THEN** the upload is rejected and the previous avatar is kept

### Requirement: Profile visibility
A user's name, email and avatar SHALL be visible only to the user and to members of projects they share.

#### Scenario: Stranger lookup
- **WHEN** a user requests profile data of someone who shares no project with them
- **THEN** the system responds as if that user does not exist
