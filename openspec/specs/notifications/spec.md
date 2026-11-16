# notifications Specification

## Purpose

Tells users about things that need their attention: tasks newly assigned to them (by email) and announcements from the operators (in the app).

## Requirements

### Requirement: Assignment email
When a member assigns a task to another member who is a person, the system SHALL send the assignee one email in the assignee's language. The email SHALL contain the assigner's name, the task key and a link to the task, and SHALL NOT contain the task description or comments. An assigner who is an agent (spec `agents`) SHALL be named like any other. No email SHALL be sent:
- when the assignee is an agent;
- when users assign a task to themselves;
- when the assignee is unchanged;
- when the update is rejected.

#### Scenario: Assign to a teammate
- **WHEN** Alice assigns GOAL-7 to Bob
- **THEN** Bob receives one email naming Alice and GOAL-7 with a link to the task

#### Scenario: Self-assignment
- **WHEN** Alice assigns GOAL-7 to herself
- **THEN** no email is sent

#### Scenario: Assign to an agent
- **WHEN** Alice assigns GOAL-7 to agent Fish
- **THEN** no email is sent

#### Scenario: Agent assigns a person
- **WHEN** agent Fish assigns GOAL-12 to Bob
- **THEN** Bob receives one email naming Fish and GOAL-12 with a link to the task

### Requirement: Emails are sent in the background
Notification and account emails SHALL be queued and sent asynchronously so that the request that caused them completes without waiting for mail delivery, and failed deliveries SHALL be retried.

#### Scenario: Mail server slow
- **WHEN** the mail server is slow to respond
- **THEN** the assignment request still completes promptly and the email is delivered later

### Requirement: In-app announcements
Operators SHALL be able to publish announcements written in Markdown. A user SHALL see the announcements they have not dismissed, oldest first, and SHALL be able to dismiss all of them at once. Every new account SHALL receive the current welcome announcement.

#### Scenario: Dismiss
- **WHEN** a user with 2 unread announcements dismisses all
- **THEN** their announcement list is empty and other users' lists are unchanged
