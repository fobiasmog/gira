## ADDED Requirements

### Requirement: OpenSpec work in a sprint being archived
The sprint archive dialog SHALL warn when the sprint holds cards of OpenSpec changes (spec `openspec-changes`) that are not in the done column. The warning SHALL name each such change with its number of unfinished cards, and SHALL say that agents may be working on them and that cards carried over lose their checklist and their link to the change. Archiving SHALL stay possible, with or without carrying tasks over. A sprint without such cards SHALL show no warning.

#### Scenario: Unfinished OpenSpec cards
- **WHEN** a member opens the archive dialog of "Openspec integration", which holds three cards of `add-labels` that are not done
- **THEN** the dialog warns that 3 cards of `add-labels` are unfinished, and the member can still archive the sprint

#### Scenario: Nothing unfinished
- **WHEN** a member opens the archive dialog of a sprint whose OpenSpec cards are all done
- **THEN** the dialog shows no warning
