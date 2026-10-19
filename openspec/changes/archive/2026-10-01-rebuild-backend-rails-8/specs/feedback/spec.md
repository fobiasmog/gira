## Purpose

Lets a signed-in user send feedback to the people who run Goalner without leaving the application.

## ADDED Requirements

### Requirement: Send feedback
A signed-in user SHALL be able to send feedback consisting of a reason of 1 to 100 characters and a message of 1 to 5,000 characters. The feedback SHALL be emailed to the operators' configured address with the sender's account email as reply-to. The request SHALL require a valid CSRF token.

#### Scenario: Feedback sent
- **WHEN** a user submits reason "bug" and a message
- **THEN** the operators receive an email with the reason, the message and the user's email as reply-to

#### Scenario: Missing CSRF token
- **WHEN** a feedback request arrives without a valid CSRF token
- **THEN** it is rejected and no email is sent

### Requirement: Feedback rate limit
A user SHALL be able to send at most 5 feedback messages per hour; further requests SHALL receive HTTP 429.

#### Scenario: Sixth message
- **WHEN** a user sends a sixth feedback message within one hour
- **THEN** the request receives HTTP 429 and no email is sent
