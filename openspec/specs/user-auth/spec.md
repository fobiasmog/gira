# user-auth Specification

## Purpose

Lets people create an account with an email address and password, prove they own that address, and sign in and out, while resisting credential stuffing, account enumeration and session hijacking.

## Requirements

### Requirement: Email and password registration
The system SHALL allow a visitor to register with a name, an email address and a password of at least 12 characters and at most 72 bytes. A new account SHALL NOT be able to sign in until its email address is confirmed through a confirmation link sent to that address; the link SHALL expire after 24 hours and SHALL stop working once used.

#### Scenario: Successful registration
- **WHEN** a visitor submits a valid name, an unused email and a 12-character password
- **THEN** the account is created in an unconfirmed state and a confirmation email is sent to that address

#### Scenario: Password too short
- **WHEN** a visitor submits a password shorter than 12 characters
- **THEN** registration is rejected with a validation error on the password field and no account is created

#### Scenario: Password too long
- **WHEN** a visitor submits a password longer than 72 bytes
- **THEN** registration is rejected with a validation error on the password field and no account is created

#### Scenario: Sign-in before confirmation
- **WHEN** a user with an unconfirmed email submits correct credentials
- **THEN** sign-in is refused with a message asking them to confirm their email, and they are offered to resend the confirmation link

#### Scenario: Expired confirmation link
- **WHEN** a confirmation link older than 24 hours is opened
- **THEN** the email is not confirmed and the user is offered to resend the link

### Requirement: Registration does not reveal existing accounts
The system SHALL respond to a registration attempt for an already registered email address in the same way, from the visitor's point of view, as to a successful registration, and SHALL notify the existing account holder by email instead of creating a second account.

#### Scenario: Registering an existing email
- **WHEN** a visitor registers with an email that already belongs to an account
- **THEN** the visitor sees the same "check your email" response as for a new registration, no new account is created, and the existing account holder receives an email saying someone tried to register with their address

### Requirement: Password sign-in
The system SHALL sign a confirmed user in when the email and password match, and SHALL return the same generic error for an unknown email and for a wrong password, taking comparable time in both cases.

#### Scenario: Correct credentials
- **WHEN** a confirmed user submits a matching email and password
- **THEN** a session is established and the user is redirected to the page they originally requested, or to `/app`

#### Scenario: Unknown email or wrong password
- **WHEN** a visitor submits an email that does not exist, or a wrong password for an existing email
- **THEN** the response is the same generic "invalid email or password" error in both cases

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

### Requirement: Sessions
Each sign-in SHALL create a server-side session record identified by a signed cookie. A session SHALL end after 14 days without use, on sign-out, or on a password change or reset as described above. Session records SHALL store the creation and last-use times and the user agent, and SHALL NOT store IP addresses.

#### Scenario: Idle session
- **WHEN** a user returns 15 days after last using a session
- **THEN** they are asked to sign in again

#### Scenario: Active session
- **WHEN** a user uses the application every few days
- **THEN** the session stays valid

### Requirement: Sign-out
The system SHALL sign a user out only through a DELETE request carrying a valid CSRF token, and SHALL delete the server-side session and its cookie.

#### Scenario: GET to sign-out URL
- **WHEN** a signed-in user's browser sends a GET request to the sign-out URL
- **THEN** the user remains signed in

#### Scenario: Stolen cookie after sign-out
- **WHEN** a session cookie is replayed after the user signed out
- **THEN** the request is treated as unauthenticated

### Requirement: Authentication rate limits
The system SHALL limit, per client IP address, sign-in attempts to 10 per 3 minutes, registrations to 5 per hour, password-reset requests to 5 per hour, and confirmation or unlock email re-sends to 5 per hour. Requests over a limit SHALL be refused without being processed (HTTP 429 for API requests, a "try again later" message on pages).

#### Scenario: Sign-in burst
- **WHEN** an IP address sends an eleventh sign-in attempt within 3 minutes
- **THEN** the attempt is refused with "try again later" and the credentials are not checked

### Requirement: Session cookie protection
The session cookie SHALL be signed and marked Secure, HttpOnly and SameSite=Lax.

#### Scenario: Cookie attributes
- **WHEN** a user signs in over HTTPS
- **THEN** the session cookie is set with Secure, HttpOnly and SameSite=Lax attributes
