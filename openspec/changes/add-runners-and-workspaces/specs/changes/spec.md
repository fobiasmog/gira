## ADDED Requirements

### Requirement: Base branch of a change
A change SHALL have a base branch: the branch its work starts from, a branch name as defined in spec `projects`, "Repository of a project". A change created by a member SHALL get the base branch given at creation, or else the project's default branch at that moment. A change created by an import (spec `openspec-changes`) SHALL get the project's default branch. Members SHALL be able to change the base branch of an open change while the change has no workspace (spec `agent-workspaces`). Once it has one, a change SHALL be refused with a validation error. Change lists and opening a change SHALL include the base branch.

#### Scenario: Default
- **WHEN** a member creates `export-csv` in TEST, whose default branch is `main`, without a base branch
- **THEN** `export-csv` has the base branch `main`

#### Scenario: Given at creation
- **WHEN** a member creates `add-tags` with the base branch `release/2.0`
- **THEN** opening `add-tags` shows the base branch `release/2.0`

#### Scenario: Changed before work starts
- **WHEN** `add-tags` has no workspace, and a member changes its base branch to `main`
- **THEN** `add-tags` has the base branch `main`

#### Scenario: Changed after work started
- **WHEN** `export-csv` has a workspace, and a member changes its base branch
- **THEN** the request is rejected with a validation error, and the base branch is unchanged

#### Scenario: Invalid name
- **WHEN** a member creates a change with the base branch `../main`
- **THEN** the response is HTTP 422 with a validation error on the base branch, and nothing is created
