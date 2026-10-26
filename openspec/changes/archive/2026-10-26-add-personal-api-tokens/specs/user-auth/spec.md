# Spec Delta

## MODIFIED Requirements

### Requirement: Account lockout
The system SHALL lock an account after 10 consecutive failed password attempts. Failed attempts SHALL include wrong passwords at sign-in and wrong current passwords re-entered to change the password or to create an API token. A locked account SHALL unlock after 1 hour or through a single-use unlock link emailed to the account holder. A successful sign-in or a correct re-entered password SHALL reset the count. While locked, a re-entered password SHALL be refused even when correct.

#### Scenario: Tenth failed attempt
- **WHEN** a tenth consecutive wrong password is submitted for an account
- **THEN** the account is locked and an unlock email is sent to the account holder

#### Scenario: Correct password while locked
- **WHEN** the correct password is submitted for a locked account within the lock period
- **THEN** sign-in is refused with the same generic error and the account remains locked

#### Scenario: Wrong current passwords in settings
- **WHEN** a signed-in user has submitted 9 consecutive wrong passwords at sign-in, on the password-change form or on the token-creation form, and then submits a wrong current password on the password-change form
- **THEN** the change is rejected, the account is locked and an unlock email is sent

#### Scenario: Re-entered password while locked
- **WHEN** a signed-in user whose account is locked submits their correct current password on the password-change form
- **THEN** the change is rejected with the same validation error as for a wrong current password and the password is unchanged

#### Scenario: Correct re-entered password resets the count
- **WHEN** a user with 5 consecutive failed attempts enters their correct current password to create an API token
- **THEN** the failed-attempt count is reset to zero

### Requirement: Password reset
The system SHALL let a user request a password reset link by email. The response SHALL be identical whether or not the email belongs to an account. Reset links SHALL expire after 15 minutes and SHALL stop working once the password has been changed. Completing a reset SHALL end every existing session of that account and SHALL revoke all of its API tokens.

#### Scenario: Reset requested for unknown email
- **WHEN** a visitor requests a reset for an email with no account
- **THEN** the response is the same "if an account exists, we sent a link" message and no email is sent

#### Scenario: Expired reset link
- **WHEN** a reset link older than 15 minutes is used
- **THEN** the reset is refused and the user is offered to request a new link

#### Scenario: Reset completes
- **WHEN** a user sets a new valid password through a valid reset link
- **THEN** the password is changed, the same link can no longer be used, all sessions of the account are ended and all of its API tokens stop authenticating

### Requirement: Change password from settings
The system SHALL let a signed-in user change their password only after re-entering their current password. A successful change SHALL end all of the user's other sessions, keep the current one, and revoke all of the user's API tokens.

#### Scenario: Wrong current password
- **WHEN** a signed-in user submits a new password with an incorrect current password
- **THEN** the change is rejected and the password is unchanged

#### Scenario: Other devices signed out
- **WHEN** a user signed in on two devices changes their password on one
- **THEN** the other device's session ends and the current device stays signed in

#### Scenario: API tokens revoked
- **WHEN** a user with API tokens changes their password from settings
- **THEN** every one of their tokens stops authenticating
