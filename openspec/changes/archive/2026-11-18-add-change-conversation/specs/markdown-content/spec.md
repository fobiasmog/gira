## MODIFIED Requirements

### Requirement: One feature set for editing and display
Every place that displays Markdown — descriptions, comments, archived tasks, announcements, the ideas of changes and the files of changes — SHALL support exactly the formatting the description editor supports. Markdown constructs outside that set, such as tables or images, SHALL NOT produce their HTML elements; their text content (cell text, image alt text) SHALL be kept as plain text.

#### Scenario: Image syntax in a comment
- **WHEN** a comment contains `![x](https://tracker.example/pixel.png)`
- **THEN** no image element is created, nothing is requested from `tracker.example`, and the alt text "x" is shown as plain text

#### Scenario: Table in a change file
- **WHEN** the `design.md` of a change holds a table and is shown formatted
- **THEN** no table element is created and the text of its cells is shown as plain text

### Requirement: Read-only Markdown views
Archived tasks, announcements and the files of changes SHALL display their Markdown content formatted, through the same renderer, without any editing controls.

#### Scenario: Archived task description
- **WHEN** a member opens an archived task whose description contains a heading and a list
- **THEN** the heading and list are shown formatted and cannot be edited

#### Scenario: Proposal of a change
- **WHEN** a member reads the `proposal.md` of a change on its page
- **THEN** its headings and lists are shown formatted, and it cannot be edited
