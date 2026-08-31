## 1. Platform operation-bound transfer

- [x] 1.1 RED — in `ratatoskr-platform/crates/public-api/tests/ai_archives.rs`, add
  `operation_bound_upload_resumes_missing_chunks_without_second_operation`; interrupt after
  acknowledged chunks, recreate API state, query status, and assert only missing chunks complete the
  original operation. Run the focused test and confirm it fails because the operation-scoped
  open/chunk/status/finalize routes do not exist.
- [x] 1.2 GREEN — edit the current Platform schema and public API/OpenAPI in place to persist a
  bounded operation-owned staging session, implement open/chunk/status/finalize using the existing
  blob-transfer types, and make 1.1 pass without a second API version or migration.
- [x] 1.3 RED — in `ratatoskr-platform/crates/public-api/tests/ai_archives.rs`, add
  `operation_transfer_is_idempotent_and_owner_device_provider_scoped`; assert identical prepare and
  chunk replay return the original state, divergent chunks conflict, valid foreign/wrong-device or
  wrong-provider requests observe bounded not-found, and a revoked credential is rejected by the
  common authentication boundary without changing stored chunks. Run it and confirm at least the
  current whole-file path fails the assertions.
- [x] 1.4 GREEN — bind preparation, transfer session and chunk access to owner, active export-agent
  device, provider and operation; add bounded expiry/replacement inside the same operation and make
  1.3 pass.
- [x] 1.5 RED — add a Platform archive-finalization test that assembles and hashes staged chunks,
  asserts digest mismatch never calls an upstream, and asserts verified bytes reach only the bound
  provider with injected operation headers. Run it and confirm current finalization behavior is
  absent.
- [x] 1.6 GREEN — implement crash-safe ordered assembly, streaming digest verification, fixed-route
  provider delivery, operation-safe cleanup and private failure mapping; make 1.5 pass.

## 2. Platform deployment, secured bus and readiness

- [x] 2.1 RED — extend `ratatoskr-platform/crates/core/tests/config_validation.rs` and the deploy
  example contract test to require ChatGPT `127.0.0.1:8096` and Claude `127.0.0.1:8097` receipt
  routes and to reject collisions or missing routes. Run the focused tests and confirm
  `deploy/systemd/edge.conf.example` fails them.
- [x] 2.2 GREEN — add the two fixed gateway routes, current-schema staging paths and required service
  unit/example configuration; make 2.1 pass and regenerate checked-in Platform API/config artifacts.
- [x] 2.3 RED — add a secured-NATS integration test beside Platform's deployment validation that
  proves distinct ChatGPT and Claude credentials can publish only to their provider-scoped
  `evt.ai-archive.<provider>.operation.reported.v1` ingress subject, cannot impersonate each other or
  subscribe to `evt.>`, and anonymous publication is refused. The Platform projection must also
  reject a producer/provider mismatch after broker acceptance. Run it and confirm the current NATS
  configuration and projection fail.
- [x] 2.4 GREEN — define the least-privilege provider users/permissions and credential-file settings,
  remove anonymous producer fallback, and make 2.3 pass without committing credential material.
- [x] 2.5 RED — add Platform capability/readiness tests that stop one provider receiver and one
  report-consumer dependency independently, asserting only the affected archive route disappears and
  no route remains ready without its report path. Run them and confirm current readiness is too weak.
- [x] 2.6 GREEN — include staging store, provider receipt reachability and report consumption in the
  existing readiness/capability projection; make 2.5 pass.

## 3. ChatGPT archive import runtime

- [x] 3.1 RED — in `ratatoskr-chatgpt/crates/chatgpt-archive/tests/receipt_receiver.rs`, add
  `raw_receipt_is_nonterminal_until_restart_safe_import_completes`; crash after raw persistence,
  restart the service, and assert no terminal report precedes parser/import while the eventual report
  carries actual counts and completeness. Run it and confirm `raw_stored_partial` fails the test.
- [x] 3.2 GREEN — make receipt persistence enqueue durable import work, run the existing parser and
  import pipeline from service startup, emit progress for raw storage and one terminal summary only
  after import, and make 3.1 pass.
- [x] 3.3 RED — add `duplicate_digest_reports_terminal_result_for_each_bound_operation` to the same
  suite; submit identical bytes under two Platform operation ids and assert one raw archive/import
  plus a truthful terminal report for each operation. Run it and confirm the duplicate shortcut
  strands the second operation.
- [x] 3.4 GREEN — correlate duplicate receipts with the existing archive/import result or durable
  pending work and emit idempotent operation-specific reports; make 3.3 pass.
- [x] 3.5 RED — extend ChatGPT outbox and admin/readiness tests so authenticated NATS publication is
  required, a permission failure leaves the row pending, and readiness fails until publisher access
  recovers. Run them and confirm anonymous `async_nats::connect` and current readiness fail.
- [x] 3.6 GREEN — use configured service credentials, retain exact-once outbox identity across retry,
  expose publisher/import-worker health, and make 3.5 pass.

## 4. Claude archive import runtime

- [x] 4.1 RED — in `ratatoskr-claude/crates/claude-archive/tests/receipt.rs` and its service boot
  tests, add `raw_receipt_is_nonterminal_until_restart_safe_import_completes`; crash after raw
  persistence, restart, and assert parser/import precedes the terminal actual-count summary. Run it
  and confirm the current raw-stored partial report fails.
- [x] 4.2 GREEN — durably enqueue and run Claude import work from service startup, publish only
  progress at raw storage and one truthful terminal report after import, and make 4.1 pass.
- [x] 4.3 RED — add `duplicate_digest_reports_terminal_result_for_each_bound_operation`; assert one
  raw archive/import and a terminal result for every distinct correlated operation. Run it and
  confirm the existing duplicate path fails to report the later operation.
- [x] 4.4 GREEN — associate duplicate receipts with existing or pending import truth and emit
  idempotent operation-specific reports; make 4.3 pass.
- [x] 4.5 RED — extend Claude outbox/admin tests to require its configured NATS identity, preserve a
  pending report on auth/permission failure, and fail readiness until reporter/import-worker health
  recovers. Run them and confirm the anonymous publisher/current readiness fail.
- [x] 4.6 GREEN — wire credentialed least-privilege publication and runtime health into the service;
  make 4.5 pass.

## 5. Export Agent durable routing and transfer

- [x] 5.1 RED — in `ratatoskr-export-agent/Tests/AgentCoreTests`, add
  `MixedProviderJournalRoutingTests.swift` proving ChatGPT and Claude entries persist distinct
  provider/classification/policy state and route independently after journal reopen. Run it and
  confirm `JournalEntry` and the queue-wide provider cannot satisfy the assertions.
- [x] 5.2 GREEN — change the current version-1 journal model in place, make provider a per-entry
  invariant, preserve processing and operation state atomically, remove queue-wide routing, and make
  5.1 pass while leaving managed archive files untouched on invalid old development state.
- [x] 5.3 RED — add
  `PlatformResumableArchiveHTTPTransportTests.interruption_relaunch_resumes_same_operation` that
  prepares once, acknowledges a subset of chunks, recreates journal/transport, queries status, sends
  only missing chunks and finalizes. Run it and confirm the current single PUT/permanent-ineligible
  path fails.
- [x] 5.4 GREEN — implement the operation-bound open/chunk/status/finalize HTTP transport, persist its
  checkpoint before presentation, recover the same bound operation after failure, and make 5.3 pass.
- [x] 5.5 RED — add transfer authorization tests proving every chunk and poll obtains a current
  credential from one session coordinator, refresh rotation changes later requests, and revocation
  stops work without deleting queue/archive state. Run them and confirm the fixed-token transports
  fail.
- [x] 5.6 GREEN — make Platform transports request-scoped authenticated clients over the shared
  session coordinator, preserve strict HTTPS/no-redirect behavior, and make 5.5 pass.

## 6. Export Agent onboarding and application runtime

- [x] 6.1 RED — add
  `Tests/RatatoskrExportAgentTests/PairingOnboardingTests.swift::relaunch_restores_non_secret_identity_and_keychain_session`;
  drive endpoint entry, pairing, relaunch, refresh, revoke and re-pair, asserting no credential enters
  configuration or visible state. Run it and confirm the current folder-only settings cannot pass.
- [x] 6.2 GREEN — persist HTTPS origin and non-secret paired identity, add onboarding/pair/re-pair/
  revoke and launch-at-login settings, use Keychain as the sole secret store, and make 6.1 pass.
- [x] 6.3 RED — add
  `Tests/RatatoskrExportAgentTests/RuntimeCompositionTests.swift::normal_launch_starts_one_shared_operational_runtime`;
  inject runtime probes and assert app launch starts watcher, candidate processor, upload scheduler,
  operation poller and reminders once, while menu/diagnostics observe their state. Run it and confirm
  the static bootstrap fails.
- [x] 6.4 GREEN — add one actor-owned runtime/coordinator, compose it from the app delegate, share its
  projections/actions with all windows and menu bindings, and make 6.3 pass.
- [x] 6.5 RED — in `RuntimeCompositionTests.swift`, add
  `shutdown_sleep_wake_and_network_recovery_reconcile_without_duplicate_work`; assert cancellation
  checkpoints on termination, one bounded reconciliation on wake/reachability, and no duplicate
  in-flight entry. Run it and confirm no lifecycle orchestration exists.
- [x] 6.6 GREEN — implement cancellable durable queue/poll/reminder loops, startup/wake/network
  reconciliation, graceful stop and user-controlled `SMAppService.mainApp`; make 6.5 pass without a
  helper or LaunchAgent.
- [x] 6.7 RED — add an Agent runtime vertical test that places stable synthetic ChatGPT and Claude
  ZIPs in an approved folder and asserts classify, immutable preserve, queue, resumable upload,
  polling, terminal menu/history, notification privacy, duplicate suppression and retry/pause/cancel.
  Run it and confirm the disconnected primitives cannot complete the flow.
- [x] 6.8 GREEN — connect stable-candidate processing, immutable store, journal, per-entry queue,
  polling, notifications, reminders, operations UI and truthful diagnostics; make 6.7 pass.

## 7. Workspace exact-revision product profile

- [x] 7.1 RED — add `integration/tests/export_agent_product_profile_test.sh` asserting the `XPA-020`
  profile requires full clean `origin/main` revisions for unchanged Contracts, Platform, ChatGPT,
  Claude and Export Agent; uses isolated ports, database, secured NATS and Keychain/support paths;
  exercises two providers plus interruption/restart/duplicate/privacy; and tears down only its exact
  namespace. Run it and confirm the profile/runner are absent.
- [x] 7.2 GREEN — add the task-namespaced Compose assets, synthetic ZIPs, secured-bus configuration,
  macOS system-test host and `integration/run-export-agent-product.sh`; make 7.1 pass. Configuration
  begins without a runtime RED test only where it is declarative, and is covered by the static test.
- [ ] 7.3 RED — add the profile's system assertion that raw receipt is non-terminal, a forced chunk
  interruption plus Agent restart preserves one operation, both real importers produce actual
  terminal summaries, duplicate bytes create no duplicate import, and evidence/logs contain no
  path, content, digest, token or credential. Run against task worktrees and confirm at least one
  pre-fix boundary fails for the diagnosed reason.
- [ ] 7.4 GREEN — finish only the cross-repository composition needed for 7.3, run it through
  `build-gate -- integration/run-export-agent-product.sh`, review the bounded evidence, and record
  exact revisions and teardown inventory in `integration/evidence/XPA-020.md` and the changeset.

## 8. Release publication and clean-machine acceptance

- [x] 8.1 RED — extend `ratatoskr-export-agent/Tests/Distribution/run.sh` with a workflow contract
  test requiring an explicit-version GitHub Release, attached final ZIP and SHA-256, exact integrated
  source revision, fail-closed tag/asset handling, and no publication before trust checks. Run it and
  confirm the current 14-day `upload-artifact` workflow fails.
- [x] 8.2 GREEN — update the owner-authorized distribution workflow to publish the accepted immutable
  release with least required permission only after signing, notarization, stapling, signature and
  Gatekeeper checks; make 8.1 pass without exposing secrets.
- [x] 8.3 Add a clean-machine acceptance script/checklist for Gatekeeper, first launch, explicit
  folder authorization, pairing, relaunch/Keychain restoration, interrupted resume, terminal status,
  manual-update navigation and rollback. A failing automated test cannot precede this task because
  it requires an owner-authorized notarized artifact and a separate compatible Mac; validate the
  script's static safety contract locally.
- [ ] 8.4 If owner Apple credentials and a clean compatible Mac are available, publish the explicit
  release and record workflow URL, source SHA, notary submission, ZIP digest, release URL and
  clean-machine results. Otherwise record this phase as externally blocked and publish nothing; do
  not mark it complete without observed evidence.

## 9. Implementation by repository

- [ ] 9.1 `ratatoskr-platform` — before code, create and validate its repository-local OpenSpec
  change; complete tasks 1–2, run the full documented machine-gated gate and strict/archived OpenSpec
  validation, merge the reviewed PR, and record its PR link and merge SHA here.
- [ ] 9.2 `ratatoskr-chatgpt` — before code, create and validate its repository-local OpenSpec change;
  complete task 3, run its full documented gate and strict/archived OpenSpec validation, merge the
  reviewed PR after Platform fixtures are fixed, and record its PR link and merge SHA here.
- [ ] 9.3 `ratatoskr-claude` — before code, create and validate its repository-local OpenSpec change;
  complete task 4, run its full documented gate and strict/archived OpenSpec validation, merge the
  reviewed PR after Platform fixtures are fixed, and record its PR link and merge SHA here.
- [ ] 9.4 `ratatoskr-export-agent` — before code, create and validate its repository-local OpenSpec
  change; complete tasks 5–6 and 8.1–8.3, run the full machine-gated Swift/distribution and
  strict/archived OpenSpec gates, merge the reviewed PR after compatible server commits exist, and
  record its PR link and merge SHA here.
- [ ] 9.5 `ratatoskr-workspace` — complete task 7 and the XPA-020 changeset, validate all exact clean
  published inputs, merge the reviewed workspace PR last, and record its PR link, merge SHA and
  verified compatible snapshot here.

## 10. Final verification and publication boundary

- [ ] 10.1 Re-run every affected repository's documented full gate at its recorded merge SHA, all
  strict and archived OpenSpec validation, Platform config/OpenAPI drift, Export Agent distribution
  policy tests, workspace static profile tests and the machine-gated composed profile; record exact
  commands and outcomes without treating fixtures as live deployment or Apple evidence.
- [ ] 10.2 Inspect final diffs and generated artifacts for provider credentials, Apple material,
  personal exports, paths/content/full digests in logs, broad macOS entitlements, anonymous NATS,
  stale port `9084`, frozen access tokens, raw-receipt terminal reports, duplicate-operation stalls,
  and unrelated changes; all searches and reviews must be clean or explicitly resolved.
- [ ] 10.3 Advance the compatible workspace snapshot only after 9.1–9.5 and 10.1–10.2 are complete;
  then, and only if 8.4 has real owner-authorized evidence, mark the product release accepted. If
  Apple or clean-machine access is missing, leave release acceptance open while reporting the exact
  external blocker.
