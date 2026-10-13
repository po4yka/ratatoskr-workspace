## MODIFIED Requirements

### Requirement: Every step of a digest run is reported with the same vocabulary

channel-digests SHALL report through `platform.operation.reported.v1`, built from `OperationReported` and wrapped in an event envelope with producer `ratatoskr-channel-digests`, aggregate `operation:<uuid>`, correlation `operation:<uuid>` and tenant `user:<owner>`, published with the outbox identifier as message identifier. The semantic key SHALL be `operation:<operation_id>:<status>`. The report points are: a subscription change applied is `succeeded`; one rejected by the limit of 20 active subscriptions is `failed` with code `channel_digest.subscription_limit_reached`, not retryable, and its command is acknowledged; an accepted on-demand run is `queued` at stage `awaiting_acquisition`, and the transition from `accepted` to `acquiring` enqueues, in the same transaction, the report `running` at stage `acquiring`; a run whose acquisition was complete and selected no sources is `succeeded` with no results, atomically with the run's completion; a run whose sources are empty and whose acquisition was incomplete is `failed` with `channel_digest.provider_unavailable`, retryable, and safe class `provider_unavailable`, and never completes empty; a run with sources and an incomplete acquisition proceeds, its result outcome is `partial`, and its terminal report is `partially_succeeded` with the warning `channel_digest.acquisition_incomplete` ("Some channels could not be read completely in this window.") in addition to `channel_digest.context_omitted` when that also applies; a Knowledge completion is `succeeded` or, when sources were omitted, `partially_succeeded` with one warning `channel_digest.context_omitted`, in both cases with the result `channel-digest-result:<result_id>` of kind `channel_digest.result`; a Knowledge failure is `failed` with code `channel_digest.recap.<safe_failure_class>`, retryable only for `provider_unavailable`, `provider_timeout` and `manifest_unavailable`; an acquisition failure is `failed` with `channel_digest.provider_unavailable`, retryable, atomically with the run's failure; a manifest that cannot be built is `failed` with `channel_digest.manifest_invalid`, not retryable; a schedule occurrence fanned out is `succeeded` at stage `fanned_out` on the occurrence operation. A scheduled digest run belongs to no Platform operation and SHALL emit no report. Acquisition SHALL record per run, in `digest_runs.acquisition_incomplete`, whether any subscribed channel ended unavailable or reported itself partial.

#### Scenario: Knowledge reports a failed recap

- **WHEN** Knowledge publishes a recap failure with a safe failure class
- **THEN** the digest run's operation reaches `failed` with that class in the error code and the retryable flag from the list above, verified by `tests/operation_reports.rs` in `ratatoskr-channel-digests`

#### Scenario: The provider is down when a run is accepted

- **WHEN** an on-demand run is accepted while the provider connection is down
- **THEN** the operation reads `queued` at `awaiting_acquisition`, never `acquiring`, and fails at its deadline with `channel_digest.run_deadline_exceeded`, verified by `tests/incomplete_acquisition.rs` and the deadline tests of `ratatoskr-channel-digests` and flow F4 of the native smoke when it is run

#### Scenario: One channel errors and the other returns nothing

- **WHEN** acquisition ends with one channel unavailable and the other without posts
- **THEN** the run fails with `channel_digest.provider_unavailable` instead of completing as an empty success, verified by `tests/incomplete_acquisition.rs`; the same behaviour for a truncated window is not reachable in the native smoke, which has no MTProto credentials

## ADDED Requirements

### Requirement: Both channel-digests binaries log through a configured subscriber

The API and the worker SHALL install a tracing subscriber from `RATATOSKR__TELEMETRY__LOG_FORMAT` (`json`, the default, or `pretty`) and `RATATOSKR__TELEMETRY__LOG_FILTER` (an `EnvFilter` directive string), both accepted by both roles and validated at load. No event SHALL carry a post body, a channel name, a token or a session byte.

#### Scenario: Library code warns

- **WHEN** library code of either binary emits a `tracing::warn!`
- **THEN** the line reaches the process output in the configured format, verified by one test per binary in `ratatoskr-channel-digests`, and the worker's log holds the closed class `provider_unavailable` when the provider is down
