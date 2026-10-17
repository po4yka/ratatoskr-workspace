# Local Obsidian acceptance

## Scope and open tasks

At workspace `d1963abf88ff2134d141d2210b95a47d814e9aa7`, OBS-024 has only tasks 6.7 and aggregate 1.2 open. Task 6.7 requires real Sync propagation, watcher acknowledgements and local/remote races from OBS-023 spike 3.3. The owner excludes Sync/MFA from this wave, so these two tasks stay open. The separate contracts tasks 3.13–3.16 are complete through OBS-029.

The linked OBS-023 tasks also retain their original acceptance boundary: 3.1/3.3 need the real test account and recording; 5.11 checks real login statuses; 6.5/6.6 replay the recorded session; 6.23–6.26 need real resource, expired-token and directory-mode evidence; 15.1/15.2 need that recorded Sync integration. Task 3.5 retains physical iOS and protected storage. Task 3.4 requires five written support answers. No support message is authorized or sent. Aggregate tasks 1.2 and 1.8 remain open.

Available desktop gaps are the twelve unanswered metadata responses and the existing opt-in Keychain round-trip and delete check. The current production write adapter is also rechecked with the real isolated CLI. These checks do not change product behavior and have no new RED. Any confirmed product defect must receive its own plan and an observed failing regression before implementation. No new TDD exception is requested or used.

## Ownership and safety

Root is the only writer. Worktrees are `.workspaces/obs031/workspace` at `d1963ab` and `.workspaces/obs031/repos/export-agent` at `e4be3b4`. The child worktree was initially created at an incorrect relative location under the baseline; it was moved through Git to the assigned absolute path before any implementation edit. No baseline tracked file changed.

The owner approved the existing Keychain test with fixture values only. It uses an unpredictable UUID service and performs save, load, remove and absent-after-delete assertions. No real account secret is used. Obsidian uses a separate app copy, profile and synthetic vault. The installer digest and app signature are checked before execution. The public CLI reference used for command forms is [Obsidian CLI](https://obsidian.md/help/cli).

## Initial pending state

The local results, cleanup, source revisions and publication checks will be recorded after the commands complete. No pending check is marked successful.

## Headless parser inspection

The published Headless 0.0.14 archive matched the exact SHA-512 integrity in the committed deployment lock. Its CLI parser declares every flag used by both Notes units, accepts `pull-only` and `bidirectional`, and accepts conflict strategy `conflict`. The empty `--configs` argument clears configuration categories: the action removes the stored option and the filter uses an empty set when it is absent. Both current unit lines match these declarations. Evidence is `evidence/obs031-local-acceptance/headless-parser-comparison.json`; the script was inspected without execution. This is static syntax evidence only. It does not close OBS-024 6.7 or any real Sync check.

## Keychain result

The approved existing test `DeviceCredentialStoreTests.testMacOSKeychainRoundTripAndDelete` passed on the pinned Export Agent source: one test, zero failures and no skip. Its real macOS Keychain calls saved and loaded only the fixture credential set under a new UUID service, then removed that record and asserted a later load returned nil. No personal credential was read. The command and result are in `evidence/obs031-local-acceptance/keychain-result.json`; the full log is `/tmp/ratatoskr-obs031-keychain.log`. No production or test source change was required.

## Full Export Agent gates

All six DEVELOPMENT commands passed on the unchanged pinned source: debug build, full tests, release build, release smoke, Distribution checks and SwiftLint. Local builds used four compiler jobs. All 307 tests passed, with zero failures and no skipped test; the real Keychain test ran again with its fresh fixture service. SwiftLint reported 16 baseline warnings and zero serious violations. No source, lint threshold or security policy changed. Per-command receipts are in `evidence/obs031-local-acceptance/export-gates.json`.

The initial desktop harness started its first CLI request before the GUI had its singleton socket. The next attempt checked ownership and socket readiness, but its fixture had disabled the core `outgoing-link` plugin, so `links` was unavailable. Its standalone link step also expected the older SwiftPM object directory; this host uses Xcode product static libraries instead. These are failed harness setup attempts, not product RED evidence. Their logs and raw responses remain retained. The next attempt enables only the required core plugin, keeps Sync/Publish disabled and links the existing production libraries from the actual build product directory. No product implementation was edited.

## Metadata result

All twelve previously unanswered commands returned explicit successful results and matched the recorded engine metadata. Four positive controls also matched: 16 comparisons, zero mismatches, and no blank stdout accepted. Queries left all fixture file bytes unchanged. Both engine and installer report 1.14.4. The successful metadata result is retained even though the independent adapter check failed later in the same attempt. Its receipt is `metadata-result.json`, archived under `cli-attempt-3/` when the next adapter recheck begins.

The source DEVELOPMENT gates remain successful. The adapter retry uses the normal first-party core plugin configuration with Sync and Publish explicitly disabled. It first reads the prepared source file through the real CLI, then submits the move. A diagnostic wrapper returns every production runner answer unchanged and writes only fake-fixture command receipts. This separates setup and indexing failures from an adapter defect.


## Final local acceptance

All 16 metadata comparisons passed again with normal core plugins enabled and Sync/Publish disabled. The source file was read through the real CLI before the queued operation. The production runner then returned status zero and "Moved: Adapter/A.md -> Adapter/New/Nested/A.md". The source disappeared, the destination held the exact expected bytes, and the request body reported "applied" with SHA-256 0350a00dd19b4809e0206f9938312dc8eaae945207ef8dea3e7609491000cee4. Every original fixture file retained its bytes. Only the Notes queue/result HTTP peer was synthetic.

The earlier adapter attempt only established that its source remained. It did not retain the native command answer, so its precise cause was not isolated. The final harness restores the normal core configuration and checks that the prepared file is visible through CLI before the operation. Its diagnostic runner delegates to the production runner and returns its answer unchanged. The final native receipts and filesystem checks passed. No tracked product or test source was edited; no product RED/GREEN correction or new test-order exception was needed.

The signed app reported engine and installer 1.14.4. The original installer SHA-256 and app TeamIdentifier checks passed. The owned app stopped, no process from the private app copy remained, and the installer volume was detached. Final proof and hashes are in evidence/obs031-local-acceptance/final-local-acceptance.json. Command receipts are in cli-acceptance.json, cli-native-receipts/ and adapter.log in the same directory. Failed setup receipts and logs remain retained.

Shared builds later reduced free space to about 270 MiB. After empty lsof checks, the previously approved sccache shards and completed intermediates/release products of this task were cleared. No process or cache server stopped. Needed debug libraries, source and evidence were retained. The cleanup receipt records observed free space, rather than an exclusive attribution of the concurrent filesystem change.

The current 21 child pins and committed lock are unchanged. The deterministic lock, manifest, doctor and status checks passed against those real baseline checkouts. All 48 current OpenSpec items pass strict validation. Workspace publication and exact-commit CI remain open at this point.

## Review before publication

Strict validation passed for all 48 current OpenSpec items and all 19 archived changes. The deterministic lock, manifest, doctor and status checks passed. The final scoped diff passed whitespace checks. The independent autoreview --mode local pass reported no P0 findings and its secret scan was clean. At review time, publication and all eight exact-commit workspace CI checks were pending.

## Verified publication

Commit cb3a4e9e465b64940b01391fe556d6586de4a1b7 was pushed to main. All eight expected and observed checks completed successfully: dependency policy, OpenSpec, Sites integration, snapshot, release-artifact self-test, workflow audit, fleet invariants and Molecule. Exact job links are in the OBS-031 changeset. The primary checkout was fast-forwarded to this commit. Lock generation was repeated twice and matched the committed lock byte for byte; lock check, manifest check, doctor and status all passed. All 21 baseline submodules retained their exact detached pins and were clean. Both protected user files retained their recorded hashes.

OBS-031 is complete at this verified snapshot. No product source or child commit changed, so no new pin can be promoted. OBS-024 6.7 and aggregate 1.2 remain open for real Sync evidence. The status-only follow-up is also subject to full exact-commit CI and final primary verification before handoff. No archived change was modified.
