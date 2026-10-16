# Tasks

## 1. Implementation by repository

The owner authorized direct publication after independent review. Record the pushed main commit
and green CI for each item in SITE-028; use a PR link if a PR is used. Contracts merge first.
No item is complete until its own DEVELOPMENT gate passes and the workspace pins the verified
commit. Pin-only items have no failing test first because they change generated dependency state.

- [ ] 1.1 `ratatoskr-contracts`: first-version types, fixtures, schemas and generated clients. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.
- [ ] 1.2 `ratatoskr-sites`: approval projection, verifier, receipt and activation. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.
- [ ] 1.3 `ratatoskr-platform`: approval digest/event and deploy proxy. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.
- [ ] 1.4 `ratatoskr-site-sdk`: proof download, immutable deploy request and workflow pin. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.
- [ ] 1.5 `ratatoskr-web`: repository binding approval UI. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.
- [ ] 1.6 `ratatoskr-extractor`: contracts revision only; no behaviour change. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.
- [ ] 1.7 `ratatoskr-knowledge`: contracts revision only; no behaviour change. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.
- [ ] 1.8 `ratatoskr-github`: contracts revision only; no behaviour change. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.
- [ ] 1.9 `ratatoskr-vault`: contracts revision only; no behaviour change. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.
- [ ] 1.10 `ratatoskr-x`: contracts revision only; no behaviour change. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.
- [ ] 1.11 `ratatoskr-instagram`: contracts revision only; no behaviour change. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.
- [ ] 1.12 `ratatoskr-threads`: contracts revision only; no behaviour change. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.
- [ ] 1.13 `ratatoskr-chatgpt`: contracts revision only; no behaviour change. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.
- [ ] 1.14 `ratatoskr-claude`: contracts revision only; no behaviour change. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.
- [ ] 1.15 `ratatoskr-telegram`: contracts revision only; no behaviour change. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.
- [ ] 1.16 `ratatoskr-channel-digests`: contracts revision only; no behaviour change. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.
- [ ] 1.17 `ratatoskr-notes`: contracts revision only; no behaviour change. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.
- [ ] 1.18 `ratatoskr-workspace`: provisioning, integration, documentation and final verified pins. Verify the repository gate, independent review where required, green CI and recorded main commit before its final pin.

## 2. Decision and real proof spike

- [x] 2.1 Record the explicit owner approval of runtime `gh` and `oras` in SITE-028 before adding either production dependency. No failing test first: authority record. Verify the exact decision and versions, licenses, update policy and public-only scope in the changeset.
- [x] 2.2 Add and run `integration/tests/site_bundle_real_proof.sh` against a real public artifact: local-manifest verification succeeds with an empty tool configuration and no token, while one changed manifest byte fails cryptographic verification. This is a capability spike, not a product implementation; retain both observed results and stop if credential-free verification fails.
- [x] 2.3 Create isolated writer worktrees and record bases, ownership and dependency order in SITE-028. No failing test first: topology record. Verify clean baseline submodules and `./ws doctor`.

## 3. Contracts and fleet revision

- [x] 3.1 RED: add `crates/sites-contracts/tests/github_binding.rs::repository_identity_is_bound` and `::deploy_request_is_digest_only`. Assert canonical name/numeric ID round-trip and refusal of malformed identities, host/URL/tag overrides and missing required proof. Run against the prior contract with valid signatures/stubs as needed; confirm assertion failures, not compilation failures.
- [x] 3.2 GREEN: add the first-version repository binding and immutable deploy request, schemas, fixtures and generated types. Verify 3.1, the contracts DEVELOPMENT gate and public API baselines.
- [ ] 3.3 Update the contracts commit in every consumer and the workspace pin guard source. No failing test first: generated lock/pin state. Verify each pin-only repository's gate and CI, SDK/Web generated drift, and `contracts_pin.rs`; record every SHA in SITE-028.
- [x] 3.4 Document the new first-version fields and producer/consumer rules beside the contract. No failing test first: documentation. Verify schemas, fixtures and the described event/body agree.

## 4. Sites enforcement

- [ ] 4.1 RED: add `crates/deploys/tests/provenance.rs::only_the_approved_build_can_be_stored`, table-driven for foreign repository/name reuse, signature, issuer, digest, commit, workflow path/revision and self-hosted runner. Valid proof stores; each invalid case leaves no deploy. Observe intended failures before verifier implementation.
- [ ] 4.2 GREEN: implement bounded proof verification and exact manifest/layer receipt. Verify 4.1 and existing receipt/path/file tests; use real signed evidence for the positive acceptance, with fakes only for fault injection.
- [x] 4.3 RED: add `services/sites/tests/deploy_provenance.rs::raw_tar_and_owner_cannot_bypass_provenance`. Assert raw tar and unsigned owner requests refuse before storage, and unauthorized sessions still refuse. Observe the missing refusal on the prior server.
- [ ] 4.4 GREEN: require the new deploy request for all caller kinds. Verify 4.3 and the existing deploy authority tests.
- [ ] 4.5 RED: add `crates/deploys/tests/provenance_races.rs::withdrawal_during_verify_stores_nothing`, `::rebind_refuses_old_activation`, `::same_commit_other_digest_conflicts` and `::concurrent_receipts_cannot_replace_proof`. Block verification to change approval deterministically; assert no visible directory or changed links. Confirm intended failures.
- [ ] 4.6 GREEN: persist verified provenance and serialize the final authority/idempotency boundary with activation. Verify 4.5, same-identity retry and verified rollback without network. Edit current schema in place; create fresh test databases.
- [ ] 4.7 RED: add `services/sites/tests/provenance_limits.rs::timeout_kills_and_reaps_children`, `::cancel_cleans_staging`, `::oversized_output_is_refused`, `::foreign_url_never_connects` and `::capacity_is_bounded`. Assert process/staging cleanup and no stored deploy on each failure. Confirm intended failures.
- [ ] 4.8 GREEN: apply D5 bounds, fixed tool/config paths, no shell or inherited credentials, checked output and stable errors. Verify 4.7 and shutdown behavior; run every Sites DEVELOPMENT command, independent review and CI.
- [ ] 4.9 Document proof storage, errors and operational bounds in the Sites docs. No failing test first: documentation. Verify the documented public behavior against the tests above.

## 5. Platform approval and proxy

- [x] 5.1 RED: add `crates/public-api/tests/site_approvals.rs::approval_event_covers_the_repository` and `::new_approval_requires_repository_binding`, with the existing `::stale_digest_is_refused` case. Assert the digest/event carries the canonical identity and a changed binding cannot use the old approval. Confirm intended failures.
- [x] 5.2 GREEN: require the binding for new approvals and emit the expanded approval event; update the existing first-version schema in place. Verify 5.1 and approval withdrawal tests.
- [x] 5.3 RED: add `crates/public-api/tests/sites_deploy_routes.rs::digest_request_keeps_deploy_authority` and `::provenance_body_is_bounded_before_proxying`. Assert exact request forwarding and existing per-site grants, body limits and content type. Confirm the old raw-body proxy fails those assertions.
- [ ] 5.4 GREEN: forward the bounded JSON/proof without weakening identity or route guards. Verify 5.3, every Platform DEVELOPMENT command, independent review and CI; document the route in the same repository.

## 6. SDK and Web

- [x] 6.1 RED: add `tests/deploy-provenance.test.ts` cases "sends the immutable digest and proof", "rejects a missing proof before login" and "cannot override the approved origin". Assert the exact server body and zero requests for invalid input. Confirm intended failures.
- [ ] 6.2 GREEN: send the new request, retain client checks and pin the trusted workflow revision; document the command. Verify 6.1, SDK DEVELOPMENT gate, review and CI.
- [x] 6.3 RED: add `src/features/sites/repository-approval.test.tsx` cases "shows repository name and immutable id" and "requires approval again when binding changes". Assert the owner-visible identity and disabled old approval. Confirm intended failures.
- [ ] 6.4 GREEN: show and approve the binding, with generated types from the same contracts commit. Verify 6.3, Web DEVELOPMENT gate, rendered desktop/mobile states, keyboard/error behavior, review and CI.

## 7. Workspace integration and provisioning

- [x] 7.1 RED: add `harness/crates/workspace-core/tests/sites_verifier_tools.rs::runtime_tools_are_pinned_and_confined` and the Molecule `sites_verifier` case. Assert pinned root-owned ARM64-compatible tools, no credential inheritance and successful real proof verification within 512 MiB. Confirm missing-tool or policy assertions fail on the previous disposable host.
- [x] 7.2 GREEN: provision the approved tool versions and server-owned trust root on the disposable host. Verify 7.1, zero-change idempotence and full Molecule. No operation on the frozen production host.
- [ ] 7.3 RED: extend `integration/tests/site_owner_editing.py` with `verified_bundle_repository_boundary`: send foreign, unsigned, changed-digest and stale-approval requests, then valid real signed evidence. Assert refusals leave no deploy and only the valid request activates. Confirm intended failures before integration adapters change.
- [ ] 7.4 GREEN: use the coordinated pins and real proof fixture; verify 7.3, existing privacy/write scenarios, withdrawal, rebinding, idempotency, cancellation and offline verified rollback. A synthetic signature is not acceptance evidence.
- [ ] 7.5 Reconcile the active `site-bundles` and `site-manifest` deltas with the enforced policy, and update runbooks and SITE-028. No failing test first: specification and documentation. Verify strict OpenSpec validation and no contradictory raw-tar acceptance requirement.
- [ ] 7.6 Advance pins only after every child CI is green. No failing test first: generated snapshot. Verify lock determinism, doctor, full harness gates, integration, Molecule, clean baselines and final workspace CI; record rollout, rollback and exact commits in SITE-028.

## Workflow follow-up

- Archive only after the old active Sites deltas are reconciled and every tracked item is complete.
- Keep runtime acceptance, CI and any later production deployment as separate evidence levels.

## Apply evidence, 2026-10-16

- The owner approved `gh` 2.102.0 and `oras` 1.3.0 for public GHCR after the plan was presented.
- `integration/tests/site_bundle_real_proof.sh` passed with an environment containing only PATH
  and private tool/config/cache/state paths, no token. It fetched the exact public Sites release
  OCI manifest at `sha256:48e1d62ba1add116c0ebf38b86a32569cda6490fcb3ae0c7b513a7521f2753ba`,
  checked its raw digest and proof-layer digest, then verified its real signature, source commit
  `3860ddc`, trusted workflow at `75b3ed8` and immutable certificate repository ID `1420131804`.
  The original exited zero; adding one space to its raw manifest made verification exit one.
- This is the service-release capability spike. It does not close the site-bundle policy,
  ARM64 ABI, production memory bound, runtime installation or server integration tasks.
  Local evidence is `evidence/site028-script/summary.json` and adjacent complete command results.

- Contracts `66bdb0c0545363f06137f13687084c21db9b27c5` is published after observed RED/GREEN
  for the manifest/event binding and immutable request. Before publication, the request was
  refined to `artifact_sha256` with the existing `DigestHex` representation; the renamed-field
  test failed before that refinement and passed after it. The registry has 83 roots, with exact
  artifact-count pins and the new canonical fixture renderer updated.
- Contracts local acceptance: 432 tests pass, zero ignored; fetch, format, clippy, source-size,
  canonical generation/fixtures, deny, strict TypeScript 6.0.3, all public API baselines (pinned
  cargo-public-api 0.52.0 and nightly-2026-06-12), OpenSpec 1.10.0 (22 active and 18 archived)
  and independent review pass. API generation used an isolated native tool; the pre-existing x86_64
  host binary was preserved. Child CI and the coordinated consumer revision are separate gates.

- Sites pin-only commit `a22a2c3f363b6d2a055cc5b50ef111ad0e027a0c` passed its full local gate,
  source-size/OpenSpec checks, independent review and all seven CI checks. No server enforcement
  was included. Channel Digests `ab63852` passed its complete local gate, review and five CI checks.
  ChatGPT `7dc1ef8` passed its complete local gate and review; its CI is still pending.
- Sites new route regression observed `200` for raw tar instead of required `415`. The approval
  projection test observed an absent repository binding, then passed after the current-schema
  column and event projection were added. These changes are local and incomplete.
- The verified-output policy parser observed a failure on a foreign certificate repository before
  its implementation, then passed the metadata mutation table. This parser test uses synthetic
  post-verification output and is not cryptographic or end-to-end acceptance.
- Platform new approval tests observed both absent binding in response/event and acceptance of an
  unbound manifest. The approval implementation is local and its GREEN check is pending.
- One Claude gate was interrupted when cleanup of the shared Cargo target removed a same-named
  test executable. No source changed. The complete gate is being repeated, and cleanup now takes
  the machine build slot. Do not count the interrupted run as a pass.

- The owner approved the additional safe Unix signal wrapper `nix` 0.30.1, `signal` only.
- Sites manifest lookup observed an absent binding before its implementation; both public and
  internal views now preserve it, and both approval projection/lookup tests pass. The low-level
  process component observed overflow accepted before its bound, then all six unit checks passed:
  policy metadata, output overflow, file streaming, constructed environment, timeout and cancellation
  group cleanup. The process/parser modules are not yet wired into the server; this is not acceptance.
- Platform's six approval tests pass. Two proxy regressions observed raw tar forwarded as 200
  instead of refused as 400, and an over-limit JSON body forwarded as 200 instead of 413. The
  protocol guard and 1 MiB route cap are local; full Platform acceptance remains pending.
- The repeated complete Claude gate passed, followed by independent review; `bc07c02` is pushed
  and awaits CI. Extractor's full gate then passed after removing the host-only `BROWSER_`
  prefix from the test child environment. Its first attempt correctly refused that unrelated
  environment key; no configuration validation was relaxed. Extractor review is pending.
- SDK pin expansion matches 23 canonical contract files at 66bdb0c and the Sites API at a22a2c3.
  All seven documented checks and production audit pass. SDK review is pending; no deploy client
  protocol change has shipped.

- Claude `bc07c02` now has five CI checks green. Extractor and SDK independent reviews are clean.
  Platform proxy suite passes all ten cases after its body/header fixtures were moved to JSON.
  OpenAPI regeneration succeeded. Full Platform gate and publication remain pending.

- Apply continuation: the final locked approval recheck was drafted before the planned 4.5 race
  RED test. This violates the required test-first order. The draft is not published, 4.5 stays
  open, and the owner was asked for a separate exception. The historical OBS-024/SITE-026
  exception does not cover this violation. Do not report a reconstructed RED as test-first proof.
- Platform completed its full DEVELOPMENT gate, deny, OpenSpec and independent review. Its
  behavior change is not published while expanded consumers and Sites enforcement are pending.
- Knowledge `0e6e447` and Notes `5076346` passed full local gates and independent review and were
  pushed. Their CI was still running at this checkpoint. Telegram completed its full local gate
  and review. Threads first failed because the local gate runner omitted
  `THREADS_ARCHIVE_TEST_NATS_URL`; its tests used the default port. The runner now sets the
  owned broker URL. No product code or validation rule was changed for that failure.
- Web repository display and missing-binding refusal each failed before implementation; the
  focused registry suite now passes five cases. Full tests found only two expected generated
  API drift failures while the Platform document and its commit lock await publication.
- Sites raw-tar/owner regression now passes. Readiness returned 200 without a verifier before
  the change and now returns 503. The preflight path test failed on a relative executable before
  implementation and now passes. Stale verification cleanup observed zero removals instead of one;
  its implementation is pending. These checks do not prove a real signed site bundle can deploy.

- All twelve pin-only Rust consumers have passed complete local gates, independent review and
  CI. SITE-028 records each full SHA. SDK `9661c6b` has five CI checks green after the fixture
  permission comments were added. The immutable real proof still names source `009afe3` and
  reusable workflow `89331e6`. The SDK client change has not shipped.
- Real proof exposed an invalid ORAS flag on `manifest fetch`; both the regression assertion and
  the real-tool lane failed before the flag was removed. Ten component tests now pass, with no
  ignored tests. The real cases use actual CLI verification; synthetic output remains limited to
  isolated policy and fault tests. Default and opt-in all-feature Clippy pass.
- The runtime role passed on the disposable ARM64 container, and its replay changed zero tasks.
  The public archive fetch and offline signature/refusal probe ran as UID 65534, with the container
  network disconnected for signature verification. Its enforced bound was 536870912 bytes and
  memory peak was 171868160 bytes. Both tool ELF files have AArch64 machine type, 65536-byte LOAD
  alignment and no dynamic interpreter. This is not a native 16 KiB-kernel run.
- Workspace Clippy and all 131 harness tests pass, with zero ignored; doctor is healthy and all
  45 active specs/changes validate. The new runtime role and Molecule tasks pass ansible-lint.
  Full Molecule is running. Its first attempt stopped before host creation because the local PATH
  lacked the configured Docker credential helper; the retry uses an empty Docker auth configuration
  and an explicit local socket. No personal registry credential is read for the retry.

- Correction to the pending test-order decision: the server job queue and cancellation cleanup
  were also drafted before the server-level 4.7 RED cases. The owner question now covers 4.5
  and 4.7 and replaces the narrower question. Existing component checks are not evidence that
  these server-level tests ran first. Keep both pairs open and the server draft unpublished
  until the owner decides and the required behavior checks pass.

- Full Molecule now passed all seven scenario actions, including zero-change idempotence and
  every verify case. The new case fetched the genuine public artifact in a 512 MiB unit, then
  verified its local proof with network address families restricted and IP traffic denied.
  The separate no-network Docker probe also passed with swap explicitly disabled; its final
  cumulative memory peak was 199110656 bytes. No production host was contacted.
- Platform is committed locally at `16b502ed502dfcdcfe6ce8574d794f4a303d4dce` after the full gate
  and review, but remains unpublished until Sites enforcement is ready. The Web draft now uses
  its exact OpenAPI bytes and commit lock; API drift and typecheck pass. Web lint still requires
  a small component extraction; browser acceptance is in progress.
- The complete Sites test run observed 195 passes, seven failures and zero ignored. The failures
  are the legacy raw-tar deploy route and unsealed activation happy paths. They must be replaced
  with verified-request coverage before the server gate can close. This draft is not published.

- The tooling RED evidence for 7.1 is the new harness assertion (`Sites verifier policy is
  missing`) and the failed fixed-path executable checks on the prior disposable ARM64 image.
  These ran before the runtime role was written. The new Molecule case subsequently passed
  on the provisioned target. The root worktree, baseline checks and 7.2 are now validated.
- Web now passes all 338 unit tests after its generated API was aligned to local Platform
  commit `16b502e`. Browser approval/error and unbound cases passed on desktop and mobile;
  visual inspection then found inner-card overflow at 320 px. A new cell-bound assertion
  failed on mobile before the grid change. Layout GREEN is pending.

- Web layout GREEN now passed both real-browser cases after a `minmax(0, 1fr)` value column
  and wrapping were applied. The checks cover each cell against its card, page width, keyboard
  approval, stale-digest feedback, missing binding and Axe. All 338 unit tests passed before
  this layout-only fix; final full Web checks and publication remain pending.
