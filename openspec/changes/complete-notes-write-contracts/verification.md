# OBS-029 verification record

## Planning and isolation

OpenSpec 1.10.0 created the complete proposal, spec, design and tasks before source edits. Strict validation passed. The nearest local root is the isolated workspace; primary store source was not edited. Fifteen Rust child worktrees have one writer and recorded full bases. Child AGENTS.md bytes match the prior wave; current Contracts, Notes and Platform instructions were inspected again.

## Observed RED, before the corresponding implementation

- OBS-024 3.13 suffix: `cargo test --locked -p ratatoskr-notes-contracts --test write_request segment_that_ends_in_a_dot_or_a_space_is_refused -- --exact`, under build-gate. One test failed: `path "Notes./x.md"`, actual `(serde, schema)` acceptance `(true, true)`, expected `(false, false)`. Log `/tmp/ratatoskr-obs029-path-suffix-red.log`.
- OBS-024 3.13 colon: the same already-built `write_request-9050f7fc5e76c2ea` test executable, `--exact colon_is_refused`. One test failed: `path "A:B.md"`, actual `(true, true)`, expected `(false, false)`. This short direct test used the executable from the suffix build; no compilation or new dependency ran outside the build gate. Log `/tmp/ratatoskr-obs029-path-colon-direct-red.log`. The redundant queued cargo invocation was cancelled before it started.

- Platform 4.1: `cargo test --locked -p ratatoskr-platform-operations --test notes_conflicts a_group_conflict_with_stale_paths_is_applied -- --exact`, on contracts 66bdb0c. One test failed: actual `Some(Rejected)`, expected `Some(Applied)`. The disposable PostgreSQL database was ready and the event reached the real inbox/projection. Log `/tmp/ratatoskr-obs029-platform-event-red.log`; owned PostgreSQL and NATS fixtures were removed.
- Notes 4.3: `cargo test --locked -p ratatoskr-notes --test link_rewrite_atomic a_group_base_mismatch_names_the_local_hash_of_each_file -- --exact`, on contracts 66bdb0c. One test failed at the new event-list assertion. The existing device result and database conflict succeeded before that assertion. Log `/tmp/ratatoskr-obs029-notes-event-red.log`.

- OBS-024 3.15: the new `conflict::raised_may_name_every_stale_path` ran before adding the field. One test failed: serde reported unknown field `stale_paths`, actual `(serde, schema)` acceptance `(false, false)`, expected `(true, true)`. Log `/tmp/ratatoskr-obs029-conflict-red.log`.

- Platform path refusal: `cargo test --locked -p ratatoskr-platform-public-api --test notes_writes invalid_body_is_refused -- --exact`, before the new contract pin. One test failed because invalid body 5 returned HTTP 202 with status accepted, while the test required HTTP 400. The test compiled and reached the real HTTP boundary. Log `/tmp/ratatoskr-obs029-platform-path-red.log`.

## Observed GREEN

- OBS-024 3.14: `cargo contracts generate` then `cargo test --locked -p ratatoskr-notes-contracts --test write_request`, in one build-gate slot. All 10 tests passed, including unsafe source and target paths and safe boundary names. Log `/tmp/ratatoskr-obs029-path-generated-green.log`.

- OBS-024 3.16: after the field and its wire mirror were added, generation first reported its existing unsupported nullable-array form. The field now emits an equivalent supported `anyOf`; the TypeScript generator's refusal policy is unchanged. Generation and all four conflict tests passed, including new list round-trip, malformed path refusal and the existing event forms. Log `/tmp/ratatoskr-obs029-conflict-shaped-green.log`.

## Tool isolation

The global `cargo-public-api` executable is x86_64 and the global `nightly` points to 2026-05-16. Neither was changed. API checks use the existing native cargo-public-api 0.52.0 under `/tmp/ratatoskr-site028-tools` and a task-local Rustup home with nightly-2026-06-12, which reports rustc 1.98.0-nightly (b30f3df3b 2026-06-11). A task-local `nightly` alias permits the existing generator to record the exact pinned compiler. The TypeScript check uses the existing pinned 6.0.3 compiler in the prior SDK task worktree.

## Contracts local gate

The exact DEVELOPMENT gate passed after the test helper's JSON indexing was replaced with checked JSON pointers. No lint was suppressed. The first Clippy diagnostic is retained in `/tmp/ratatoskr-obs029-contract-clippy-attempt1.log`.

- Fetch, fmt, Clippy all targets, source size, `cargo contracts check`, `cargo test --workspace --locked`, cargo-deny and strict TypeScript compilation passed. The observed total was 435 passed, zero failed and zero ignored. Logs and exit codes are in `/tmp/ratatoskr-obs029-contract-gates.json`; the initial fetch result remains in its attempt-1 record.
- API check before blessing named exactly one added field, `ConflictRaised::stale_paths`. After `api-write`, only `compat/api/ratatoskr-notes-contracts.txt` changed, by that one line. The exact pinned-toolchain `api-check` then passed for every crate.
- A generation rerun left all 1178 tracked and non-ignored source/artifact files byte-identical. The check ran before the writer, so the first check did not inspect repaired output.
- JSON Schema compatibility reports the requested write-path pattern restriction as breaking (`pattern.changed`, exit 1). This is the explicitly requested first-major development correction, not an unexpected gate failure. The conflict report classifies all three optional-field additions as compatible (exit 0). The observed old strict Platform rejection still requires consumer-first rollout; the structural classifier alone does not prove forward reader compatibility.

## Contracts publication

Independent autoreview completed with no accepted/actionable P0 finding. The exact reviewed 19 files were staged, the staged diff and the repository pre-commit hook were checked, and the commit metadata was checked against the naming rule. Commit `1756034314a15d3a83d5c7d15b172da502990e98` was pushed directly to main under the owner-selected workflow. GitHub reported the eight checks as expected at the push; no ruleset was changed. All eight subsequently passed, as recorded in `/tmp/ratatoskr-obs029-ci-contracts.json`. The workspace baseline pins were not advanced while checks were pending.

Platform also has a direct HTTP RED on the old pin: `notes_writes::invalid_body_is_refused` received `202 accepted` for `Notes./x.md`, expected `400`. Log `/tmp/ratatoskr-obs029-platform-path-red.log`. The new contracts source has now been resolved in thirteen consumer worktrees; parsed lockfile comparison confirms that no package identity, registry version, checksum or dependency edge changed beyond the intended contracts git source. This includes Extractor's fuzz manifest and lock.

## Platform acceptance

The first new-pin run applied the expanded event and recorded its correct result, but the test then expected `Some(Duplicate)` for the same message ID. The inbox contract suppresses that ID with `None`; a new message ID with the same conflict produces `Some(Duplicate)`. The test now checks both forms and one stored result. No production deduplication code changed.

All three conflict-consumer tests and all six write-route tests passed. The new path cases create no operation, no command and no Notes request. The whole documented gate, source-size check, cargo-deny, 24 current and 22 archived OpenSpec checks, the hook and P0 autoreview passed. The generated public `VaultWritePath` component exactly matches the canonical contract node. Commit `83dcba6498ebaf2a3b7a97739d64b47ca47c25a8` was pushed; all seven observed CI checks, including the ARM64 artifact and artifact self-test, passed. Logs: `/tmp/ratatoskr-obs029-platform-gate.json` and `/tmp/ratatoskr-obs029-ci-platform-83dcba6498eb.json`.

## Resource controls and unchanged client acceptance

The full Plugin gate passed at its unchanged pin, including API drift, lint, typecheck, all 120 tests and build. No tracked client file changed in that acceptance clone.

Local free space later fell below 3 GiB, and the consumer runner stopped before the next build. The failed resource attempt is retained under `/tmp/ratatoskr-obs029-sites-gate-default-low-disk-attempt1*`. No unfinished pin was pushed. Only managed package caches from the assigned worktrees and prior assistant task were cleaned under build-gate. No Docker image, volume, worktree, source, user file or evidence artifact was removed.

Contracts and Platform gates used their default profiles. Remaining local consumer gates set `CARGO_PROFILE_DEV_DEBUG=0`, `CARGO_PROFILE_TEST_DEBUG=0` and `CARGO_PROFILE_RELEASE_DEBUG=0` to reduce generated debug data. Assertions, features and test selection remain unchanged; the exact documented commands still run. While disk capacity was low, completed debug package outputs were cleaned before the doc or release build. After capacity recovered, further package cleanup became conditional, to keep unnecessary cache work out of the shared compiler queue. Published CI and disposable production-artifact acceptance keep the committed default profiles. These environment overrides are not committed as build configuration.

The Notes producer passed all 10 group behavior tests and its complete local gate: 195 tests, zero failed and zero ignored, fmt, Clippy, debug and release builds, deny, source-size checks, current and archived OpenSpec. Independent P0 review and the pre-commit hook passed. Commit `ac9866961533dad955450a2eb356d834bda19501` was published only after Platform CI passed; All five Notes CI checks passed, as recorded in `/tmp/ratatoskr-obs029-ci-notes-ac9866961533.json`. The group event forwards the same persisted list that the read API returns; one-file events keep omission.

Sites passed its complete local gate with 206 tests, zero failed and zero ignored. Its reviewed pin-only commit is `3cb379225cfa2bb5da9d0e83d94e877b835b1921`; all seven CI checks, including artifact self-test, passed.

The unchanged Export Agent passed all four `ObsidianCliApplyPathTests` at `e4be3b4fd54d17f85e9952097f1ded38f031d801`, after SwiftPM compiled its package. These tests use a fake CLI and a temporary vault connection; they do not prove a real Obsidian or Sync session. Its reproducible task-local Swift outputs were cleaned to recover disk. The task-local nightly used for the finished API check was uninstalled from its isolated Rustup home; the global toolchains and API tool remain unchanged. Other user projects and Docker artifacts remain intact. The consumer runner also stopped before a Knowledge build below the same free-space threshold; that attempt is retained separately. Heavy checks now release build-gate between compiler commands so other projects can use the shared queue.

Remaining consumer gates, client refreshes, CI and combined integration are pending. No historical TDD exception applies to this wave.

## Client runner correction

The first full Web unit run used Node 26.11.1 from the Python runner's PATH. It failed 144 tests because the Node native `localStorage` getter was unavailable without `--localstorage-file`, before the intended jsdom storage API could be used. The interactive shell selects Node 24.13.1, where that native getter is absent. The runner now explicitly selects that installed supported Node 24 line for the repeated complete unit suite and remaining commands. No test, assertion, application code or dependency was changed. The original Node 26 failure remains in `/tmp/ratatoskr-obs029-web-gate-04.log.node26-attempt1` and its result record. Hosted CI remains a separate acceptance gate.

The repeated Web unit suite on Node 24 passed all 338 tests in 78 files. The next E2E attempt could not launch any browser because a new acceptance clone had no Playwright Chromium 1234 cache. Its failure log and launch traces are retained, and the lock-selected browser runtime was installed under `/tmp/ratatoskr-obs029-playwright` with the repository's Playwright CLI. The repeated complete browser suite passed all 48 scenarios; no assertion or scenario was removed. The build, UI audit at the unchanged threshold of 79, and production dependency audit also passed.

SDK passed every documented gate, all 100 tests, the production dependency audit and independent P0 review. Generated input bytes and locked digests match Contracts 1756034, Sites 3cb3792 and Platform 83dcba6. Commit `0df7963db8facd15d5713a5fa01800198539e2a6` was published and all four hosted checks passed.

Knowledge passed its complete documented gate, all 349 tests with no failures or ignored tests, independent P0 review and the hook. Its published commit is `fff1bacc63636cf27868c1ff1bcc509d4dfc9d4c`; CI is pending. Resource stops retained completed command evidence and resumed only the remaining checks, after verifying the exact unchanged source and CI command sequence. No success was inferred for an unrun check.

## Publication dependency clarification

Notes was published after the strict Platform consumer passed CI, while unrelated pin-only gates remained active. The first coordination text described those independent consumers as a serial prerequisite too. A source search across every assigned child found conflict-event readers only in Platform; Notes is the producer and Contracts defines the wire type. The plan now states that actual dependency edge and preserves the mandatory join of every child gate and CI before snapshot promotion. This clarification changes no trust boundary, runtime deployment or TDD order.

Web published commit `3f7da8f1a6ef368b7cf7354a17d497ef96a4bc64` after its complete local gate and independent review. All four hosted checks passed, including the full gate in the declared CI environment. Knowledge also passed every hosted check, including the release artifact job. Client acceptance for this wave is complete; real Sync/MFA remains outside the accepted local scope.

Channel Digests passed its full gate, including all 126 test executions with zero failed or ignored tests. Commit `46efd8fb9e4c93abf5651bac030ee252fb997ef0` was published and all hosted checks passed. A mid-wave audit confirmed that primary workspace `a92d758584362b95ead0350ce3edc4653a1c1b8f` still has 21 clean baseline submodules and both protected user files match their recorded SHA-256 values. Proposed pins have not been staged yet.

## Security prerequisite discovered during consumer checks

ChatGPT compiled and passed its full test command, but cargo-deny refused its unchanged zip 8.6.0 for RUSTSEC-2026-0367, RUSTSEC-2026-0368 and RUSTSEC-2026-0369. The same explicit advisory check failed in Claude, Instagram and Threads before any ZIP production manifest edit. These are dependency-policy findings, not a confirmed exploit in the applications, which use bounded entry reads rather than the affected bulk extraction helpers. No advisory was ignored.

The separately prepared change `upgrade-archive-zip-security` / SEC-030 selected reviewed zip 9.0.0 (MIT, Rust minimum 1.88). Before compilation, its four inspection-only candidate graphs passed locked metadata and full cargo-deny; unrelated versions and dependency edges stayed unchanged. The new filename accessor is fallible, so the plan requires typed refusal mapping and a regression before compatibility edits. The owner approved that major update as a separate security prerequisite. The five unaffected pin-only consumers continue. The four-service profile result is below; workspace pins still await the remaining consumer and security gates.

## Four-service integration acceptance

The real Linux/ARM64 profile passed all 14 scenarios on Platform `83dcba6498ebaf2a3b7a97739d64b47ca47c25a8`, Sites `3cb379225cfa2bb5da9d0e83d94e877b835b1921`, Notes `ac9866961533dad955450a2eb356d834bda19501` and Knowledge `fff1bacc63636cf27868c1ff1bcc509d4dfc9d4c`. All four exact commits had passed hosted CI before the run. The two new checks proved unsafe source and target paths create no operation or command, and the real Notes outbox carries the same stale list as its read API and reaches the Platform operation result. Privacy acceptance covered 13 pages, one asset and 24 negative searches. Successful teardown created the final result record, and the recorded script, fixture and Compose hashes still match the tested source.

Evidence is in `evidence/obs029-contracts-final/` and `/tmp/ratatoskr-obs029-profile.log`. The existing supported HTTPS Debian mirror override was used; no source manifest or production build profile changed. Device acknowledgements, the Sync working tree and the Knowledge input are explicit fixtures. Real Sync networking, gateway TLS and production host permissions were not exercised by this profile. Browser rendering was covered separately by all 48 Web E2E scenarios. No workspace pin has been promoted before all security and consumer acceptance gates pass.

## SEC-030 approval and resource handling

On 2026-10-17 the owner approved zip 9.0.0 for the four archive readers. SEC-030 now proceeds in the same assigned worktrees. Four new filename regressions were written before the dependency or accessor edits. ChatGPT and Threads each produced a genuine assertion RED before implementation; Claude and Instagram passed initially because they already validate raw filename bytes. Those two results are characterization, not fabricated RED. All four focused tests then passed on the approved ZIP 9.0.0. SEC-030 records the exact logs and full-gate status.

Free disk space fell below 1 GiB while independent host builds ran. After all Web and SDK checks and CI had passed, only their task-owned node_modules and the task-owned downloaded Playwright runtime were removed. The four finished OBS-029 integration images were removed by exact tag after confirming successful teardown and no container references. Their full image metadata is retained in /tmp/ratatoskr-obs029-finished-profile-images.json. Integration logs, source hashes, result records, Docker volumes, earlier images and other projects remain intact. Published Ratatoskr package-output cleanup is queued under build-gate. These are reproducible build artifacts, not source or acceptance evidence.

The Docker build-cache inventory identified one private, reclaimable cache mount: `6xmr65ozfwlpzgl8bzuer7o1z`, `/build/target`, 5.72 GB, from the Ratatoskr Notes release build. Only this exact cache ID was pruned; no general Docker prune ran. The inventory and command result are `/tmp/ratatoskr-obs029-build-cache-inventory.txt` and `/tmp/ratatoskr-obs029-owned-docker-target-clean.log`. This removes reproducible compiler output, not source, images, volumes or test evidence.

The owner also approved SEC-030 D5 for the standalone Instagram fuzz graph. Its fixed Rustls record, existing BSD-3-Clause declaration and exact libfuzzer-sys 0.4.13 NCSA exception pass the full root and fuzz dependency policy. CI now enforces locked fuzz metadata and the full fuzz audit. Independent source review is clean; full local gates and exact-commit CI remain prerequisites for its pin. Threads `331e07c058eaa70e9f02c11a2f6bf313d6a19986` has passed all five hosted checks. Shared sccache cleanup was separately approved and freed 5,266,247,680 bytes without interrupting another project.


## Final child CI join

All 17 selected child commits passed their complete local gates, independent source reviews and every expected and observed hosted check. SEC-030 D6 restored unflagged CP437 names after genuine assertion RED in both readers, under the owner-approved oem_cp scope. Final ChatGPT `63a4506b39315749aab71d3fe3e9193fe23aa0e2` passed 280 tests; Threads `3b11fd1464b9afe721d350868a3f6fa2639aaec8` passed 211 tests and its release build. The final four security revisions are recorded in SEC-030. A fresh all-child CI query passed before root source review. The original four-service integration hashes still match its 14-scenario result. Workspace pins and provisioning are not yet accepted; real Obsidian Sync remains explicitly deferred.


## Prepared snapshot

All 17 selected gitlinks are staged after checking origin/main ancestry and clean acceptance clones. Two generated locks are byte-identical, `lock check` passes, and doctor reports healthy. Format, manifest and topology hashes are unchanged; the other four repository records are unchanged. The first successful `./ws` invocation built and ran the current workspace CLI. The remaining short lock-generation/check/doctor commands used that same compiled binary with the wrapper's workspace-root environment and harness working directory; no compiler ran outside build-gate. The queued second cargo wrapper was cancelled before it started, and its driver records that cancellation rather than a validation failure. Exact replacement commands, successful exit codes, binary digest and lock digest are in `/tmp/ratatoskr-obs029-workspace-lock-direct.json`. Full harness and disposable provisioning acceptance remain open.


The temporary root runner initially added a blanket 850-line Rust-file check copied from the product gates. It stopped on unchanged baseline `harness/crates/workspace-core/src/lib.rs` (1214 lines), before any harness command ran. Workspace `.github/workflows/ci.yml` and its workspace-specific QUALITY_GATES command list do not contain that blanket check. The runner now follows those actual workspace gates; the changed Rust snapshot test also passes the extra 850-line check. No source file, CI rule, linter threshold or policy was changed to pass. The baseline inventory is retained in `/tmp/ratatoskr-obs029-root-source-size-inventory.json`; this wave does not claim global harness file-length compliance.


The complete workspace harness passed all 131 tests, with zero failed, ignored or filtered tests. Formatter, all-target/all-feature Clippy with warnings denied, full dependency policy, strict current and archived OpenSpec, all seven owner-editing profile contract tests and the authentication contract scan of five profiles passed. The already-built CLI also passed the documented manifest and status commands. All eight root runner commands have exit 0 in `/tmp/ratatoskr-obs029-root-gates.json`. Provisioning acceptance remains open; no root snapshot is published yet.


## Disposable provisioning resource failure

All five original controller preflight roles passed their real ORAS pull, GitHub attestation source-commit/workflow checks and SHA256SUMS checks. Resumable HTTPS ranges were assembled only after their full OCI hashes matched. An isolated controller HOME kept this run separate from older cached snapshots. No attestation marker was created by the preload helper.

Original default Molecule converge then passed: 263 tasks OK, 144 changed, zero failed or unreachable. Idempotence reached 230 tasks OK with zero changes, but Ansible failed while transferring the monitoring alert-rule module with `Errno 28: No space left on device`. This is a failed provisioning attempt, not a passed idempotence check or behavioral RED. Verify did not run. The owned container and its two anonymous volumes were removed successfully. Logs are `/tmp/ratatoskr-obs029-molecule-v3-enospc-{converge,idempotence,destroy}.log`. Full provisioning acceptance remains open.

Completed task test executables and Node dependency directories were already absent; the earlier compiled workspace CLI was also no longer present. Only failed task-owned download remnants and owner-approved replenished sccache were cleared. A separate owner decision is requested for 27 inactive old published artifact-cache directories, 7.21 GiB, outside task worktrees. The current verified private artifact cache and all source/evidence remain intact. The alternative CI path needs a PR because workflows run only on main and pull requests. No workspace commit or pin publication has occurred.


The owner approved the exact old artifact-cache cleanup. All 27 inactive directories were removed after their paths, sizes, absence of symlinks and absence of active readers were checked again. The observed free space rose to about 10.2 GiB; current private verified artifacts, source and evidence were preserved. No process was stopped. The full local retry uses one build-gate slot with a free-space check before creation. The initial conservative 8 GiB estimate was refined to 7 GiB from the observed 3.5 GiB provisioning usage, 1.2 GiB original tamper-cache copy and at least 2 GiB headroom. All original tests and assertions remain unchanged. This supersedes the pending resource decision above, but does not claim provisioning success.


## Final local provisioning acceptance

The original default Molecule prepare, converge, idempotence and verify phases passed on the selected lock `b387699a8093cbea0cc2f8d91efede49d97716c796ebb41c8bc8bc0b607f8f87`. The disposable local Debian 12 ARM64 host ran the published and attested binaries with its own PostgreSQL and NATS. Idempotence made zero changes. Observed recaps:

- converge: `ratatoskr-host             : ok=263  changed=144  unreachable=0    failed=0    skipped=22   rescued=0    ignored=0`.
- idempotence: `ratatoskr-host             : ok=232  changed=0    unreachable=0    failed=0    skipped=52   rescued=0    ignored=0`.
- verify: `ratatoskr-host             : ok=121  changed=15   unreachable=0    failed=0    skipped=0    rescued=0    ignored=1`.

The one ignored SQL negative probe is intentional and followed by assertions for the error and absent success marker. No verification case was skipped. The owned container and its two anonymous volumes were removed. Configuration hash `a4c671674d4595dd8475b89fe764d20c4dd5ed2f685ca93f9a5e8fb0346613d5` is unchanged. Logs are `/tmp/ratatoskr-obs029-molecule-final-{converge,idempotence,verify,destroy}.log`; controller evidence is `evidence/obs029-molecule-controller/`.

Earlier registry timeouts, a controller HTTP/2 protocol failure and the initial index-versus-native-manifest guard failure remain recorded as failed setup attempts. A verified OCI index proves the native ARM64 image relationship. The controller used an isolated HOME and its five-repository artifact cache so the original tamper test did not copy unrelated cached snapshots. Existing Molecule state and tool configuration paths were retained. Redundant owned OCI download bytes were removed only after the original role verified all five source artifact directories. Only controller dependency-cache isolation, verified transfer and local HTTP/1.1 transport changed; original prepare, signature, source-commit, workflow and checksum checks still ran. The original role fetched and attested each exact artifact. No manual attestation marker was created, and no security check was skipped.

These are local stand-in checks. They retain the declared fake Bot API and tunnel fixtures and do not prove real Obsidian Sync/MFA, Cloudflare account operation, DNS, production TLS or production-host permissions. Root publication and exact-commit CI remain open.
