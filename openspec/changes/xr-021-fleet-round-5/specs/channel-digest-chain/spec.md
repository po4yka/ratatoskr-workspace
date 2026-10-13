## MODIFIED Requirements

### Requirement: Every step of a digest run is reported with the same vocabulary

channel-digests SHALL report through `platform.operation.reported.v1`, built from `OperationReported` and wrapped in an event envelope with producer `ratatoskr-channel-digests`, aggregate `operation:<uuid>`, correlation `operation:<uuid>` and tenant `user:<owner>`, published with the outbox identifier as message identifier. The semantic key SHALL be `operation:<operation_id>:<status>`. The report points are: a subscription change applied is `succeeded`; one rejected by the limit of 20 active subscriptions is `failed` with code `channel_digest.subscription_limit_reached`, not retryable, and its command is acknowledged; an accepted on-demand run is `queued` at stage `awaiting_acquisition`, and the transition from `accepted` to `acquiring` enqueues, in the same transaction, the report `running` at stage `acquiring`; a run whose acquisition was complete and selected no sources is `succeeded` with no results, atomically with the run's completion; a run whose sources are empty and whose acquisition was incomplete is `failed` with `channel_digest.provider_unavailable`, retryable, and safe class `provider_unavailable`, and never completes empty; a run with sources and an incomplete acquisition, or whose window held more eligible posts than one digest takes, proceeds, its result outcome is `partial`, and its terminal report is `partially_succeeded` with the warning `channel_digest.acquisition_incomplete` ("The digest does not cover every post of the window: some channels could not be read completely, or the window held more posts than one digest takes.") in addition to `channel_digest.context_omitted` when that also applies; a Knowledge completion is `succeeded` or, when sources were omitted, `partially_succeeded` with one warning `channel_digest.context_omitted`, in both cases with the result `channel-digest-result:<result_id>` of kind `channel_digest.result`; a Knowledge failure is `failed` with code `channel_digest.recap.<safe_failure_class>`, retryable only for `provider_unavailable`, `provider_timeout` and `manifest_unavailable`; an acquisition failure is `failed` with `channel_digest.provider_unavailable`, retryable, atomically with the run's failure; a manifest that cannot be built is `failed` with `channel_digest.manifest_invalid`, not retryable; a schedule occurrence fanned out is `succeeded` at stage `fanned_out` on the occurrence operation. A scheduled digest run belongs to no Platform operation and SHALL emit no report. Acquisition SHALL page a channel newest first and stop at the first page that contains a post published before the digest window starts: that post proves every later one older, the checkpoint is `completed` and the channel is not partial, and a post published exactly at the window start is inside the window. A page with no such post and a next cursor SHALL continue, a page that straddles the window start SHALL be processed in full before the walk stops, and a channel SHALL be partial only when the page limit is reached while every page so far still reached into the window, or when a provider error stops a walk that already has pages. Acquisition SHALL record per run, in `digest_runs.acquisition_incomplete`, whether any subscribed channel ended unavailable or reported itself partial; a deep history behind a window that was read completely is not partial.

#### Scenario: Knowledge reports a failed recap

- **WHEN** Knowledge publishes a recap failure with a safe failure class
- **THEN** the digest run's operation reaches `failed` with that class in the error code and the retryable flag from the list above, verified by `tests/operation_reports.rs` in `ratatoskr-channel-digests`

#### Scenario: The provider is down when a run is accepted

- **WHEN** an on-demand run is accepted while the provider connection is down
- **THEN** the operation reads `queued` at `awaiting_acquisition`, never `acquiring`, and fails at its deadline with `channel_digest.run_deadline_exceeded`, verified by `tests/incomplete_acquisition.rs` and the deadline tests of `ratatoskr-channel-digests` and flow F4 of the native smoke when it is run

#### Scenario: One channel errors and the other returns nothing

- **WHEN** acquisition ends with one channel unavailable and the other without posts
- **THEN** the run fails with `channel_digest.provider_unavailable` instead of completing as an empty success, verified by `tests/incomplete_acquisition.rs`; the same behaviour for a truncated window is not reachable in the native smoke, which has no MTProto credentials

#### Scenario: A deep history behind a window read on the first page

- **WHEN** a channel's history is deeper than the page limit times the page size and the window is satisfied on the first page
- **THEN** acquisition makes one provider page call, the report is not partial, the run is `succeeded` and the checkpoint is `completed`, verified by the acquisition tests of `ratatoskr-channel-digests` with PostgreSQL and a scripted provider

#### Scenario: A quiet channel with a deep history

- **WHEN** no post of a channel falls in the window although its history is deep
- **THEN** the run completes as an empty success with no sources instead of failing with `channel_digest.provider_unavailable`

#### Scenario: A window longer than the page limit

- **WHEN** the window spans more full pages than the page limit
- **THEN** the report is partial and the terminal report carries `channel_digest.acquisition_incomplete`; this path is covered by repository tests only, because the native smoke has no MTProto credentials

#### Scenario: A window with more posts than one digest takes

- **WHEN** the window holds more eligible posts than the worker's source count
- **THEN** the run is `partial`, its operation `partially_succeeded` with the warning above, and a content-free WARN carries the two counts, verified by the executor tests of `ratatoskr-channel-digests`

## ADDED Requirements

### Requirement: A digest takes the newest posts of its window

channel-digests SHALL select the newest `limits.source_count` post revisions of the window (ordered by `published_at` descending, then channel, then message identifier descending, then revision identifier descending), and SHALL order the selected revisions ascending for the manifest, whose ordering rule is unchanged. When more eligible revisions exist than were selected, the run's `acquisition_incomplete` flag SHALL be set. Exactly `source_count` eligible revisions are complete.

#### Scenario: 250 posts in one window

- **WHEN** a window holds 250 eligible post revisions and the source count is 100
- **THEN** the manifest holds the newest 100 in ascending order and the run is partial; with exactly 100 the run is complete, verified by the executor tests of `ratatoskr-channel-digests` against PostgreSQL and a scripted provider; the 100 post cap needs live MTProto and is not run in the native smoke

### Requirement: A post deleted upstream is withdrawn from later digests

After a page of a channel has been stored, channel-digests SHALL treat every stored, non-deleted revision of that channel whose message identifier lies inside the identifier range the page proves, and which the page does not contain, as deleted. The range of a page is from the lowest identifier of the page up to (excluding) the lowest identifier of the previous page of the same walk, or without an upper bound for the first page, and a short last page proves down to the start of the channel; a walk that stopped at the page limit proves only the pages it read. A provider error mid-walk proves nothing. A page that marks a post deleted withdraws it the same way, and a post without text counts as present. Withdrawing SHALL set `deleted_at`, clear the body and set `minimized_at` on all revisions of that message, and the selection SHALL exclude revisions with `deleted_at`. A recap that Knowledge already stored is not withdrawn; only later digests change.

#### Scenario: A post vanishes between two walks

- **WHEN** a stored post is absent from a later page that proves its range
- **THEN** it is withdrawn, absent from the next manifest and its body is null; a vanished identifier outside the proved range is kept and a provider error mid-walk withdraws nothing, verified by the acquisition tests of `ratatoskr-channel-digests`

### Requirement: Stored post bodies are minimized on a timer

The channel-digests worker SHALL run its minimization on a timer, with the strict keys `RATATOSKR__RETENTION__BODY_DAYS` (default 30, 8 to 3650, larger than the 7 day window bound) and `RATATOSKR__RETENTION__SWEEP_INTERVAL_SECONDS` (default 3600, 60 to 86400), documented in the worker configuration example. A pass SHALL handle at most 5000 rows, null the bodies older than the retention and set `minimized_at`, keep the provenance and the digests, leave a younger body untouched, count `channel_digests_bodies_minimized_total` and log a content-free line.

#### Scenario: Old bodies are minimized

- **WHEN** post revisions older than the retention window are stored and the worker's timer runs
- **THEN** their bodies are null and `minimized_at` is set within two sweep intervals, provenance and digests stay and a younger body is untouched, verified by the worker tests and by flow F4 of the native smoke when it is run
