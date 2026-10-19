# comments Specification

## Purpose

Lets project members discuss a task in Markdown comments with file attachments that only project members can download.

## Requirements

### Requirement: Comment on a task
Members SHALL be able to list a task's comments, newest first, and add a comment whose Markdown text is 1 to 10,000 characters long. Comment text SHALL be stored and returned exactly as written; the server SHALL NOT convert it to HTML.

#### Scenario: Add a comment
- **WHEN** a member posts "Looks good, see **notes**" on a task
- **THEN** the comment appears first in the task's comment list with that exact text, the author and the creation time

#### Scenario: Empty comment
- **WHEN** a member posts a comment with no text
- **THEN** the request is rejected with a validation error

### Requirement: Edit and delete own comments
A user SHALL be able to edit or delete only comments they wrote. Deleted comments SHALL disappear from the task's comment list.

#### Scenario: Edit someone else's comment
- **WHEN** a user tries to edit a comment written by another member
- **THEN** the response is HTTP 404 and the comment is unchanged

### Requirement: Attachments
A comment SHALL accept up to 10 attached files of at most 10 MB each. Accepted file types SHALL be PNG, JPEG, GIF, WebP, PDF, plain text, CSV and ZIP, determined from the file content. SVG, HTML and any other type SHALL be rejected. Image and PDF attachments SHALL get a preview thumbnail.

#### Scenario: Allowed files
- **WHEN** a member posts a comment with a 3 MB PDF and a 1 MB PNG
- **THEN** both are attached and listed with file name, size and a preview

#### Scenario: Rejected type
- **WHEN** a member attaches an SVG or an HTML file
- **THEN** the whole comment is rejected with a validation error naming the file

#### Scenario: Too many files
- **WHEN** a member attaches 11 files
- **THEN** the comment is rejected with a validation error

### Requirement: Attachment access control
Attachments and their previews SHALL be downloadable only by signed-in members of the attachment's project, through URLs that do not work for anyone else. Downloads SHALL be served with `Content-Disposition: attachment` and `X-Content-Type-Options: nosniff`.

#### Scenario: Former member
- **WHEN** a user who has left the project opens a previously valid attachment URL
- **THEN** the response is HTTP 404

#### Scenario: Signed-out request
- **WHEN** an attachment URL is requested without a session
- **THEN** the file is not served
