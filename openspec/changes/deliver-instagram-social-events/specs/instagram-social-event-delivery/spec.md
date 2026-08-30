## Purpose

Defines the acknowledged, least-privilege path that carries Instagram's durable SocialSource facts from its transactional outbox into the Platform-owned event stream without false delivery credit or content leakage.

## ADDED Requirements

### Requirement: Broker acknowledgement is the delivery boundary
Instagram SHALL mark an outbox row published only after the Platform-owned event stream acknowledges the exact stored envelope on the subject corresponding to its stored event type. Writing a log, opening a broker connection, sending bytes without an acknowledgement, or receiving a permission error SHALL NOT count as delivery.

#### Scenario: Acknowledged publication advances the outbox
- **WHEN** Instagram publishes an unpublished canonical SocialSource envelope and the event stream acknowledges it
- **THEN** the stream contains the exact stored envelope bytes on the matching allowlisted subject and that outbox row alone receives `published_at`

#### Scenario: Missing acknowledgement preserves retry state
- **WHEN** the broker is unavailable, rejects the credential or subject, times out, closes the connection, or fails to acknowledge the publish
- **THEN** the outbox row remains unpublished, records a content-free failed attempt, and is eligible for later byte-identical redelivery

### Requirement: Instagram publishes only its three canonical SocialSource facts
The delivery boundary SHALL map `social.source.captured.v1`, `social.source.updated.v1`, and `social.source.removed.v1` respectively to `evt.social.source.captured.v1`, `evt.social.source.updated.v1`, and `evt.social.source.removed.v1`. Any other stored event type or mismatch between the row event type and envelope event type MUST fail closed without publishing or marking the row.

#### Scenario: Every supported fact uses its exact subject
- **WHEN** one valid unpublished row of each supported event type is delivered
- **THEN** a consumer observes each byte-identical envelope once on its corresponding exact subject and no broader subject is used

#### Scenario: Unknown or mismatched fact is refused
- **WHEN** an unpublished row names a non-allowlisted type or its canonical envelope declares another event type
- **THEN** no event reaches the stream, the row remains unpublished, and the diagnostic contains identifiers and error class but no envelope content

### Requirement: Disabled transport never consumes durable intent
When no bus endpoint is configured, Instagram SHALL leave every outbox row unchanged and SHALL expose that broker delivery is disabled or unavailable. It MUST NOT substitute a logging, null, success-only, or in-memory transport that can advance `published_at`.

#### Scenario: Standalone service retains facts
- **WHEN** Instagram starts without bus configuration and creates a SocialSource outbox row
- **THEN** repeated publisher cadences do not change `published_at`, attempt count, payload, or event identity, and diagnostics do not print the payload

### Requirement: Historical logging acknowledgements have a bounded repair
Instagram SHALL provide an explicit operator command that, while the old service is stopped and before the real publisher starts, transactionally returns every previously logging-acknowledged SocialSource row to the unpublished retry lane. The command SHALL use only the existing outbox schema, report a content-free repaired count, and be idempotent and crash-safe within the documented cutover sequence.

#### Scenario: Cutover repair requeues false positives
- **WHEN** the stopped old deployment's database contains published captured, updated, or removed rows created before real broker delivery existed and the operator runs the bounded repair command
- **THEN** one transaction clears their false publication state, makes them immediately retryable, and reports the exact repaired count without rendering event content

#### Scenario: Repeated pre-cutover repair is a no-op
- **WHEN** the operator repeats the repair while the old service remains stopped and before the real publisher starts
- **THEN** the command reports zero repaired rows and leaves every envelope and event identity unchanged

#### Scenario: Repair crash changes nothing partially
- **WHEN** repair fails before its transaction commits
- **THEN** no partial subset of requeued rows is visible and the operator can retry the whole command

### Requirement: The Instagram broker identity is least privilege
Platform SHALL authorize the Instagram NKey to publish only the three canonical Instagram-owned SocialSource subjects in addition to the exact JetStream API and acknowledgement subjects required by its pre-provisioned browser-capture consumer. The identity MUST remain unable to publish commands or foreign event families, create or select consumers, or directly subscribe to fleet event subjects.

#### Scenario: Allowed event publication succeeds
- **WHEN** the configured Instagram identity publishes each canonical SocialSource subject and waits for JetStream acknowledgement
- **THEN** all three publishes are stored in `ratatoskr_events` and acknowledged

#### Scenario: Foreign authority stays denied
- **WHEN** the Instagram identity attempts a command publish, Platform operation fact, notification fact, arbitrary social subject, consumer creation, foreign durable access, or direct event subscription
- **THEN** NATS denies the attempt and the permitted browser-command consumer and three event subjects remain usable

### Requirement: Composed proof preserves evidence boundaries
The workspace SHALL exercise the real Instagram outbox, the configured Instagram NKey policy, and a real JetStream event stream together. The resulting evidence SHALL distinguish database commit, broker acknowledgement, downstream consumer acknowledgement, Knowledge processing, and live deployment.

#### Scenario: End-to-end broker delivery fixture
- **WHEN** the composed test commits a canonical Instagram outbox fact and runs one delivery pass against the Platform NATS configuration
- **THEN** the test observes the exact subject and envelope in `ratatoskr_events`, then observes `published_at` only after the publish acknowledgement

#### Scenario: Broker proof is not promoted to Knowledge proof
- **WHEN** the composed producer-to-stream test succeeds without a Knowledge consumer
- **THEN** its evidence reports broker delivery only and does not claim Knowledge indexing, live deployment, or provider acceptance
