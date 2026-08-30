## 1. Platform least-privilege expansion

- [x] 1.1 In `ratatoskr-platform/services/edge/tests/deployment_profile.rs`, add failing test `instagram_bus_identity_has_only_its_three_event_subjects` asserting the actual Instagram NKey stanza contains captured/updated/removed exact subjects while excluding `evt.>`, other event families, commands, consumer creation, and direct event subscription; run the targeted gated test and observe failure because all three event grants are absent.
- [x] 1.2 Add only the three Instagram event subjects to `deploy/nats/ratatoskr.conf`, update the operator guide, and verify task 1.1 passes without changing any existing consumer API/acknowledgement permission.
- [x] 1.3 In `ratatoskr-platform/crates/eventing/tests/nats_permissions.rs`, add failing real-broker test `instagram_nkey_permission_matrix_is_enforced_by_actual_config`; materialize the checked-in config with disposable NKeys and assert acknowledged publishes for captured/updated/removed plus denials for a command, Platform event, arbitrary social event, consumer creation, foreign durable access, and direct event subscription; observe red because the actual config denies the owned facts.
- [x] 1.4 Implement the mode-0600 actual-config fixture using the existing `nkeys`/Docker test stack and make task 1.3 green; verify the generated temporary files are removed and no seed appears in output or the repository diff.

## 2. Instagram acknowledged transport

- [x] 2.1 In `ratatoskr-instagram/crates/instagram-archive/tests/publishing.rs`, add failing tests `supported_event_types_map_to_exact_subjects`, `unknown_event_type_stays_unpublished`, `row_and_envelope_type_mismatch_stays_unpublished`, and `future_retry_is_not_claimed`; assert the exact subjects, unchanged payload/identity, null `published_at`, and due-time selection, then run the targeted gated test red against the current transport seam/query.
- [x] 2.2 Extend `EventTransport` with the stored event type, add the closed row/envelope/subject validator, select only due rows, and preserve content-free failure bookkeeping; verify task 2.1 passes and existing byte-identical redelivery tests remain green.
- [x] 2.3 In `ratatoskr-instagram/services/instagram-archive/tests/nats_outbox_delivery.rs`, add failing real PostgreSQL/JetStream tests `publish_ack_marks_only_acknowledged_row`, `permission_denial_retains_row`, `ack_timeout_retains_identical_bytes`, and `all_three_fact_types_use_exact_subjects`; observe red because the deployable exposes only `LoggingTransport`.
- [x] 2.4 Add the concrete finite-timeout JetStream transport using existing dependencies, await the publish acknowledgement, emit content-free diagnostics, and make task 2.3 green without logging an envelope or credential.
- [x] 2.5 In `ratatoskr-instagram/services/instagram-archive/tests/boot.rs`, add failing tests `configured_bus_wires_consumer_and_publisher_before_readiness` and `missing_bus_starts_no_success_transport_and_changes_no_outbox_row`; observe red because publisher construction is currently independent of bus configuration and always uses logging success.
- [x] 2.6 Factor one authenticated bus connection, wire the browser consumer and publisher from it before readiness, delete `LoggingTransport`, and start no publisher when the bus is absent; verify task 2.5 and existing command-consumer boot tests pass.

## 3. Historical false-ack repair

- [x] 3.1 In `ratatoskr-instagram/crates/instagram-archive/tests/outbox_repair.rs`, add failing tests `logging_era_social_facts_are_requeued_atomically`, `second_pre_cutover_repair_changes_zero_rows`, `foreign_event_types_are_untouched`, and `failed_transaction_changes_no_subset`; assert only existing outbox fields change and event IDs/payloads remain byte-identical, then observe red because the repair operation does not exist.
- [x] 3.2 Implement the advisory-locked transactional repair over the three supported SocialSource event types and verify task 3.1 passes without a schema or migration change.
- [x] 3.3 In `ratatoskr-instagram/services/instagram-archive/tests/repair_logging_outbox.rs`, add failing CLI tests `repair_requires_exact_confirmation`, `repair_prints_only_count`, and `repair_never_starts_network_or_http_planes`; observe red because the command grammar is absent.
- [x] 3.4 Add the closed `repair-logging-outbox --confirm logging-transport-never-delivered` operator command, safe exit codes, and stopped-service runbook; verify task 3.3 passes and repeated pre-cutover execution reports zero.

## 4. Workspace composition and evidence

- [ ] 4.1 Add `changesets/IG-014-instagram-event-delivery.yaml` with exact base/final SHAs, Platform-before-Instagram order, historical incident statement, stopped-service repair, rollback, proof boundaries, and PR/check fields; no failing test because this is coordination configuration. Verify repository IDs and recorded SHAs against Git directly.
- [x] 4.2 In `integration/tests/instagram_event_delivery_profile_test.sh`, add a failing composed test that accepts explicit Platform and Instagram worktree paths, starts the actual Platform NATS policy fixture plus PostgreSQL, invokes Instagram's real transport test, and requires exact subject/body/acknowledgement ordering and denial evidence; run it red against both base SHAs.
- [x] 4.3 Add the bounded IG-014 runner/fixture wiring and evidence template, then verify task 4.2 passes on a Docker-capable host and states that Knowledge consumption, provider behavior, deployment, and human alert receipt are unverified.
- [x] 4.4 Update Instagram, Platform, and workspace documentation so logging delivery is removed, the three ACL subjects and repair sequence are current, and outbox commit/broker ack/consumer ack/Knowledge/live deployment are distinct; no failing test because this is documentation. Verify every documented command exists and static docs tests pass.

## 5. Full verification and publication

- [x] 5.1 Run each child repository's complete local gate from its assigned worktree through the machine-wide `build-gate`, including format, clippy, build, test, deny/advisories, strict OpenSpec, deployment/static tests, and `git diff --check`; run the composed IG-014 profile, then record exact commands and outcomes without promoting fixture proof to deployment proof.
- [ ] 5.2 Review all three final diffs for scope, secrets, payload logging, weakened ACLs, retry/data-loss regressions, stale generated files, unrelated edits, and clean original baselines; stage only intended paths, inspect staged diffs, commit each repository in dependency order, push the explicitly authorized task branches, and verify exact remote branch SHAs.

## 6. Implementation by repository

- [ ] 6.1 `ratatoskr-platform` — merge the narrow ACL/test change first and record its pull request URL and merged SHA in IG-014; close only after exact-SHA hosted `ci`, `fleet`, `openspec`, and `zizmor` checks succeed.
- [ ] 6.2 `ratatoskr-instagram` — after Platform, merge the acknowledged publisher/repair change and record its pull request URL and merged SHA in IG-014; close only after exact-SHA hosted gates and the real-broker test succeed.
- [ ] 6.3 `ratatoskr-workspace` — after both child commits are known, merge the IG-014 changeset/integration evidence last and record its pull request URL and merged SHA; close only after the composed profile and hosted workspace checks succeed. No Contracts or Knowledge PR is part of IG-014.
