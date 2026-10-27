## ADDED Requirements

### Requirement: List columns
Members SHALL be able to list a project's columns in board order, without the board's tasks. Each column SHALL have its id, title, color, position, and whether it is the done column, as in the board snapshot. The last column in the list SHALL be the done column.

#### Scenario: List columns
- **WHEN** a member lists the columns of a project whose board has "To Do", "Work", "Review", "Done"
- **THEN** the list contains "To Do", "Work", "Review", "Done" in that order, each with its id, title, color and position, and only "Done" is marked as the done column

#### Scenario: Same columns as the board
- **WHEN** a member lists a project's columns and then reads its board
- **THEN** both contain the same columns with the same fields and order

#### Scenario: Not a member
- **WHEN** a user lists the columns of a project they are not a member of
- **THEN** the response is HTTP 404
