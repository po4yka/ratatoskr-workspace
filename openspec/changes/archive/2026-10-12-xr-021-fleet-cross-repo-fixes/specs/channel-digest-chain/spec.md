## ADDED Requirements

### Requirement: Knowledge reads a digest manifest from channel-digests through one contract

Knowledge SHALL read the manifest of a digest run with `GET /v1/manifests/{manifest_id}` on the channel-digests API (`127.0.0.1:8098`), where the identifier is the bare lowercase UUID of the manifest reference. The request SHALL carry `Authorization: Bearer <RATATOSKR__AUTH__SERVICE_SECRET>`, `x-ratatoskr-owner-id` (the bare lowercase UUID of the user, never `user:<uuid>`), `x-ratatoskr-digest-run-id` (a bare UUID) and `x-ratatoskr-manifest-digest` (64 lowercase hexadecimal characters, the sha256 of the response body). The path template, the readiness path and the three header names are constants of `ratatoskr_channel_digest_contracts::manifest`, and both repositories SHALL import them. The response SHALL be `200`, `application/json`, `cache-control: no-store`, with a body that is exactly the stored canonical manifest bytes and never a re-serialization. A missing or wrong bearer, or an owner header that does not parse, SHALL be `401`. An absent manifest, a manifest of another owner, a run identifier that differs from the manifest's run, and a digest that differs from the stored one SHALL all be `404` with an empty body, indistinguishable from one another.

#### Scenario: A claim does not match the stored manifest

- **WHEN** Knowledge sends a digest header that differs from the stored sha256
- **THEN** channel-digests answers `404` with an empty body, the same as for an absent manifest, verified by `services/api/tests/api.rs` in `ratatoskr-channel-digests`

#### Scenario: Knowledge verifies what it read

- **WHEN** Knowledge receives the body
- **THEN** it hashes the bytes, compares them with the digest it asked for, and parses them with `ChannelDigestManifest::from_canonical_bytes`, which fails with an integrity error when re-canonicalizing the parsed value does not reproduce the input, verified by `crates/channel-digest-contracts/tests/manifest.rs` in `ratatoskr-contracts` and `crates/knowledge/tests/channel_digest_recap_manifest.rs` in `ratatoskr-knowledge`

#### Scenario: Readiness of the API listener

- **WHEN** a caller sends `GET /ready` with the bearer and no owner header
- **THEN** the API answers `200` when the database answers `select 1` and `503` otherwise, with `cache-control: no-store`, and `/live` is `404` on that listener

### Requirement: The manifest is a closed, verified artifact

`ChannelDigestManifest` SHALL carry the schema tag `channel_digest_manifest.v1`, the manifest reference, the owner, the digest run, the window and from 1 to 100 sources, SHALL reject unknown fields, and SHALL validate that: there are at most 20 distinct channels; every `published_at` lies within `[window.start_at, window.end_at)`; revision references are unique; the triple of channel, message identifier and revision is unique; and the sources are ordered ascending by publication time, channel, message identifier compared as a decimal integer, and revision. Canonical bytes SHALL be compact UTF-8 JSON with object keys in lexicographic order and no trailing newline, produced without depending on a map-ordering feature of any consumer.

#### Scenario: Sources are out of order

- **WHEN** a manifest lists sources in an order other than the one stated
- **THEN** `validate` fails and names the ordering rule

### Requirement: The read API exposes typed views to Platform

channel-digests SHALL answer, with the bearer and `x-ratatoskr-owner-id`, `GET /v1/subscriptions?page_size=1..100` (default 50), `GET /v1/results?page_size=1..100` (the owner's results, newest first, summaries only, no recap content) and `GET /v1/results/{result_id}`, with bodies defined by `ChannelDigestSubscriptionPage`, `ChannelDigestResultPage` and `ChannelDigestResultView` in the contracts. The query parameter SHALL be `page_size`. Platform SHALL expose `PUT /v1/channel-digests/subscriptions/{channel_username}`, `POST /v1/channel-digests/runs`, `GET /v1/channel-digests/subscriptions`, `GET /v1/channel-digests/results` and `GET /v1/channel-digests/results/{result_id}` to a signed-in user. The two writes SHALL require `Idempotency-Key`, answer `202` with `{operation_id, status:"accepted"}`, and create operations of kind `channel_digest.subscription.set` and `channel_digest.run`. The three reads SHALL call the channel-digests API through a typed loopback client with the shared secret and the caller's user identifier, and SHALL NOT use the generic reverse proxy, which strips `Authorization`. The channel username SHALL already match `^[a-z][a-z0-9_]{4,31}$` and SHALL NOT be case-normalized by the route. An upstream `404` SHALL be `404`; a transport failure or timeout SHALL be an upstream-unavailable or upstream-timeout error; any other non-success or unparsable body SHALL be an upstream-invalid-response error. Responses SHALL carry `cache-control: no-store`.

#### Scenario: A user subscribes and requests a run

- **WHEN** a signed-in user sends `PUT /v1/channel-digests/subscriptions/{name}` and then `POST /v1/channel-digests/runs` with idempotency keys
- **THEN** each answers `202`, and repeating a request with the same key replays the stored answer without a second operation, verified by `crates/public-api/tests/channel_digests.rs` in `ratatoskr-platform`

#### Scenario: A username is mixed case

- **WHEN** the path parameter has an uppercase letter
- **THEN** the route answers `400` instead of normalizing it

#### Scenario: Reads without a configured channel-digests API

- **WHEN** Platform has no channel-digests listener configured
- **THEN** the three read routes answer upstream-unavailable while the two command routes still work, verified by `crates/public-api/tests/channel_digests_reads.rs`

### Requirement: Platform commands the chain through typed envelopes

For a subscription or a run, Platform SHALL, in the transaction that reserves the idempotency key and creates the operation, enqueue one `CommandEnvelope` with producer `ratatoskr-platform`, correlation `operation:<operation_id>`, tenant `user:<principal>`, and an idempotency key derived from the operation (`operation.<operation_id>`), after `validate_for_publish` passes. The outbox message identifier SHALL be the command identifier. A run's window SHALL be the 24 hours ending at acceptance, with `accepted_at` equal to the window end. A scheduled occurrence SHALL use the occurrence identifier as the command identifier, `due_at` as the schedule grid point and not the current time, and `previous_due_at` as the grid point before it, no more than 7 days earlier.

#### Scenario: An HTTP retry and a redelivery collapse

- **WHEN** the same request is replayed by Platform's ledger and the outbox then redelivers the command
- **THEN** channel-digests records one inbox row, because the idempotency key derives from the operation identifier

### Requirement: Channel-digests registers its own schedule

At worker start, channel-digests SHALL enqueue one `platform.schedule.registration_requested.v1` command with its service name, the schedule name `daily-digest`, the owner `RATATOSKR__SCHEDULE__OWNER_USER_ID`, the cron `RATATOSKR__SCHEDULE__CRON` (default `0 6 * * *`), the occurrence command type, the operation kind `channel_digest.schedule.occurrence`, an empty payload template and `RATATOSKR__SCHEDULE__ENABLED`. The envelope producer SHALL equal `payload.service_name`. An unchanged configuration SHALL NOT be sent again and a changed one SHALL register again; Platform upserts on service name and schedule name. With no owner configured, channel-digests SHALL register nothing and log a safe class. `ratatoskr-github` stays allowlisted as a registrar and has no producer wired. The owner user SHALL exist in `identity.users`, because Platform has no system principal.

#### Scenario: Configuration changes

- **WHEN** the cron expression changes between two starts
- **THEN** one new registration command is enqueued, and an unchanged restart enqueues none, verified by `tests/registration.rs` in `ratatoskr-channel-digests` and `crates/operation-contracts/tests/schedule_registration.rs` in `ratatoskr-contracts`

### Requirement: Every step of a digest run is reported with the same vocabulary

channel-digests SHALL report through `platform.operation.reported.v1`, built from `OperationReported` and wrapped in an event envelope with producer `ratatoskr-channel-digests`, aggregate `operation:<uuid>`, correlation `operation:<uuid>` and tenant `user:<owner>`, published with the outbox identifier as message identifier. The semantic key SHALL be `operation:<operation_id>:<status>`. The report points are: a subscription change applied is `succeeded`; one rejected by the limit of 20 active subscriptions is `failed` with code `channel_digest.subscription_limit_reached`, not retryable, and its command is acknowledged; an accepted on-demand run is `running` at stage `acquiring`; a run with no selected sources is `succeeded` with no results, atomically with the run's completion; a Knowledge completion is `succeeded` or, when sources were omitted, `partially_succeeded` with one warning `channel_digest.context_omitted`, in both cases with the result `channel-digest-result:<result_id>` of kind `channel_digest.result`; a Knowledge failure is `failed` with code `channel_digest.recap.<safe_failure_class>`, retryable only for `provider_unavailable`, `provider_timeout` and `manifest_unavailable`; an acquisition failure is `failed` with `channel_digest.provider_unavailable`, retryable, atomically with the run's failure; a manifest that cannot be built is `failed` with `channel_digest.manifest_invalid`, not retryable; a schedule occurrence fanned out is `succeeded` at stage `fanned_out` on the occurrence operation. A scheduled digest run belongs to no Platform operation and SHALL emit no report.

#### Scenario: Knowledge reports a failed recap

- **WHEN** Knowledge publishes a recap failure with a safe failure class
- **THEN** the digest run's operation reaches `failed` with that class in the error code and the retryable flag from the list above, verified by `tests/operation_reports.rs` in `ratatoskr-channel-digests`

### Requirement: Knowledge composes the stored recap itself

The model SHALL be asked for a headline, an overview, topics, notable items and warnings only. Knowledge SHALL compose the stored recap, filling the contract, prompt and context versions, the output language, the manifest digest and the coverage counts from its own state, and SHALL add the `context_omitted_sources` warning itself when sources were omitted. The result SHALL then pass the existing recap validator. A recap run SHALL resume after a crash from its durable state with at most two provider calls in total.

#### Scenario: A run is interrupted after a response arrived

- **WHEN** the worker restarts when a response was received but not yet validated
- **THEN** the stored response is validated without a new provider call, verified by `crates/knowledge/tests/channel_recap_pipeline_resume.rs` in `ratatoskr-knowledge`
