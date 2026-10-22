# Spec Delta

## MODIFIED Requirements

### Requirement: Dependency policy
The client's directly declared runtime dependencies SHALL be exactly `vue`, `vue-router`, `pinia`, `@sentry/vue`, `livekit-client` and `@tiptap/*` packages, and its development dependencies exactly `vite`, `@vitejs/plugin-vue`, `typescript` and `vue-tsc`, at exact versions with a committed lockfile. Packages SHALL be installed without running install scripts. Client code SHALL NOT import packages that are not declared directly. CI SHALL fail when any of these rules is broken.

#### Scenario: Unapproved dependency added
- **WHEN** a change adds `axios` to `package.json`
- **THEN** the CI dependency-policy check fails and names the package

#### Scenario: Importing a transitive package
- **WHEN** client code imports `marked`, which is only present as a transitive dependency
- **THEN** the CI check fails

#### Scenario: Call library declared
- **WHEN** `livekit-client` is declared at an exact version and the client imports it
- **THEN** the CI dependency-policy check passes
