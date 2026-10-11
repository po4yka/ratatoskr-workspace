## ADDED Requirements

### Requirement: Every message type has one subject, one envelope and named parties

Every message type that crosses the bus SHALL be published to `<class>.<contract type name>`, where the class is `cmd` for a registered command and `evt` for a registered event, wrapped in the contract `CommandEnvelope` or `EventEnvelope`. The producing and consuming repositories SHALL be those registered for that type in `contracts.toml`. The class prefix is the privilege boundary: `cmd.>` is published only by Platform's Edge outbox pump, except for the command subjects a service is explicitly allowed to publish in the identity requirement below. Commands travel on the stream `ratatoskr_commands` (subjects `cmd.>`, publish refused when full) and events on `ratatoskr_events` (subjects `evt.>`, oldest dropped when full).

#### Scenario: A producer publishes a registered type

- **WHEN** a service publishes a message whose type is registered in `contracts.toml`
- **THEN** the subject is the class prefix plus the type name, and the stored body is the complete envelope with a `producer` that equals the registered producer, verified by the registry test `tools/contractsc/tests/live_message_types.rs` in `ratatoskr-contracts`

#### Scenario: An unregistered type cannot be published

- **WHEN** a relay reads an outbox row whose `event_type` is not in its closed list
- **THEN** the row cannot exist, because the schema's `CHECK` constraint lists the allowed types, and a row that predates the constraint stops the worker with a hard error instead of being skipped or retried forever

### Requirement: An outbox row stores the complete canonical envelope

Every producer outbox row used for the bus SHALL store the complete canonical envelope JSON and never a bare payload. The envelope's `event_id` or `command_id` SHALL equal the row's id and SHALL be sent as the `Nats-Msg-Id` header. A relay SHALL set `published_at` only after the JetStream acknowledgement resolves successfully; a failed publish SHALL leave the row unpublished, increment its attempt count, record a safe error class and defer the next attempt, so a failing head row never starves later rows.

#### Scenario: A publish is refused by the broker

- **WHEN** the broker does not acknowledge a publish
- **THEN** the row stays unpublished with an incremented attempt count and a later `next_attempt_at`, and a later row in the same outbox is still published

#### Scenario: A permission denial reads like an outage

- **WHEN** a publish is denied by the permission set
- **THEN** the client sees only a missing acknowledgement, the error text tells the operator to check the NATS server log for a `Publish Violation`, and no test observes the denial any other way than the missing acknowledgement or the client event callback

### Requirement: A service that cannot finish its work does not report ready

When the relay, publisher or consumer task of a service returns before an orderly shutdown, the service SHALL set its bus readiness to false and exit non-zero. A service that has a broker consumer configured SHALL also have configured the surface it needs to finish the work, or SHALL refuse to start with a typed configuration error and exit code 78.

#### Scenario: A consumer task dies

- **WHEN** a service's consumer task returns while the process is still running
- **THEN** the service reports not ready and exits non-zero rather than logging the error and staying ready

#### Scenario: A consumer is configured without the means to complete work

- **WHEN** a service starts with a bus consumer configured and without the credentials or endpoint it needs to resolve the work
- **THEN** it exits with code 78 and a configuration error naming the missing setting

### Requirement: Consumers verify their durable and never create one

A production worker SHALL fetch its Edge-provisioned durable by name and SHALL verify its filter, acknowledgement policy and acknowledgement wait against the fixed table below. A mismatch SHALL keep readiness false. A worker SHALL NOT create or update a durable on a `ratatoskr_*` stream. A development switch for unauthenticated local brokers MAY create topology and SHALL be refused together with an nkey seed. At a consumer, a message SHALL be acknowledged after the durable outcome is committed, terminated when it is permanently invalid, and negatively acknowledged with a two-second delay when the failure is transient.

#### Scenario: Edge has not yet provisioned the durable

- **WHEN** a service starts before Edge has created its durable
- **THEN** the service fails startup and is restarted by its supervisor until Edge has provisioned it, and it never creates the durable itself

#### Scenario: A durable differs from its specification

- **WHEN** Edge finds an existing durable whose filter, acknowledgement policy, wait or delivery limit differs from the table
- **THEN** Edge refuses to start with a bus error and does not modify the durable

### Requirement: The fixed durables and the completion bucket are provisioned by Edge

Edge SHALL create, after declaring the two streams, every durable in the following table and the key-value bucket `browser_worker_completions` (maximum age 24 hours, direct get allowed). All are pull consumers with instant replay and no delivery subject. Existing durables are unchanged: `platform_edge_projection`, `platform_ai_archive_chatgpt_projection`, `platform_ai_archive_claude_projection`, `ratatoskr_telegram_notifications`, `ratatoskr_x_browser_capture`, `ratatoskr_instagram_browser_capture` and `threads_browser_capture`; `platform_schedule_registration` is created by Edge's own registration consumer.

| Stream | Durable | Filter | Ack wait | Max deliver | Owner identity |
|---|---|---|---|---|---|
| commands | `ratatoskr_extractor_capture` | `cmd.content.capture.requested.v1` | 30 s | 12 | EXTRACTOR |
| commands | `ratatoskr_browser_worker` | `cmd.content.render.requested.v1` | 300 s | 12 | EXTRACTOR_BROWSER_WORKER |
| commands | `ratatoskr_knowledge_channel_recap` | `cmd.knowledge.channel_digest_recap.requested.v1` | 30 s | unlimited | KNOWLEDGE |
| commands | `ratatoskr_channel_digest_subscriptions` | `cmd.channel_digest.subscription.set_requested.v1` | 30 s | unlimited | CHANNEL_DIGESTS |
| commands | `ratatoskr_channel_digest_runs` | `cmd.channel_digest.run.requested.v1` | 30 s | unlimited | CHANNEL_DIGESTS |
| commands | `ratatoskr_channel_digest_schedule_occurrences` | `cmd.channel_digest.schedule.occurrence_requested.v1` | 30 s | unlimited | CHANNEL_DIGESTS |
| commands | `ratatoskr_vault_backup_policy` | `cmd.vault.backup_policy.apply_requested.v1` | 30 s | unlimited | VAULT |
| events | `ratatoskr_knowledge_documents` | `evt.content.document.extracted.v1` | 120 s | unlimited | KNOWLEDGE |
| events | `ratatoskr_knowledge_social_sources` | `evt.social.source.>` | 120 s | unlimited | KNOWLEDGE |
| events | `ratatoskr_knowledge_ai_archive` | `evt.ai_archive.>` | 120 s | unlimited | KNOWLEDGE |
| events | `ratatoskr_knowledge_repository_requests` | `evt.knowledge.repository_analysis.requested.v1` | 120 s | unlimited | KNOWLEDGE |
| events | `ratatoskr_github_analysis_completed` | `evt.knowledge.repository_analysis.completed.v1` | 30 s | unlimited | GITHUB |
| events | `ratatoskr_github_analysis_failed` | `evt.knowledge.repository_analysis.failed.v1` | 30 s | unlimited | GITHUB |
| events | `ratatoskr_github_policy_acknowledged` | `evt.vault.backup_policy.acknowledged.v1` | 30 s | unlimited | GITHUB |
| events | `ratatoskr_x_extractor_reports` | `evt.platform.operation.reported.v1` | 30 s | unlimited | X |
| events | `ratatoskr_channel_digest_recap_completed` | `evt.knowledge.channel_digest_recap.completed.v1` | 30 s | unlimited | CHANNEL_DIGESTS |
| events | `ratatoskr_channel_digest_recap_failed` | `evt.knowledge.channel_digest_recap.failed.v1` | 30 s | unlimited | CHANNEL_DIGESTS |
| events | `ratatoskr_extractor_render_awaits` | `evt.content.render.>` | 30 s | unlimited | EXTRACTOR |

Every events-stream durable other than `ratatoskr_extractor_render_awaits` uses explicit acknowledgement and delivers all messages; `ratatoskr_extractor_render_awaits` uses no acknowledgement and delivers only messages published after it is created. Knowledge's ingest acknowledgement wait SHALL equal the 120 seconds of its durables.

#### Scenario: A fresh broker starts in the documented order

- **WHEN** the operator reloads NATS with the reviewed configuration, starts Edge, and then starts the other services
- **THEN** every service finds its durable and becomes ready, verified by the real-broker matrix in `ratatoskr-platform` (`crates/eventing/tests/nats_permissions.rs`)

### Requirement: There are thirteen NATS identities in one reviewed file

`ratatoskr-platform/deploy/nats/ratatoskr.conf` SHALL be the only deployed authorization file and SHALL hold exactly thirteen identities: EDGE, TELEGRAM, CHATGPT, CLAUDE, X, INSTAGRAM, THREADS, EXTRACTOR, EXTRACTOR_BROWSER_WORKER, KNOWLEDGE, GITHUB, VAULT and CHANNEL_DIGESTS. Each public nkey is a unique placeholder `UREPLACE_ME_WITH_THE_PUBLIC_NKEY_OF_RATATOSKR_<NAME>_<X+>`, where the name is split from the filler at the last underscore. Every identity except EDGE SHALL subscribe only to `_INBOX.>` and SHALL have no `deny` block. A service that carries a copy of its own stanza in `deploy/nats/identity*.conf` SHALL carry one that equals the reviewed stanza once comments, whitespace and the nkey token are ignored. The extractor's earlier wide permission file SHALL NOT exist.

#### Scenario: The reviewed file holds exactly the thirteen identities

- **WHEN** `harness/crates/workspace-core/tests/bus_acl.rs::platform_conf_has_exactly_the_thirteen_identities` reads the pinned Platform configuration
- **THEN** it finds those thirteen names, each with a distinct placeholder, and every owning repository is checked out

#### Scenario: A service copy drifts from the reviewed stanza

- **WHEN** `bus_acl.rs::every_service_fragment_equals_its_platform_stanza` compares the extractor, browser worker, Knowledge, channel-digests, GitHub and Vault copies with their stanzas
- **THEN** every pair is equal, and a copy that differs fails the test and names the identity

#### Scenario: The old extractor file is gone

- **WHEN** `bus_acl.rs::extractor_permissions_conf_is_gone` looks for `deploy/nats/extractor-permissions.conf` in the extractor checkout
- **THEN** the file does not exist

### Requirement: Only Edge can create topology or read the bus wholesale

Only EDGE SHALL hold `$JS.API.>`, `cmd.>` or `$JS.ACK.>` without a durable suffix. No other identity SHALL hold `$JS.API.>`, `evt.>` or `cmd.>`, or any consumer-create, durable-create, stream-create, stream-update, message-get or direct-get permission on a `ratatoskr_*` stream. The only wildcards a non-EDGE publish allow may contain are `$JS.ACK.<stream>.<durable>.>`, `$JS.API.DIRECT.GET.KV_<bucket>.>` and `$KV.<bucket>.>`. Each durable's consumer-info, next-message and acknowledgement permissions SHALL appear in exactly one stanza, the owner named in the durable table.

#### Scenario: A stanza gains a wide permission

- **WHEN** a non-EDGE stanza is edited to allow `evt.>`, `$JS.API.>` or any consumer-create subject
- **THEN** `bus_acl.rs::non_edge_stanzas_obey_the_permission_invariants` fails and names the identity and the subject

#### Scenario: Two identities claim one durable

- **WHEN** the same durable's permissions appear in two stanzas
- **THEN** the same test fails and names the durable

### Requirement: The broker binds inside the container and is published on loopback

The NATS server SHALL bind `0.0.0.0` for its client port and `0.0.0.0:8222` for monitoring inside the container's network namespace, so Docker's published port reaches it. The container SHALL publish both ports on `127.0.0.1` only, and the client port SHALL additionally require an nkey. The publication, not the bind, is the boundary.

#### Scenario: The published port is reachable and is not exposed

- **WHEN** the compose file for the broker is read
- **THEN** it publishes `127.0.0.1:4222:4222` and `127.0.0.1:8222:8222` and no other address, as `docs/DEPLOYMENT_TARGET.md` allocates

### Requirement: The shared operation-report subject is documented as trusted by its envelope producer

`evt.platform.operation.reported.v1` is one subject published by the extractor, X, Instagram, Threads and channel-digests, and its authenticity rests on the envelope `producer` field. An identity allowed to publish it can therefore forge reports for another, and X can read every tenant's report metadata through its durable. The specification SHALL state this limit wherever those permissions are granted, and no code or test SHALL claim the subject is attributable beyond the envelope field. Closing the limit needs per-producer subjects and a contract change, and is a follow-up.

#### Scenario: The limit is stated where the permission is granted

- **WHEN** a reader reviews the identities that may publish `evt.platform.operation.reported.v1`
- **THEN** this requirement names the five identities and the forgery limit
