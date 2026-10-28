# Spec Delta

## MODIFIED Requirements

### Requirement: Dependency policy
The client's directly declared runtime dependencies SHALL be exactly `vue`, `vue-router`, `pinia`, `@sentry/vue`, `@tiptap/*` packages and `swagger-ui-dist`, and its development dependencies exactly `vite`, `@vitejs/plugin-vue`, `typescript` and `vue-tsc`, at exact versions with a committed lockfile. Packages SHALL be installed without running install scripts. Client code SHALL NOT import packages that are not declared directly. Only the API documentation page's entry point SHALL import `swagger-ui-dist`. CI SHALL fail when any of these rules is broken.

#### Scenario: Unapproved dependency added
- **WHEN** a change adds `axios` to `package.json`
- **THEN** the CI dependency-policy check fails and names the package

#### Scenario: Importing a transitive package
- **WHEN** client code imports `marked`, which is only present as a transitive dependency
- **THEN** the CI check fails

#### Scenario: Documentation viewer imported by the application
- **WHEN** a module of the single-page application imports `swagger-ui-dist`
- **THEN** the CI check fails and names the importing file

### Requirement: API tokens screen
The settings SHALL include an API tokens screen that lists the user's tokens and creates one from a name, one of the user's projects, read-only or read-write access, an expiry of 7, 30, 90 or 365 days, and the current password. A new token's value SHALL be shown once, with a copy control and a warning that it will not be shown again. Revoking SHALL ask for confirmation. The screen SHALL link to the API documentation.

#### Scenario: Create and copy
- **WHEN** a user creates a token on the API tokens screen with their correct password
- **THEN** the token's value is shown with a copy control and a warning that it will not be shown again, and the token appears in the list

#### Scenario: Value not shown again
- **WHEN** a user leaves the API tokens screen after creating a token and comes back
- **THEN** the list shows the token without its value

#### Scenario: Wrong password
- **WHEN** a user submits the creation form with a wrong current password
- **THEN** the error is shown under the password field and the other fields keep their values

#### Scenario: Revoke
- **WHEN** a user chooses to revoke a token and confirms
- **THEN** the token disappears from the list

#### Scenario: Password change warning
- **WHEN** a user opens the password change form
- **THEN** it states that changing the password revokes all API tokens

#### Scenario: Link to the API documentation
- **WHEN** a user follows the API documentation link on the API tokens screen
- **THEN** the API documentation page opens
