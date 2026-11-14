## ADDED Requirements

### Requirement: Agent accounts cannot sign in
An agent account (spec `agents`) SHALL NOT be able to sign in, reset its password, unlock its account or confirm its address. For each of these actions, the system SHALL respond to an agent's address exactly as to an address without an account. Failed sign-in attempts with an agent's address SHALL NOT count toward lockout.

#### Scenario: Sign-in
- **WHEN** someone submits an agent's address with any password
- **THEN** sign-in is refused with the same generic error as for an unknown address

#### Scenario: Password reset
- **WHEN** someone requests a password reset for an agent's address
- **THEN** the response is the same as for an unknown address, and no email is sent

#### Scenario: Repeated failures
- **WHEN** sign-in fails ten times in a row with an agent's address
- **THEN** no unlock email is sent and the agent's tokens keep working

### Requirement: Agent domain is reserved
Registration with an address on the agent domain (`agents.goalner.com`) SHALL be rejected with a validation error on the address, whether or not an agent has that address. No account SHALL be created and no email SHALL be sent.

#### Scenario: Registering an agent address
- **WHEN** a visitor registers with `silver-fish-4821@agents.goalner.com`
- **THEN** registration is rejected with a validation error on the email field, no account is created and no email is sent
