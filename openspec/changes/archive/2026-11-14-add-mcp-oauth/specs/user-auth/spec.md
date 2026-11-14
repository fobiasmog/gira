# Spec Delta

## MODIFIED Requirements

### Requirement: Password reset
The system SHALL let a user request a password reset link by email. The response SHALL be identical whether or not the email belongs to an account. Reset links SHALL expire after 15 minutes and SHALL stop working once the password has been changed. Completing a reset SHALL end every existing session of that account, SHALL revoke all of its API tokens and SHALL end all of its MCP connections (spec `mcp-authorization`).

#### Scenario: Reset requested for unknown email
- **WHEN** a visitor requests a reset for an email with no account
- **THEN** the response is the same "if an account exists, we sent a link" message and no email is sent

#### Scenario: Expired reset link
- **WHEN** a reset link older than 15 minutes is used
- **THEN** the reset is refused and the user is offered to request a new link

#### Scenario: Reset completes
- **WHEN** a user sets a new valid password through a valid reset link
- **THEN** the password is changed, the same link can no longer be used, all sessions of the account are ended and all of its API tokens stop authenticating

#### Scenario: Connections end on reset
- **WHEN** a user with a claude.ai connection completes a password reset
- **THEN** claude.ai's next MCP request receives HTTP 401 and its refresh receives `invalid_grant`

### Requirement: Change password from settings
The system SHALL let a signed-in user change their password only after re-entering their current password. A successful change SHALL end all of the user's other sessions, keep the current one, revoke all of the user's API tokens and end all of the user's MCP connections (spec `mcp-authorization`).

#### Scenario: Wrong current password
- **WHEN** a signed-in user submits a new password with an incorrect current password
- **THEN** the change is rejected and the password is unchanged

#### Scenario: Other devices signed out
- **WHEN** a user signed in on two devices changes their password on one
- **THEN** the other device's session ends and the current device stays signed in

#### Scenario: API tokens revoked
- **WHEN** a user with API tokens changes their password from settings
- **THEN** every one of their tokens stops authenticating

#### Scenario: Connections ended
- **WHEN** a user with MCP connections changes their password from settings
- **THEN** every connection ends and the connected apps list is empty
