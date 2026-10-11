## ADDED Requirements

### Requirement: An explicit social capture is reported queued, then once terminally

For an explicit capture of an X, Instagram or Threads post, the service SHALL emit a `queued` report (stage `capture_queued`, no results, no error) in the same database transaction that commits the capture and claims the broker message, and later exactly one terminal report per operation: `succeeded` at stage `capture_preserved` with the result `social.post` targeting `social_source:<uuid>` and no error or warning, or `failed` at stage `capture_unavailable` with no results and exactly one error. The reports SHALL be built by the shared constructors of `ratatoskr_social_contracts::capture_report` (`queued_report`, `preserved_report`, `unavailable_report`, `report_envelope`) and wrapped in an event envelope with aggregate `capture:<capture_id>`, correlation `operation:<operation_id>`, causation `command:<command_id>`, tenant `user:<owner>`, event type `platform.operation.reported.v1`. A terminal report SHALL be recorded by an update that is conditional on no earlier report (`reported_at is null`) and that inserts the outbox row, so a redelivery or a crash between resolution and reporting reports without fetching again. A command that is valid and attributable to an operation and a tenant, but whose permalink the service cannot map, SHALL receive a terminal `failed` report with the inaccessible error rather than a silent acknowledgement. Platform projects these reports through its existing operation-report durable with no code change.

#### Scenario: A post is preserved

- **WHEN** an explicit capture resolves to a public post
- **THEN** the operation shows `queued` and then `succeeded` with one `social.post` result, and exactly one `succeeded` report exists for the operation, verified by `services/x/tests/explicit_capture_e2e.rs` in `ratatoskr-x`, `services/instagram-archive/tests/browser_capture_e2e.rs` in `ratatoskr-instagram` and `crates/threads-archive/tests/capture_resolution.rs` in `ratatoskr-threads`

#### Scenario: A report is repeated

- **WHEN** the same command is delivered twice, or the process stops after resolving and before reporting
- **THEN** one terminal report exists and the post is not fetched a second time

#### Scenario: The golden reports are byte-compared

- **WHEN** `crates/social-contracts/tests/capture_report.rs` in `ratatoskr-contracts` builds each report
- **THEN** its bytes equal the fixtures `social-capture-queued.json`, `social-capture-preserved.json`, `social-capture-deleted.json` and `social-capture-unavailable-retryable.json`

### Requirement: Unavailability has three causes and fixed wording

An unavailable post SHALL carry one of three errors: `social.source.deleted`, not retryable, "The post was deleted by the provider."; `social.source.unavailable`, not retryable, "The post cannot be retrieved publicly."; or `social.source.unavailable`, retryable, "The post could not be retrieved. Try again later." A provider answer that means deleted maps to the first; a private, protected, unsupported, unparseable-permalink or invalid-payload answer maps to the second; a throttle, a server error, a timeout or a transport failure maps to the third while attempts remain.

#### Scenario: A post was deleted

- **WHEN** the provider reports the post as not found
- **THEN** the terminal report is `failed` with `social.source.deleted` and `retryable=false`, with no retry

### Requirement: Transient failures retry on a bounded schedule

A service SHALL attempt a capture at most five times (configurable). After the n-th transient failure the next attempt SHALL be due after `min(30 s * 4^(n-1), 30 min)`, which is 30 seconds, 2 minutes, 8 minutes and 30 minutes. The fifth transient failure SHALL be the terminal retryable-unavailable report, so the worst case stays under one hour, far below Platform's 24 hour reaper of stale operations. A permanent class SHALL terminate on the first attempt. The resolver SHALL run as its own task, not in the consumer loop.

#### Scenario: A provider keeps throttling

- **WHEN** the provider answers throttling five times in a row
- **THEN** four retries are scheduled at 30 seconds, 2, 8 and 30 minutes and the fifth failure produces the terminal retryable-unavailable report, verified by `crates/x-sync/tests/public_capture/retry.rs` in `ratatoskr-x` and the capture-resolution tests of `ratatoskr-instagram` and `ratatoskr-threads`

### Requirement: A service that consumes captures can resolve them, or does not start

When a broker consumer for captures is configured, the resolution surface SHALL also be configured: for X a bearer token file and an HTTPS API base; for Instagram an endpoint and an access token file; for Threads an oEmbed endpoint and an absolute raw-object root. Otherwise the process SHALL refuse to start with exit code 78. The provider public-resolution rules are: X resolves with an app-only bearer and reports a protected post as unavailable, never preserved; Instagram resolves through Meta's oEmbed endpoint from the host allow-list `graph.facebook.com` and `graph.instagram.com`, HTTPS only, without redirects, with a 3 second connect and 10 second total timeout and a 256 KiB body cap; Threads resolves through its credential-free approved oEmbed client. Credentials SHALL never be logged, and the Instagram URL SHALL be redacted in errors.

#### Scenario: The bus is configured and the credential is not

- **WHEN** X starts with its bus configured and no bearer token path
- **THEN** it exits with code 78 and a configuration error, instead of reporting ready while captures cannot complete

### Requirement: An explicit capture publishes only what the capturing user's own public lookup returned

The explicit capture path of X SHALL be keyed by the owner taken from the command envelope's tenant, SHALL treat a command without a tenant as a poison command, and SHALL NOT read the shared per-provider post table, the account tables or any account-keyed table. A re-capture of the same owner and post SHALL resolve again and emit `social.source.updated.v1` only when the content digest changed, and SHALL always report success. Status identifiers SHALL be accepted from `x.com`, `www.x.com`, `mobile.x.com`, `twitter.com`, `www.twitter.com` and `mobile.twitter.com`. Instagram SHALL record one operation row per command, because captures deduplicate on user and canonical URL; a new capture on an unavailable record SHALL reset it to accepted, and on an already resolved record SHALL report `preserved` without fetching. Threads SHALL record its operation on the capture row and report the real `social_source_id` read after the write.

#### Scenario: A second user names a post another user captured

- **WHEN** user B captures the permalink of a post that user A already captured
- **THEN** user B's source is resolved for user B and no content stored for user A is published to B, verified by `services/x/tests/explicit_capture_e2e.rs` in `ratatoskr-x`

### Requirement: Every social fact is a complete envelope on a closed route

`social.source.captured.v1`, `social.source.updated.v1` and `social.source.removed.v1` SHALL be stored in the producer's outbox as complete event envelopes with producer `ratatoskr-x`, `ratatoskr-instagram` or `ratatoskr-threads`, aggregate `social_source:<id>` and tenant `user:<owner>`, and each service SHALL run one relay with a closed type-to-subject mapping. Instagram SHALL publish through a NATS transport and, without a configured bus, SHALL start no publisher and let rows accumulate unpublished; it SHALL NOT mark rows published on a log line. Threads SHALL map the removal event to its subject instead of aborting the pump on it.

#### Scenario: A removal row precedes other rows

- **WHEN** a Threads outbox holds a removal row before a captured row
- **THEN** both are published in order and the pump does not abort, verified by `crates/threads-archive/tests/nats_browser_capture.rs` in `ratatoskr-threads`

### Requirement: The browser extension sends one canonical timestamp

`captured_at` on the extension wire SHALL be RFC 3339 UTC with a literal `Z`, with seconds precision when the fractional part is zero and otherwise the fraction with its trailing zeros removed, matching the pattern `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{0,8}[1-9])?Z$`. The extension SHALL canonicalize at the single wire edge, so a draft queued with a trailing-zero fraction is repaired and not dropped. The contracts SHALL carry a valid fixture `2026-08-27T09:30:00.12Z` and an invalid fixture `2026-08-27T09:30:00.120Z` rejected by the deserializer.

#### Scenario: A millisecond value ends in zero

- **WHEN** the extension captures at a time whose milliseconds are 120
- **THEN** the request carries `...00.12Z`, which the contract accepts, and a queued draft holding `...00.120Z` is sent as `...00.12Z`
