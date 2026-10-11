## ADDED Requirements

### Requirement: An on-demand digest run always reaches a terminal state

The channel-digests worker SHALL run a reaper every 30 seconds, independent of the provider connection. A run in `accepted`, `acquiring` or `waiting_recap` whose `updated_at` is older than `RATATOSKR__LIMITS__RUN_DEADLINE_SECONDS` (default 1800, validated 60..=86400) SHALL become `failed` with the safe class `deadline_exceeded`, and for a run that owns a Platform operation the same transaction SHALL enqueue one `failed` operation report with error code `channel_digest.run_deadline_exceeded` and `retryable = true`, keyed so that a report already queued for the operation is not duplicated. A scheduled run has no operation and is failed the same way without a report. A late completion or failure fact from Knowledge for a run the reaper already failed SHALL change no state and enqueue no second report.

#### Scenario: Knowledge never answers

- **WHEN** a run waits for a recap that never arrives
- **THEN** after the deadline the run is `failed`, Platform shows the operation `failed` with `channel_digest.run_deadline_exceeded`, and exactly one report was published, verified by `tests/run_deadline.rs` in `ratatoskr-channel-digests`

#### Scenario: The recap arrives after the reaper

- **WHEN** Knowledge's completion fact arrives for a run that is already `failed`
- **THEN** the state and the single report are unchanged

### Requirement: A command that can be attributed is rejected with a report

When a subscription or run command decodes far enough to know its `operation_id` and owner but fails validation in the worker, the worker SHALL enqueue a `failed` report with error code `channel_digest.command_invalid` and `retryable = false`, mark the inbox row failed and acknowledge the message. Only a command that cannot be attributed SHALL be terminated without a report.

#### Scenario: A run command names an invalid window

- **WHEN** the worker receives a run command with a known operation and an invalid request
- **THEN** the operation ends `failed` with `channel_digest.command_invalid` instead of staying `running`

### Requirement: Knowledge's recap intake redelivers with growing delay

A transient failure of the recap inbox, the run lookup, the manifest attempt or the manifest load SHALL be negatively acknowledged with the delay `min(2 s * 2^(delivered-1), 60 s)` computed from the message's delivery count, so the loop never runs hotter than once per minute after the sixth delivery. Each redelivery SHALL increment `knowledge_channel_recap_redeliveries_total`. No new failure code is introduced: terminal failure of a stuck run is the channel-digests deadline.

#### Scenario: The run store fails persistently

- **WHEN** the run store fails on every delivery
- **THEN** the delays grow to 60 seconds and stay there, verified by `services/knowledge/tests/channel_recap_redelivery.rs` in `ratatoskr-knowledge`

### Requirement: The worker's intake and the read API stay within their bounds

The worker's `RATATOSKR__CHANNEL_RECAP__FETCH_BATCH` SHALL default to 1 and the worker SHALL send an in-progress acknowledgement every 10 seconds while a message is being processed, so a prefetched batch cannot outlive the 30 second ack wait of Knowledge's recap durable. The read API SHALL clamp `page_size` to its configured `RATATOSKR__LIMITS__PAGE_SIZE` instead of answering `400` for a larger valid request, because Platform sends up to 100.

#### Scenario: Platform asks for a page larger than the configured limit

- **WHEN** Platform requests `page_size=100` and the API limit is lower
- **THEN** the API answers `200` with at most the limit, verified by `services/api/tests/api.rs` in `ratatoskr-channel-digests`

### Requirement: Scheduled runs take their language from the worker's configuration

A scheduled run SHALL take its `output_language` from `RATATOSKR__SCHEDULE__OUTPUT_LANGUAGE` (`ru` or `en`, default `ru`, strict, worker only) instead of a schema default. The schedule registration payload and the contracts are unchanged.

#### Scenario: The operator chooses English

- **WHEN** the worker is configured with `en` and a scheduled occurrence runs
- **THEN** the run's output language is `en`

### Requirement: Platform refuses a schedule whose owner is not an active user

The schedule registration handler SHALL check `identity.users` for the owner inside the registration transaction and SHALL answer a rejection, with an audit event and the safe log class `schedule_owner_unknown`, when the user does not exist or is not active. The channel-digests worker's startup log SHALL state the same prerequisite.

#### Scenario: The configured owner is a random UUID

- **WHEN** the worker registers its schedule with an owner that is not a user
- **THEN** no schedule row is written and the rejection is audited, verified by `crates/scheduling/tests/registration.rs` in `ratatoskr-platform`

### Requirement: Knowledge's tenant deletion covers the channel recap tables

Tenant-scope deletion SHALL delete, inside the same transaction as the existing deletions and in foreign-key order (outbox, results, attempts, manifests, runs, inbox), every `channel_recap_*` row whose owner is the tenant, and SHALL queue the raw-response digests of the deleted attempts in `knowledge.blob_erasure_queue`. `DeletionCounts` and the deletion record SHALL carry `channel_recap_rows`, and the scope-empty check SHALL include it. Source and archive scope SHALL NOT touch these tables.

#### Scenario: A tenant is deleted after a recap

- **WHEN** a tenant with recap rows is deleted
- **THEN** every recap table is empty for that tenant, another tenant's rows are untouched, and the raw responses are queued for erasure, verified by `crates/knowledge/tests/deletion_isolation.rs` in `ratatoskr-knowledge`

### Requirement: The recap provider is never scripted by default

Knowledge's `RATATOSKR__CHANNEL_RECAP__PROVIDER_MODE` SHALL default to `openrouter`, which requires the provider API key when the recap is enabled. `scripted` SHALL be accepted only when `RATATOSKR__CHANNEL_RECAP__BUS_ENDPOINT` is a loopback `nats://` URL without a credentials file, and the process SHALL log a warning naming the mode at startup.

#### Scenario: An operator enables the recap and nothing else

- **WHEN** only `RATATOSKR__CHANNEL_RECAP__ENABLED=true` is set
- **THEN** the service demands the OpenRouter key instead of serving fixed text, verified by `crates/knowledge/tests/config.rs` in `ratatoskr-knowledge`
