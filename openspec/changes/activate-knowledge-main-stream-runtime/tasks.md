## 1. KNO-018 task topology

- [x] 1.1 Create the KNO-018 cross-repository changeset and isolated worktrees for Contracts, Platform, GitHub, Knowledge, Extractor, and Workspace; this cannot start from a failing test because it records Git topology, and verification is clean baseline submodules plus one writer, base SHA, role, dependency, rollback, and required gate per repository.
- [x] 1.2 Record the live-publisher exclusions and exact proof categories in the changeset; this is coordination metadata rather than behavior, and verification is that X, Instagram, Threads, GitHub publication, ChatGPT, and Claude are named as separate dependencies rather than claimed by fixture injection.

## 2. Contracts: typed extracted-document fact

- [x] 2.1 RED: in `tools/contractsc/tests/fixtures.rs`, add `document_extracted_event_is_registered_with_existing_wire_payload`, asserting registry identity, `content.document.extracted.v1`, Extractor producer, Knowledge consumer, direct `Document` payload, generated schema/fixture paths, and invalid-payload refusal; run the focused test and observe it fail because the event is unregistered.
- [x] 2.2 GREEN: register the typed v1 event in `ratatoskr-document-contracts` and `contracts.toml`, add compatibility and invalid fixtures, regenerate checked-in schemas/bindings, and verify the focused test plus Contracts format, clippy, test, schema, fixture, determinism, and generated-drift gates pass through `build-gate` where compiler-backed.

## 3. Platform: fixed topology and least privilege

- [x] 3.1 RED: in `crates/eventing/tests/stream_limits.rs`, add `edge_preprovisions_exact_knowledge_consumers_and_refuses_drift`, asserting one exact multi-filter primary durable, the recap durable, cursor-preserving reuse, and mismatch refusal; run it against a real test broker and observe the consumers are absent.
- [x] 3.2 GREEN: add the two Knowledge consumer specifications to the fixed inventory and Edge startup provisioning, validate the broker's exact multi-filter behavior, and verify the focused stream tests pass without consumer mutation by Knowledge.
- [x] 3.3 RED: in `crates/eventing/tests/nats_permissions.rs` and `services/edge/tests/deployment_profile.rs`, add `knowledge_identity_is_limited_to_fixed_consumers_and_terminal_subjects`, asserting required describe/fetch/ack/publish operations succeed while consumer creation, foreign access, broad subscriptions, source publication, and stream administration fail; observe the test fail because no Knowledge identity exists.
- [x] 3.4 GREEN: render the Knowledge NKey permissions and seed path from the fixed inventory, update deployment/operator configuration, and verify the real-broker permission matrix plus deployment-profile tests pass without exposing a production seed.

## 4. GitHub: immutable README read boundary

- [x] 4.1 RED: in `services/catalog/tests/repository_content_api.rs`, add `knowledge_reads_only_authorized_digest_verified_readme`, asserting service authentication, owner/repository scope, exact BlobRef digest/media-type/length, response limit, and denial of foreign, arbitrary URL, oversized, missing, and corrupt requests; run it and observe the internal route is absent.
- [x] 4.2 GREEN: add the bounded internal README endpoint and service-auth policy over Catalog-owned immutable bytes, wire production configuration without embedding credentials, and verify the focused API/security tests plus the GitHub repository gate pass.

## 5. Knowledge: primary runtime and durable recovery

- [x] 5.1 RED: in `services/knowledge/tests/primary_boot.rs`, add `primary_role_requires_exact_durable_and_live_supervisors`, asserting startup opens but never creates `ratatoskr_knowledge_main`, `/ready` stays 503 for absent/drifted/disconnected topology or a stopped worker, and reconnect restores readiness; run it and observe the current admin-only process reports ready.
- [x] 5.2 GREEN: add validated primary-bus/provider/resolver/worker configuration, open the fixed durable, supervise all handles in `main`, and make readiness reflect storage, topology, dependencies, and worker health; verify `primary_boot` passes while deliberately non-primary test commands remain explicit.
- [x] 5.3 RED: in `services/knowledge/tests/primary_intake.rs`, add `delivery_is_acked_only_after_collision_checked_atomic_admission`, covering all exact subjects, subject/type/producer/tenant/aggregate/payload validation, duplicate equality, conflicting event IDs, commit failure NAK, permanent rejection Term, and processing of a valid event after poison input; run it and observe no primary adapter exists.
- [x] 5.4 GREEN: implement canonical envelope dispatch and transactional receipt/source/work admission for document, social, AI-archive, and repository families, including content-free rejection evidence and ACK/NAK/Term classification; verify the intake test passes with no inference inside the delivery boundary.
- [x] 5.5 RED: in `crates/knowledge/tests/work_recovery.rs`, add `admitted_work_reclaims_every_state_without_duplicate_effects`, asserting crash-after-admission recovery, lease expiry, every persisted article/family state, response reuse, bounded retry, final failure, and explicit uncertain-provider handling; run it and observe receipt-only duplicates and intermediate states strand work.
- [x] 5.6 GREEN: edit the first-version schema definition in place to add collision evidence, work state, eligibility, attempts, and leases; make family admission transactional and workers claim/resume each legal state without blind retry of an uncertain external call; verify `work_recovery` passes with a scripted idempotent provider and no migration file exists.
- [x] 5.7 RED: in `crates/knowledge/tests/source_lifecycle.rs`, add `removal_and_tombstone_delete_scoped_derivatives_and_block_stale_replay`, covering social capture/update/old replay/removal, archive state-before-head, tombstone, stale replay, duplicate deletion, and cross-tenant isolation; run it and observe social removal is unsupported and suppression is incomplete.
- [x] 5.8 GREEN: implement owner-scoped source-head ordering, social removal, archive tombstone suppression, and atomic derived analysis/embedding/search deletion; verify lifecycle tests pass and unrelated owners/subjects remain unchanged.
- [x] 5.9 RED: in `services/knowledge/tests/repository_readme_resolution.rs`, add `repository_analysis_uses_authenticated_bounded_blob_resolution`, asserting authorized resolution and independent digest/media/length verification plus retry/final classification for unavailable, unauthorized, oversized, missing, and corrupt responses; run it and observe no production resolver exists.
- [x] 5.10 GREEN: implement the GitHub service client behind `RepositoryReadmeResolver`, enforce end-to-end timeout and response limit, wire it into repository work, and verify the focused resolver test emits one completion or typed failure without direct database/path/URL access.
- [x] 5.11 RED: in `crates/knowledge/tests/terminal_outbox.rs`, add `terminal_state_and_fact_survive_publish_uncertainty`, asserting atomic success/failure plus outbox insertion, stable envelope/message identity, broker-ack marking, idle-start drain, reconnect retry, and duplicate logical outcome refusal for social, AI archive, and repository work; run it and observe only recap has an outbox.
- [x] 5.12 GREEN: add the general transactional terminal outbox and independently supervised NATS publisher, move family terminal transitions into the shared transaction boundary, and verify the focused fault tests pass with `Nats-Msg-Id` deduplication.
- [x] 5.13 RED: in `services/knowledge/tests/primary_shutdown.rs`, add `shutdown_stops_claims_settles_delivery_joins_workers_then_closes_storage`, interrupting fetch, admission, provider, indexing, and outbox boundaries; run it and observe worker handles are not all owned or joined.
- [x] 5.14 GREEN: implement ordered cancellation and bounded drain for intake, leased workers, indexer, resolver calls, and outbox publication; verify the shutdown test and primary lag/rejection/retry/outbox metrics tests pass without high-cardinality or user-content labels.
- [x] 5.15 Refactor the now-green article and family state-machine code so shared leasing, resume, and terminal transitions have one implementation while preserving all passing behavior tests.

## 6. Extractor: typed publication

- [x] 6.1 RED: in `crates/eventing/tests/completion.rs`, add `document_completion_uses_registered_typed_event_without_wire_drift`, asserting construction through the typed payload, exact subject/envelope/aggregate identity, and byte-equivalent canonical fixture; run it and observe the manual unregistered construction path.
- [x] 6.2 GREEN: update Extractor's Contracts pin and construct the document event through the registered type without changing its payload, outbox transaction, or subject; verify the focused test and Extractor repository gate pass.

## 7. Workspace integration and fault matrix

- [x] 7.1 RED: in `integration/tests/knowledge_main_stream.bats`, add `all_primary_families_recover_and_publish_terminal_state`, launching task-namespaced NATS/Postgres/Extractor/GitHub/Knowledge/scripted-provider services and asserting document, social, AI-archive, and repository outcomes, readiness, exact durable topology, search visibility, and terminal facts; run it against current pins and observe failure because Knowledge has no primary durable or runtime adapter.
- [x] 7.2 GREEN: add the KNO-018 Compose profile, canonical injection helpers, real Extractor and GitHub paths, scripted provider, health checks, and deterministic teardown; verify the main-family scenario passes with no dependency on baseline submodule edits or local-only path overrides.
- [x] 7.3 RED: extend `integration/tests/knowledge_main_stream.bats` with `replay_poison_tombstone_outbox_and_shutdown_faults_are_safe`, asserting commit-before-ACK restart, every durable state, poison-followed-by-valid delivery, broker outage/readiness recovery, terminal publish uncertainty, social removal, archive tombstone, stale replay, and SIGTERM drain; observe at least the current replay and removal cases fail before the recovery implementation is pinned.
- [x] 7.4 GREEN: add only the task-namespaced fault controls and evidence collection needed by the scenario, then verify the complete replay/deletion/shutdown matrix passes and reports scripted-provider fixture proof separately from live producer/provider/deployment proof.
- [x] 7.5 Run `openspec validate activate-knowledge-main-stream-runtime --strict`, workspace topology/lock/contract-impact checks, every affected repository gate, and the full KNO-018 composed profile; record exact commands, outputs, SHAs, rollback result, baseline cleanliness, and every unavailable hosted/live proof in the changeset.

## 8. Implementation by repository

- [ ] 8.1 `ratatoskr-contracts` — merge the typed document-event pull request first and replace `[PR: pending]` with the merged PR URL and merge SHA; this item closes only after required hosted checks and merge are observed.
- [ ] 8.2 `ratatoskr-platform` — merge the fixed Knowledge consumer/NKey pull request after Contracts compatibility is known and replace `[PR: pending]` with the merged PR URL and merge SHA; this item closes only after real-broker permissions and hosted checks pass.
- [ ] 8.3 `ratatoskr-github` — merge the backward-compatible immutable README boundary pull request and replace `[PR: pending]` with the merged PR URL and merge SHA; this item does not claim GitHub event publication and closes only after hosted checks and merge are observed.
- [ ] 8.4 `ratatoskr-knowledge` — merge the primary runtime/durability pull request against the published Contracts and available Platform/GitHub boundaries, replace `[PR: pending]` with the merged PR URL and merge SHA, and close only after repository-local and composed recovery gates pass.
- [ ] 8.5 `ratatoskr-extractor` — merge the typed publication pull request against the published Contracts release, replace `[PR: pending]` with the merged PR URL and merge SHA, and close only after wire-equivalence and hosted checks pass.
- [ ] 8.6 `ratatoskr-workspace` — pin only the merged child SHAs, regenerate `workspace.lock`, complete the KNO-018 changeset, replace `[PR: pending]` with the merged workspace PR URL and merge SHA, and close only after the pinned exact-SHA profile and hosted fleet checks pass.

## 9. Publication and completion

- [x] 9.1 Push every child task branch without force, verify each remote branch resolves to the intended commit, and record push proof separately from PR/CI/merge proof.
- [ ] 9.2 After all child PRs merge, rebase the workspace task branch on current protected `origin/main`, advance pins to merged SHAs only, rerun strict OpenSpec and the exact-SHA integration profile, commit, push, and open the workspace pin PR without bypassing protection.
- [ ] 9.3 After the workspace PR merges, verify remote `main`, clean baseline submodules, reproducible lock generation, retained durable/cursor rollback evidence, and changeset completeness; only then archive the OpenSpec change and mark KNO-018 complete.
