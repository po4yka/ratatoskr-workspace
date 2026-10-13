## ADDED Requirements

### Requirement: Knowledge acknowledges every deletion fact it applies or refuses

Knowledge SHALL publish `evt.knowledge.deletion.acknowledged.v1`, the registered event `knowledge.deletion.acknowledged.v1` (payload `KnowledgeDeletionAcknowledged`: the acknowledged event identifier, the family `ai_archive` or `social`, the owner, the subject, the outcome `applied` or `refused`, a refusal that is present exactly when the outcome is `refused`, and the acknowledgement time), once for each `ai_archive.subject.tombstoned.v1` and `social.source.removed.v1` delivery that it has applied (the rows are deleted and the pending blobs are collected in the same handler pass), that duplicates an applied one, or that it refuses as `foreign_subject`. The envelope producer SHALL be `ratatoskr-knowledge`, the tenant the owner, the aggregate the subject, the correlation identifier that of the acknowledged envelope and the causation identifier `event:<acknowledged_event_id>`. A delivery that Knowledge rejects for any other reason (undecodable, wrong producer, no tenant) cannot be attributed and SHALL NOT be acknowledged. A duplicate delivery of an acknowledged fact SHALL queue the acknowledgement again when the earlier one is more than a minute old, so an acknowledgement lost to the events stream's drop-oldest retention is produced again when the producer re-sends. The five producers (ChatGPT, Claude, X, Instagram and Threads) SHALL each read the acknowledgements on a durable of their own, `ratatoskr_<service>_deletion_acks`, that Edge provisions with the standard 30 second acknowledgement wait, and no producer SHALL hold the permission to read another producer's durable.

#### Scenario: A tombstone is applied

- **WHEN** Knowledge applies a tombstone for a conversation of a user
- **THEN** exactly one acknowledgement with the outcome `applied` is published after the blobs are erased, verified by the ingest tests of `ratatoskr-knowledge` against a real broker and PostgreSQL and by flow F6 of the native smoke when it is run

#### Scenario: A tombstone names a subject of another owner

- **WHEN** a tombstone arrives for a subject that belongs to another tenant
- **THEN** it is acknowledged with the outcome `refused` and the refusal `foreign_subject`, and the other tenant's data is untouched

#### Scenario: An acknowledgement is dropped from the stream

- **WHEN** a tombstone that Knowledge already acknowledged arrives again after more than a minute
- **THEN** a second acknowledgement is published

### Requirement: A producer re-sends a deletion fact until Knowledge acknowledges it

ChatGPT and Claude (`ai_archive.subject.tombstoned.v1`) and X, Instagram and Threads (`social.source.removed.v1`) SHALL keep a deletion fact's outbox row after the broker accepts it, with `acknowledged_at`, `ack_outcome` (`applied` or `refused`), `resend_count` and `next_resend_at`, and SHALL publish the stored envelope bytes again, unchanged (same event identifier, same `Nats-Msg-Id`), when `next_resend_at` has passed and no acknowledgement has arrived. After a resend the next wait SHALL be `least(resend_after * 2^resend_count, resend_cap)`. The resend SHALL stop only when `acknowledged_at` is set; a `refused` outcome also sets it, raises an ERROR log line and the counter `<service>_tombstone_refused_total`, and leaves the data in Knowledge for an operator to inspect. The keys `RATATOSKR__TOMBSTONE__RESEND_AFTER_SECONDS` (default 600, 30 to 86400) and `RATATOSKR__TOMBSTONE__RESEND_CAP_SECONDS` (default 21600, at least the first, at most 604800) SHALL be documented in each service's configuration example. Because the events stream collapses a repeated `Nats-Msg-Id` inside its 120 second duplicate window, a resend sooner than that is a no-op at the broker; the default is 600 on purpose and a test that wants a second stream copy SHALL set at least 150. No deletion path SHALL remove an unacknowledged deletion row. The gauges `<service>_unacknowledged_tombstones` and `<service>_oldest_unacknowledged_tombstone_age_seconds` SHALL be exported on the operator listener, and a producer's readiness SHALL NOT depend on them, so a Knowledge outage does not make a producer unready.

#### Scenario: Knowledge is down when a tombstone is published

- **WHEN** Knowledge is stopped, a tombstone is published and `resend_after` passes
- **THEN** the same event identifier is on the stream a second time with `resend_count` 1, and when Knowledge starts it applies the tombstone once, publishes one acknowledgement, the producer's row gets `acknowledged_at` and `ack_outcome` `applied`, and no further resend follows, verified by the producer repositories' broker tests and flow F6 of the native smoke for ChatGPT and Claude when it is run

#### Scenario: A later deletion meets an unacknowledged row

- **WHEN** a second deletion runs while an earlier tombstone is still unacknowledged
- **THEN** the unacknowledged row is not removed

#### Scenario: Knowledge refuses the subject

- **WHEN** the acknowledgement carries the outcome `refused`
- **THEN** the resend stops, the refusal counter rises and an ERROR line is logged

### Requirement: Every tombstone is addressed to the owner the subject was announced under

ChatGPT and Claude SHALL record, in the same transaction that enqueues each `ai_archive.*` fact, the owner that fact carries in a ledger `announced_subjects` (subject kind, subject identifier, archive, owner reference, account), with no foreign key to exports, so that no export deletion cascades it. A deletion SHALL emit one tombstone per distinct owner the ledger holds for each subject, addressed to that owner, and SHALL consult the live `PLATFORM_ACCOUNTS` mapping on no deletion path. A subject with no ledger row (never announced) SHALL emit no tombstone, add no gap and not fail the request. A re-announced survivor SHALL carry the owner of the retained archive's own ledger row. The Claude deletion plan SHALL be accepted after the account has left the mapping, and its request SHALL store the supplied account reference as given.

#### Scenario: The mapping changes between import and deletion

- **WHEN** an archive is imported under one mapping, the mapping is replaced by one that no longer lists the account, and the account's data is deleted
- **THEN** the tombstones name the original owner, Knowledge removes that user's data and no `downstream_tombstone_unbound` gap exists, for both providers, verified by the repositories' tests against PostgreSQL and flow F6 of the native smoke when it is run

#### Scenario: Two owners for one account

- **WHEN** two archives of one account were announced under two different users and a tenant-scope deletion runs
- **THEN** a conversation shared by both gets one tombstone per owner and no third user receives one

### Requirement: Edge erases the producer's published copy of deleted content on request

Edge, the only identity that holds `$JS.API.>`, SHALL erase single messages of `ratatoskr_events` when ChatGPT or Claude sends the registered command `platform.stream_erasure.requested.v1` (payload `PlatformStreamErasureRequested`: a `privacy_request` reference, the owner, and 1 to 500 strictly ascending stream sequences) on `cmd.platform.stream_erasure.requested.v1`. Producers SHALL record the stream sequence of every published outbox row, and every path that deletes a published content-bearing fact (`archive.imported`, `conversation`, `project` and `artifact` facts, never a tombstone or an operation report) SHALL enqueue the erasure command for the sequences it removes, per owner and in the same transaction. Edge SHALL consume the command on its own durable `platform_stream_erasure`, SHALL validate that the envelope producer is ChatGPT or Claude, that the tenant equals the payload owner and that the aggregate equals the request reference, and SHALL erase a sequence only when its subject is one of the seven content-bearing `evt.ai_archive.*` subjects, the stored envelope's producer equals the command's producer and its tenant equals the payload owner; anything else SHALL be counted `refused` and left alone, and a sequence that is no longer in the stream SHALL be counted `missing`. Edge SHALL write one content-free audit row per command (producer, owner and the three counts) and count `platform_stream_erasure_total{outcome="erased"|"missing"|"refused"}`. No stanza other than EDGE SHALL hold a publish allow under `$JS.API.STREAM.` other than the read-only info of a KV bucket's stream, and only CHATGPT and CLAUDE SHALL hold the publish allow for the erasure command. The erasure is eventual: a deletion SHALL NOT wait for it. Social facts stay in the events stream after an Instagram, Threads or X deletion until retention drops them.

#### Scenario: A deleted conversation's fact leaves the stream

- **WHEN** a published conversation fact is deleted by its producer
- **THEN** the stream message of that conversation is gone within 30 seconds, the neighbouring conversation's message is still there, Edge's audit row has counts and no content, and the NATS log has no publish violation, verified by the Platform and producer broker tests and flow F6 of the native smoke when it is run

#### Scenario: A producer names a message it did not publish

- **WHEN** the ChatGPT identity asks to erase another producer's message, another tenant's message, a tombstone or a message of another subject family
- **THEN** nothing is erased and the outcome is counted `refused`

#### Scenario: A stanza gains the right to delete

- **WHEN** a non-EDGE stanza is given a publish allow such as `$JS.API.STREAM.MSG.DELETE.ratatoskr_events`
- **THEN** `bus_acl.rs` fails and names the identity and the subject

### Requirement: The workspace checks that the acknowledgement path is provisioned and authorised

The workspace harness SHALL fail when Edge's durable table and the services disagree about the acknowledgement durables, and SHALL fail when the set of stanzas allowed to publish `evt.ai_archive.subject.tombstoned.v1` or `evt.social.source.removed.v1` differs from the set of services that have a `*_deletion_acks` durable. It SHALL also check that KNOWLEDGE alone may publish `evt.knowledge.deletion.acknowledged.v1`.

#### Scenario: A producer is added without its durable

- **WHEN** a stanza gains the publish allow for a deletion fact and Edge's table has no `ratatoskr_<service>_deletion_acks` row for it
- **THEN** `tombstone_acks.rs` fails and names the identity

#### Scenario: A durable is renamed on one side

- **WHEN** one `*_deletion_acks` name differs between Edge's table and the owning service
- **THEN** `bus_durables.rs` fails and names the durable
