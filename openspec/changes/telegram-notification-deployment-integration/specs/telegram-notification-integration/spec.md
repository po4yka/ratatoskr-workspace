## Purpose

Defines the fleet-visible route and verification boundary by which a raised notification becomes a preference-filtered Telegram delivery without moving notification policy into producers.

## ADDED Requirements

### Requirement: Raised notification facts have one canonical Telegram route

Producer services SHALL publish the existing `platform.notification.raised.v1` fact on `evt.platform.notification.raised.v1`. Telegram SHALL be the consumer that decides whether, when, and to which verified Telegram chat the fact is delivered; producers SHALL NOT bypass that decision through a Telegram-specific command or direct Bot API call.

#### Scenario: Producer raises a notification for an enabled recipient

- **WHEN** a valid raised-notification envelope for a linked user is published on the canonical subject and the user's matching preference is enabled
- **THEN** Telegram produces one authorized outbound projection for each eligible configured chat

#### Scenario: Producer raises a notification disabled by the user

- **WHEN** a valid raised-notification envelope is published for a class the recipient disabled
- **THEN** Telegram records a suppression and sends no Bot API request

### Requirement: Notification topology is provisioned before Telegram starts

Platform SHALL own creation and validation of the `ratatoskr_telegram_notifications` pull consumer on `ratatoskr_events`, filtered exactly to `evt.platform.notification.raised.v1`. The Telegram identity SHALL be able to inspect, fetch from, and acknowledge only that durable and SHALL NOT be able to create consumers, select another filter, or publish domain messages. Telegram readiness SHALL remain false when the durable is absent or mismatched.

#### Scenario: Compatible topology precedes Telegram startup

- **WHEN** Platform has created the matching durable and the Telegram dispatcher starts with its least-privilege identity
- **THEN** Telegram verifies the durable, becomes ready, and can resume its existing cursor

#### Scenario: Telegram cannot self-provision a broader consumer

- **WHEN** the fixed durable is absent or carries a different filter
- **THEN** Telegram remains unready and its NATS identity cannot create or replace the consumer

### Requirement: At-least-once transport does not become duplicate delivery

Telegram SHALL use the contract notification identity, recipient, and target chat as the logical delivery key independently of the carrying bus event identity. Re-delivery or re-publication of the same notification SHALL NOT create a second outbound message for the same chat.

#### Scenario: Same notification arrives in two event envelopes

- **WHEN** two valid envelopes carry the same notification identity to the same recipient
- **THEN** the composed system contains one Telegram delivery decision per eligible chat and acknowledges both transport deliveries safely

### Requirement: A composed profile proves both interaction and notification boundaries

The workspace SHALL provide a task-namespaced profile using synthetic identities, updates, credentials, Bot API responses, notification facts, and Platform operation events. The smoke SHALL demonstrate the plan-item-5 article path from admitted Telegram update through Platform operation progress to a final Telegram projection and SHALL separately demonstrate an enabled notification delivery plus a preference suppression.

#### Scenario: Namespaced composed smoke passes

- **WHEN** the TG-010 profile starts from an empty task namespace and the smoke drives the article and notification cases
- **THEN** the observed Bot API calls, Platform requests, notification decisions, and durable rows match the two flows without production credentials, real chats, or private content

#### Scenario: Profile teardown preserves unrelated resources

- **WHEN** the TG-010 profile is torn down after the smoke
- **THEN** only containers, ports, databases, streams, and volumes bearing its task namespace are removed

### Requirement: Evidence states its real boundary

The integration record SHALL name exact source revisions and executed checks, and SHALL distinguish structural systemd validation, local composed runtime evidence, hosted CI, and live deployment. A successful composed profile SHALL NOT be reported as webhook registration, real-chat delivery, or operation of the frozen single-host target.

#### Scenario: Composed profile succeeds without live deployment

- **WHEN** every local profile assertion passes while the deployment target remains frozen
- **THEN** the evidence reports composed success and live deployment as unperformed
