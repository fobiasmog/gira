## ADDED Requirements

### Requirement: Base branch of a change
A change SHALL have a base branch: the branch its work starts from. For now, every change's base branch SHALL be `main`, whether a member or an import (spec `openspec-changes`) created it, and members SHALL NOT be able to choose or change it. Change lists and opening a change SHALL include the base branch.

#### Scenario: Created by a member
- **WHEN** a member creates `export-csv` in TEST
- **THEN** opening `export-csv` shows the base branch `main`

#### Scenario: Created by an import
- **WHEN** a client imports the OpenSpec change `add-tags` into TEST
- **THEN** `add-tags` has the base branch `main`

#### Scenario: Another branch given
- **WHEN** a member creates `fix-login`, and the request also gives the base branch `release/2.0`
- **THEN** `fix-login` has the base branch `main`
