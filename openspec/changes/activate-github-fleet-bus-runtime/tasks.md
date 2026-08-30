## 1. Coordinated task setup

- [x] 1.1 Create `changesets/GHB-017-github-fleet-bus-runtime.yaml` with bases `ratatoskr-platform` `070b718238c4e6e45a5b7fc08ebe719ed5374e33`, `ratatoskr-github` `fd60dd37e22b30056d2153ef22b271f75659e654`, and workspace `8f305f056bca06abe46c031797359f0118d5e0a4`, plus dependency graph, compatibility break, rollout, rollback, exact subject/durable inventory, required gates, and empty PR/merge/pin fields; no failing test because this is the required coordination record, and verify it with the workspace changeset validator.
- [x] 1.2 Create one isolated child worktree and task branch per affected product repository, assign one writer to each, and create/strictly validate the repository-local OpenSpec change before code edits; no failing test because this is required planning and Git isolation, and verify the pinned baseline submodules remain clean.

## 2. Platform fixed GitHub topology

- [x] 2.1 RED — in `crates/eventing/tests/stream_limits.rs`, add `github_durables_have_exact_stream_filters_and_delivery_limits` asserting all four durable names, streams, filters, explicit ack, deliver-all replay, ack wait, max deliveries, and idempotent reprovisioning; run `build-gate -- cargo test -p ratatoskr-platform-eventing --test stream_limits --locked` and observe failure because no GitHub consumers exist.
- [x] 2.2 GREEN — add the four fixed GitHub consumer specs and Platform-owned provisioning path, rejecting rather than mutating mismatched existing consumers; rerun the targeted test until green.
- [x] 2.3 RED — in `crates/eventing/tests/nats_permissions.rs`, add `github_identity_can_use_only_declared_bus_paths`, asserting the six allowed publish/fetch families and denied foreign publish, wildcard subscribe, unrelated durable, consumer create, stream purge/delete, and consumer delete; run the test through `build-gate --` and observe failure because the GitHub identity is absent.
- [x] 2.4 GREEN — add the GitHub public NKey placeholder and exact permissions to `deploy/nats/ratatoskr.conf`, extend synthetic fixture generation and `deploy/nats/README.md`, rerun the real-broker permission test, then run the complete Platform gate from `DEVELOPMENT.md` through `build-gate --` for compiler-backed commands.

## 3. GitHub classified wire outbox

- [ ] 3.1 RED — in `crates/catalog/tests/schema.rs`, add `bus_tables_store_classified_envelopes_and_recovery_state`, asserting only the six exact transport subjects plus outbox ordering/lease/retry/dead-letter fields and inbox transport/lease/terminal fields; run `build-gate -- cargo test -p ratatoskr-github-catalog --test schema --locked` and observe failure against the current unclassified schema.
- [x] 3.2 GREEN — edit the single current `schema.sql` in place to add the required constraints and recovery fields, remove phantom/unclassified subjects, update database test support, and rerun the schema test without creating a migration or compatibility view.
- [ ] 3.3 RED — in `crates/catalog/tests/readme_observations.rs` and `crates/catalog/tests/watch_analysis_flow.rs`, update/add `analysis_outbox_is_final_event_envelope` assertions for exact `evt.` subject, canonical event envelope, stable message/event identity, tenant, repository aggregate, revision, ordering key/sequence, and secret absence; run both targeted tests through `build-gate --` and observe failure because rows currently store raw payloads and unclassified subjects.
- [x] 3.4 GREEN — construct the complete current event envelope inside each analysis-producing transaction and update all readers/tests to the one classified shape; rerun both targeted tests until green.
- [ ] 3.5 RED — in `crates/catalog/tests/backup_policy_flow.rs`, add `policy_outbox_is_final_command_envelope` asserting exact `cmd.vault.target.desired.v1`, canonical command fields, policy version correlation, one estate ordering key/sequence, and no secret/provider payload; run the targeted test through `build-gate --` and observe failure because the outbox stores only the raw policy document.
- [x] 3.6 GREEN — create the complete Vault command envelope atomically with each changed policy version, update typed feedback fixtures/readers for classified subjects, and rerun `backup_policy_flow` until green.

## 4. GitHub recoverable outbox publisher

- [ ] 4.1 RED — add `crates/catalog/tests/outbox_claims.rs` tests `claims_due_rows_with_bounded_leases`, `same_key_preserves_sequence`, `unrelated_key_bypasses_failed_key`, `expired_lease_is_reclaimed`, `broker_failure_backs_off`, and `attempt_exhaustion_retains_dead_letter`; run through `build-gate --` and observe failure because the current outbox has no claim/retry state.
- [x] 4.2 GREEN — implement database claim, confirmation, failure, lease recovery, ordering and dead-letter operations with finite configuration and stable redacted error codes; rerun `outbox_claims` until green.
- [ ] 4.3 RED — add `services/catalog/tests/outbox_publisher.rs` tests `broker_ack_precedes_published_mark`, `restart_republishes_identical_message`, `nats_message_id_matches_outbox_identity`, and `publisher_never_creates_topology`, using a real disposable NATS broker; run through `build-gate --` and observe failure because the service has no publisher.
- [x] 4.4 GREEN — add the bounded JetStream publisher using stored subject/bytes and `Nats-Msg-Id`, mark rows only after broker acknowledgement, integrate lease recovery and cancellation, and rerun `outbox_publisher` until green.
- [ ] 4.5 RED — in `services/catalog/tests/operator_commands.rs`, add `dead_letter_requeue_preserves_identity_subject_and_payload` plus refusal tests for unknown, published, non-dead-letter, and malformed IDs; run through `build-gate --` and observe failure because no requeue command exists.
- [x] 4.6 GREEN — add the narrow operator requeue command and redacted machine-readable outcome, rerun its tests, and verify it creates no new row and edits no message bytes.

## 5. GitHub resumable inbox and durable consumers

- [ ] 5.1 RED — in `crates/catalog/tests/sync_commands.rs`, add `provider_failure_after_claim_is_resumable`, `expired_processing_lease_is_resumable`, `terminal_command_is_duplicate`, and `interrupted_full_snapshot_never_infers_absence`; run through `build-gate --` and observe the current bug where any existing claim is reported duplicate.
- [x] 5.2 GREEN — replace insert-or-duplicate sync claiming with received/processing/retryable/terminal states and leases, load the account-owned encrypted credential per delivery, preserve checkpoint/idempotency semantics, and rerun `sync_commands` until green.
- [ ] 5.3 RED — add `services/catalog/tests/inbound_bus.rs` tests for all four fixed durables: typed envelope dispatch, commit-before-ack redelivery, transient NAK/redelivery, terminal malformed quarantine, duplicate acknowledgement, and foreign-subject isolation; run through `build-gate --` and observe failure because no NATS consumers exist.
- [x] 5.4 GREEN — implement the four bounded fixed-durable consumers and subject-specific adapters, coupling ack/NAK/term to durable inbox outcomes without topology creation, and rerun `inbound_bus` until green.
- [ ] 5.5 RED — extend `crates/catalog/tests/config.rs` with `serve_bus_config_is_complete_finite_and_redacted`, asserting endpoint, protected NKey seed path, worker limits/timeouts/backoff, required serving encryption key, unknown-key refusal, and `Debug`/serialization redaction; run through `build-gate --` and observe failure because bus configuration is absent.
- [x] 5.6 GREEN — implement role-aware bus and worker configuration so serving/check-config validates the complete runtime while unrelated one-shot operator jobs require only their own dependencies; rerun config tests until green.

## 6. GitHub due workers, supervision, readiness, and drain

- [ ] 6.1 RED — add `services/catalog/tests/due_workers.rs` tests `analysis_dispatches_without_http_kick`, `dirty_policy_publishes_after_restart`, and `transient_iteration_failure_does_not_kill_worker`; run through `build-gate --` and observe failure because neither due function is called by the serving process.
- [x] 6.2 GREEN — add bounded due-analysis and policy-reconciliation loops over durable database state with independent retry/backoff and cancellation, then rerun `due_workers` until green.
- [ ] 6.3 RED — extend `services/catalog/tests/boot.rs` with `listener_only_process_is_unready`, `missing_or_drifted_durable_blocks_readiness`, `bus_loss_flips_and_recovery_restores_readiness`, `dead_letter_does_not_hide_shared_health`, and `worker_exit_is_not_ready`; run through `build-gate --` and observe the current listener-only process report ready.
- [x] 6.4 GREEN — supervise the publisher, four consumers and two due workers, expose shared dependency/heartbeat observations through readiness, and add bounded lag/retry/duplicate/rejection/dead-letter metrics without payloads or repository-name labels; rerun boot/admin tests until green.
- [ ] 6.5 RED — add `services/catalog/tests/shutdown.rs` tests for signal-before-inbox-commit redelivery, signal-after-commit duplicate absorption, outbox lease recovery, stopped new claims, listener drain, bus close, and bounded exit; run through `build-gate --` and observe failure because current shutdown covers only HTTP.
- [x] 6.6 GREEN — implement ordered shared cancellation and bounded join of HTTP, bus, publisher, consumers and due workers before database close; rerun shutdown tests and the complete GitHub repository gate from `DEVELOPMENT.md` through `build-gate --`.

## 7. GitHub deployment role and workspace allocation

- [ ] 7.1 RED — add `services/catalog/tests/deployment_profile.rs` assertions for `aarch64-unknown-linux-gnu`, dedicated user, domain `127.0.0.1:8092`, allocated operator `9469`, protected NKey/encryption inputs, owned database role, NVMe logging, filesystem/resource restrictions, `Type=exec`, and `TimeoutStopSec=130s`; run through `build-gate --` and observe failure because GitHub has no deployment artifacts.
- [x] 7.2 GREEN — add the systemd unit, redacted environment example, logrotate rule, deployment documentation and arm64 release/build verification, update GitHub README/DEVELOPMENT from “fleet bus planned” to the implemented boundary, and rerun the deployment profile plus release boot/readiness/SIGTERM smoke through `build-gate --`.
- [x] 7.3 Update `docs/DEPLOYMENT_TARGET.md` to allocate GitHub operator port `9469` and document that live monitoring firewall/config remains an unperformed deployment action; no failing test because this is the workspace source-of-truth allocation, and verify it matches the GitHub deployment-profile assertion and introduces no claim of host modification.

## 8. Workspace fixture integration and compatible snapshot

- [x] 8.1 RED — add `integration/tests/github_fleet_bus_profile_test.sh` assertions for exact child commits, four durables, GitHub permissions, service configuration, fixture-only credentials, bounded waits, redaction, and evidence labels; run the lightweight profile contract test and observe failure because no profile/runner exists.
- [x] 8.2 GREEN — add disposable PostgreSQL/NATS, fake GitHub HTTP provider, synthetic Platform/GitHub identities, fixture Knowledge/Vault peers, compose profile and runner so the profile contract test passes without live credentials or services.
- [ ] 8.3 RED — add end-to-end scenarios for scheduled sync, both outbound messages, Knowledge completion/failure and Vault acknowledgement, plus forced restart after inbound commit-before-ack and outbound broker-ack-before-mark; run the profile and observe failure at the currently absent GitHub runtime boundary.
- [x] 8.4 GREEN — run the profile against exact proposed child commits until each domain effect exists once, outbox rows converge, all durable acknowledgement floors advance, readiness/drain behave under deadlines, and no secret appears; record commands and proof boundaries in `integration/evidence/GHB-017.md`.
- [ ] 8.5 After both child PRs merge, update only the Platform and GitHub submodule pointers, regenerate `workspace.lock`, run topology/lock/dirty-baseline checks and the GHB-017 profile, and update the changeset with PR URLs, merged SHAs, verification, rollout, rollback and final snapshot; no new failing test because this publishes already-tested compatible commits.
- [ ] 8.6 Run `openspec validate --all --strict`, sync/archive only after all implementation tasks are complete, rerun archived specs, inspect staged diffs, commit only GHB-017 paths, push each authorized task branch, and verify every remote branch resolves to its local commit SHA; no failing test because these are final publication gates.

## 9. Implementation by repository

- [ ] 9.1 `ratatoskr-platform` — PR: pending; close only after tasks 2.1–2.4 pass the full repository gate and the PR merges first, then record its URL and merged commit in `GHB-017`.
- [ ] 9.2 `ratatoskr-github` — PR: pending; close only after tasks 3.1–7.2 pass the full repository gate against the merged Platform topology and the PR merges, then record its URL and merged commit in `GHB-017`.
- [ ] 9.3 `ratatoskr-workspace` — PR: pending; close only after tasks 7.3–8.6 pass against merged child SHAs, the workspace PR merges, and its verified pinned snapshot, URL and merge commit are recorded in `GHB-017`.
