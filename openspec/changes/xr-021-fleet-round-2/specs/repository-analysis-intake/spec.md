## ADDED Requirements

### Requirement: GitHub originates analysis requests at runtime and bounds its provider calls

A `track` action SHALL register a metadata-delta watch for owner `user:<principal>` whose first evaluation queues an analysis request, so tracking a repository queues its first analysis; `metadata` and `star` actions register no watch. The action route SHALL preserve the README while applying fresh metadata and SHALL evaluate the enabled watches after every fresh body, through the same code as the periodic observer. A queued request's `source_revision.readme` SHALL be `Present` with a blob reference when a README was fetched and `Absent` with the real reason otherwise. A periodic observer SHALL run every `RATATOSKR__WATCH__OBSERVE_INTERVAL_SECONDS` (default 3600, `0` disables, at most 604800) and observe at most `RATATOSKR__WATCH__BATCH` (default 10, 1..=100) repositories that have an enabled watch, oldest observation first. Every provider call SHALL be bounded by a connect timeout of 5 seconds and a total timeout of 30 seconds by default, configurable through `RATATOSKR__PROVIDER__TIMEOUT_MS` (1000..=120000), and a timeout SHALL be a transport error. A `404` from the grant-revocation call SHALL be accepted as already revoked only after a probe of `GET {base}/user` with the same token answers `401`; any other outcome is an error that the account erasure reports as incomplete.

#### Scenario: A repository is tracked

- **WHEN** a user tracks a repository
- **THEN** exactly one `evt.knowledge.repository_analysis.requested.v1` is published for it, and the request reaches a terminal status when Knowledge's completion or failure fact is consumed, verified by `services/catalog/tests/watch_observer.rs` in `ratatoskr-github`

#### Scenario: The provider stalls

- **WHEN** the provider does not answer within the timeout
- **THEN** the action answers a bounded error and account erasure does not hang
