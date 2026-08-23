## Purpose

Defines the cross-process durability and privacy boundary for Telegram updates that the webhook has accepted but the interaction worker has not yet settled.

## ADDED Requirements

### Requirement: Accepted updates survive process restart

Telegram SHALL persist enough authenticated and parsed update data before returning a successful webhook acknowledgement for a restarted worker to process the update without another delivery from Telegram.

#### Scenario: process stops after admission

- **WHEN** the webhook persists and acknowledges an update but the process stops before the worker handles it
- **THEN** a restarted worker loads the pending update and settles it exactly once

#### Scenario: redelivery follows uncertain acknowledgement

- **WHEN** Telegram redelivers an update whose durable row already exists
- **THEN** the service does not create a second interaction or lose the original pending work

### Requirement: Settled updates retain no process payload

Telegram SHALL remove the processable update payload after terminal settlement while retaining the minimized identity, classification, state, and timestamps required for deduplication and audit.

#### Scenario: terminal settlement minimizes retained data

- **WHEN** the worker settles an update as processed, unsupported, or failed
- **THEN** the durable row no longer contains message text or another processable Telegram payload
