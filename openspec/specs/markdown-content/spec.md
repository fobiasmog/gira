# markdown-content Specification

## Purpose

Lets people write task descriptions and comments with formatting while storing them as portable Markdown, and guarantees that every place showing Markdown renders the same feature set safely.

## Requirements

### Requirement: Description editor
A member SHALL edit a task description in a formatting editor with controls for headings (levels 1–3), bold, italic, strikethrough, inline code, code block, bulleted list, numbered list, task list with checkboxes, blockquote, link, undo and redo. Typing Markdown shortcuts (for example `## ` or `- [ ] `) SHALL apply the corresponding formatting. The description SHALL be saved as Markdown automatically when the editor loses focus and after one second without typing.

#### Scenario: Format and save
- **WHEN** a member types a heading and a task list item and clicks elsewhere
- **THEN** the task's stored description is Markdown containing `# ` heading syntax and `- [ ] ` task-list syntax

#### Scenario: Toggle a checkbox
- **WHEN** a member ticks a task-list checkbox in the description
- **THEN** the stored Markdown changes that item from `- [ ]` to `- [x]`

### Requirement: Paste Markdown
Pasting plain-text Markdown into the description editor SHALL insert it as formatted content.

#### Scenario: Paste a list
- **WHEN** a member pastes the text `- one` followed by `- two` on a new line
- **THEN** the editor shows a bulleted list with two items

### Requirement: Comments in Markdown
Comments SHALL be written as Markdown in a plain text field and displayed formatted in the comment list. Bare `http`, `https` and `www.` URLs in comments SHALL be displayed as links.

#### Scenario: Comment with a link
- **WHEN** a member posts "See https://example.com/spec and **note** this"
- **THEN** the comment shows a clickable link and the word "note" in bold

### Requirement: One feature set for editing and display
Every place that displays Markdown — descriptions, comments, archived tasks and announcements — SHALL support exactly the formatting the description editor supports. Markdown constructs outside that set, such as tables or images, SHALL NOT produce their HTML elements; their text content (cell text, image alt text) SHALL be kept as plain text.

#### Scenario: Image syntax in a comment
- **WHEN** a comment contains `![x](https://tracker.example/pixel.png)`
- **THEN** no image element is created, nothing is requested from `tracker.example`, and the alt text "x" is shown as plain text

### Requirement: Safe Markdown rendering
Rendering Markdown SHALL NOT produce any element or attribute outside the supported formatting, and SHALL NOT run scripts or event handlers, whatever raw HTML the Markdown contains. Links SHALL be rendered only for `http`, `https` and `mailto` targets, SHALL open in a new tab, and SHALL carry `rel="noopener noreferrer nofollow"`. Links with any other target SHALL be shown as plain text.

#### Scenario: HTML injection in a comment
- **WHEN** a comment contains `<img src=x onerror=alert(1)><script>alert(2)</script>`
- **THEN** no image or script element is created and no script runs

#### Scenario: Script link
- **WHEN** a description contains `[click](javascript:alert(1))`
- **THEN** "click" is shown as plain text without a link

### Requirement: Read-only Markdown views
Archived tasks and announcements SHALL display their Markdown content formatted, through the same renderer, without any editing controls.

#### Scenario: Archived task description
- **WHEN** a member opens an archived task whose description contains a heading and a list
- **THEN** the heading and list are shown formatted and cannot be edited
