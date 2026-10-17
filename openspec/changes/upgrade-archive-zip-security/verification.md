## Approval and source review

The owner approved zip 9.0.0 on 2026-10-17. This is SEC-030, an explicit dependency-security prerequisite for OBS-029. The four repository writers remain the existing assigned OBS-029 worktrees.

Upstream identifies 9.0.0 as patched for the three observed findings:

- RUSTSEC-2026-0367: https://github.com/zip-rs/zip2/security/advisories/GHSA-vv5m-jxxh-4627
- RUSTSEC-2026-0368: https://github.com/zip-rs/zip2/security/advisories/GHSA-4v9h-p7m9-rh26
- RUSTSEC-2026-0369: https://github.com/zip-rs/zip2/security/advisories/GHSA-4684-h2q9-2vcp

The registry archive checksum is `711e8c9646791c49b7eb799a19c4ae70a9b8372ddc6a1fa4778defd1e2aa5d5e`. The published package is MIT, declares Rust 1.88 and has no build script or procedural macro. Source triage found no unexplained process, network, home-directory or environment access. Embedded byte references are fixed test fixtures. The source and review records remain under `evidence/obs029-zip-review/` in the task workspace.

Four inspection-only candidate graphs change only ZIP's version and checksum. No unrelated package, dependency edge or package name changes. All four candidates passed locked metadata and full cargo-deny before compilation. Actual implementation must use those reviewed graphs, default features off and the existing deflate feature.

## Policy RED

ChatGPT's full local gate passed its test command and then failed cargo-deny on all three advisory IDs. Its evidence is `/tmp/ratatoskr-obs029-chatgpt-gate.05`. The same explicit advisory check failed in Claude, Instagram and Threads; `/tmp/ratatoskr-sec030-policy-red.json` lists their logs. All four failures preceded production ZIP dependency edits. No advisory ignore was added.

## Filename checks

Four new tests exercise each public archive inspector. The fixture changes a filename byte to `0xff` and sets UTF-8 bit 11 in both the local and central headers. The payload and CRC stay unchanged. The test expects the existing typed refusal before extraction.

The observed initial executions are recorded below. Claude and Instagram already validate raw bytes, so their first passing results are characterization.

Independent review of the Claude and Instagram characterization bundles found no accepted actionable P0 finding. Those regression and lint checks passed before characterization commits and dependency edits.

## Acceptance still required

Full repository gates, the final source reviews, exact-commit hosted CI, and the combined OBS-029 snapshot checks remain open. No production deployment is part of this change.

Published-source follow-up: `src/types.rs::ZipFileData::name` first tries UTF-8, then CP437 without checking the UTF-8 flag. The planned accessor error mapping alone cannot enforce refusal. The same scoped behavior therefore also needs a raw-byte UTF-8 check when bit 11 is set in ChatGPT and Threads. This preserves their existing unflagged CP437 path. Claude and Instagram already validate raw bytes. This source finding precedes production dependency and accessor edits.

The first four filename executions failed compilation with ENOSPC before any behavioral assertion ran. None is RED. The original logs and result JSON files are retained with suffix `.no-space-attempt1`. No production ZIP edit followed those failures. Five other unstarted task wrappers were cancelled after verifying they did not hold the build slot or have a child compiler. Their completed successful command prefixes remain intact; `/tmp/ratatoskr-sec030-resource-queue-stop.json` records the cancellation. Claude and Instagram characterization Clippy checks did run and passed.

The owner selected waiting for RIPDPI. That UI run was not interrupted. Its slot was released, free capacity recovered to about 14 GiB, and all four old-version filename checks were queued again before dependency or accessor edits.

## Observed old-reader filename results

After capacity recovered, all four exact focused tests compiled and ran on zip 8.6.0, before any production dependency or accessor edit:

- ChatGPT: one test failed because inspection returned a successful inventory with `�ntry.json`, instead of the required refusal.
- Threads: one test failed because inspection returned successful entry names containing `�ntry.json`.
- Claude: one test passed. Its existing `name_raw` / strict UTF-8 validation returned `UnsafePath`. This is characterization, not RED.
- Instagram: one test passed. Its existing raw-byte validation returned `UnsafePath`. This is characterization, not RED.

Logs and exact commands are `/tmp/ratatoskr-sec030-<repository>-filename-red.log` and their JSON records. The same filename suffix `red` records the planned first execution; it does not label the two green characterizations as failures. Claude and Instagram also passed all-target Clippy, formatting, independent P0 review and the hook before their separate test-only characterization commits. Pending OBS-029 Cargo pin changes remain staged separately.

The four actual production locks now resolve the reviewed ZIP 9.0.0 graph. `cargo fetch --locked` and `cargo deny --locked check` passed in each worktree; `/tmp/ratatoskr-sec030-policy-green.json` records exact commands and exits. A parsed lock comparison confirmed that the update changed no package or edge beyond ZIP's version and checksum, relative to the already staged OBS-029 pin. The filename implementation checks bit 11 raw bytes in ChatGPT and Threads before the decoder fallback; bounded extraction code remains in place. Claude needs only two test-accessor API edits, and Instagram needs no reader source edit.

The separate test-only characterization commits are Claude `5c0d5cd` and Instagram `64aa9b7` (full IDs in `/tmp/ratatoskr-sec030-characterization-commits.json`). The final local change bundles for all four repositories passed independent P0 source review. Exact file hashes and original bases are frozen in `/tmp/ratatoskr-sec030-source-freeze.json`; `/tmp/ratatoskr-sec030-reviews.json` lists the reports. Publication requires every documented local command, a one-test GREEN execution, unchanged reviewed file hashes, a clean hook and unchanged remote base. Hosted CI remains a separate gate before pins.

All four focused filename tests passed on ZIP 9.0.0, each with one executed test and zero failed or ignored tests. ChatGPT and Threads now refuse the same malformed flagged name that the old reader accepted. The two pre-existing strict readers retain their typed refusals.

The standalone Instagram metadata guard first failed with exit 101 because its old lock could not satisfy the inherited path dependency under --locked. After changing only the approved contracts references and ZIP node, full locked metadata passed. A full fuzz policy check also ran and failed on separate existing development-graph debt: rustls 0.23.45 advisory IDs 0346–0349, NCSA not allowed for libfuzzer-sys 0.4.13, and missing license metadata on the local fuzz package. That initial failure remains the pre-fix evidence. The owner then approved design D5 on 2026-10-17. The local child plan is `ratatoskr-instagram/openspec/changes/align-fuzz-security/`. Only the Rustls record changed from 0.23.45 to the existing production 0.23.46, with no other new package or edge. The local fuzz manifest declares the existing BSD-3-Clause. The exact libfuzzer-sys 0.4.13 exception permits its required NCSA license without changing the global allowlist or advisory rules. Final locked metadata, full root policy and full fuzz policy all passed; the fuzz command uses the explicit root deny.toml. Independent review of this approved extension returned no actionable P0 finding. Full repository gates and exact-commit CI remain separate pending acceptance steps.

Threads completed the full local gate, hook and source review, then published `331e07c058eaa70e9f02c11a2f6bf313d6a19986`. All five exact-commit CI checks passed: [commit checks](https://github.com/po4yka/ratatoskr-threads/commit/331e07c058eaa70e9f02c11a2f6bf313d6a19986/checks). The other three security repositories and five remaining pin consumers still require their remaining gates and CI.

A later resource shortage left about 0.3 GiB free. Only two waiting task-owned Cargo test wrappers were cancelled before execution, with no child compiler and no build-slot ownership. Their prior successful steps are retained in `/tmp/ratatoskr-sec030-resource-queue-stop2.json`. This is not a test RED or a test failure. Other projects were not interrupted.

The owner approved clearing the shared reproducible sccache on 2026-10-17. Only its hash and preprocessor cache directories were removed; no compiler or cache server was stopped. The operation freed 5,266,247,680 bytes. `/tmp/ratatoskr-sec030-approved-sccache-clean.json` records the exact path and free-space measurements. Source worktrees, evidence and other tool caches were preserved.

Before Instagram publication, actual Threads deny-job logs proved hosted CI installs cargo-deny 0.20.2. The earlier local 0.19.0 check was valid but used different --config placement. The new CI/docs command was corrected to the 0.20 root-option form before push. An isolated official 0.20.2 ARM64 macOS artifact was checked against its GitHub release SHA-256, and both full root and fuzz audits then passed on that exact tool. Logs are `/tmp/ratatoskr-sec030-instagram-final-{root,fuzz}-policy-0202.log`; artifact identity is `/tmp/ratatoskr-sec030-tools/identity.json`. Only the queued task-owned Instagram validation wrapper was replaced before it started, so its remaining full gates use the current CI command list and tool. This is a validation-tool alignment, not a test RED or production dependency change.

A final published-source check found a legacy-name compatibility gap in ChatGPT and Threads: ZIP 8.6 decodes unflagged names as CP437, while ZIP 9 first tries UTF-8. New public-inspector tests assert the old interpretation of C3 A9 bytes (`├⌐.json`), with no filename payload or CRC change. These tests are queued and no RED has yet been claimed. Root snapshot preparation was stopped before pin changes. D6 records the reviewed decoder candidate, its full-policy GREEN inspection and the required owner choice; production manifests and decoder implementation remain unchanged.

Both D6 public-inspector regressions now ran on the published ZIP 9.0.0 implementations and failed by the intended name assertion: actual `é.json`, expected `├⌐.json`. Each executed one test, with zero ignored tests and no compile error. Logs and JSON are `/tmp/ratatoskr-sec030-{chatgpt,threads}-legacy-red.log`. Only these two test files changed; production manifests and decoder code remain unchanged while the owner chooses the implementation. All 17 originally published child revisions have successful CI; this newly reproduced compatibility gap still blocks pin promotion.


### D6 owner approval and corrective checks

The owner approved oem_cp 2.1.2 with default features disabled for ChatGPT and Threads. Production edits followed both observed assertion RED results. Each actual lock adds only the four approved packages; every existing package version, checksum and dependency edge is unchanged. A trial Cargo resolution selected another existing tempfile/getrandom edge; it was rejected, and the retained exact graph passes locked metadata. Both complete actual graphs pass cargo-deny 0.20.2 without policy exceptions. The implementation uses the total CP437 conversion for unflagged non-ASCII bytes, leaves ASCII borrowed, and keeps strict flagged UTF-8 refusal. Validated Unicode Path extra fields still take precedence. Additional tests cover a valid Unicode override (unchanged behavior) and invalid-CRC fallback (another case of the same unflagged-name behavior already captured by the observed RED). No separate RED result is claimed for those added cases. Rust 1.97.0 on aarch64-apple-darwin is the local toolchain. Focused GREEN, full gates, independent review and new exact-commit CI remain required before promotion.


Both CP437 regressions now pass on the compiled Rust 1.97 ARM64 implementations: one executed test, zero failed and zero ignored per repository. The same freshly built test binaries each also pass the Unicode Path / invalid-CRC case and the existing malformed UTF-8 refusal case. Those short direct runs did not invoke Cargo or compile outside build-gate. Evidence: `/tmp/ratatoskr-sec030-{chatgpt,threads}-legacy-green.log{,.json}` and `...-legacy-direct-boundaries.json`. Both independent five-file source reviews have no accepted/actionable P0 finding. Full gates and new exact-commit CI are still pending; no corrected child SHA or workspace pin is published yet. Replenished shared sccache data was cleared under the existing owner approval, freeing another 1,306,497,024 bytes without stopping any process; `/tmp/ratatoskr-sec030-approved-sccache-clean-d6.json` records the exact scope.


The first full D6 Clippy command failed in both test files because the new CRC literal lacked digit separators. Both diagnostics requested `0x6a38_7172_u32`; only that spelling changed. The value, production implementation and assertions are unchanged, and no lint was suppressed. These exit-101 results are style-gate failures, not behavioral RED evidence. Their original logs remain under `...-legacy-gate.02`. Fresh complete gates use `...-legacy-final-gate`, and independent source review is repeated for the final source bytes. No child was committed or pushed before this correction.


## Final child acceptance

Both final D6 full gates passed, including 280 ChatGPT and 211 Threads tests, with zero failed, ignored or filtered tests. Threads also passed doc and release builds. The only full-gate correction was the value-preserving CRC digit separator; no lint or policy was weakened. Both final source reviews are clean. Hosted CI passed every expected and observed check at these selected revisions:

- `chatgpt` [`63a4506b39315749aab71d3fe3e9193fe23aa0e2`](https://github.com/po4yka/ratatoskr-chatgpt/commit/63a4506b39315749aab71d3fe3e9193fe23aa0e2/checks).
- `claude` [`fc759137a7b6fc790d9e6266a94b82d444c91bba`](https://github.com/po4yka/ratatoskr-claude/commit/fc759137a7b6fc790d9e6266a94b82d444c91bba/checks).
- `instagram` [`bd2e1096fc94af4e0c9bcf7abb5e336ec9c431e5`](https://github.com/po4yka/ratatoskr-instagram/commit/bd2e1096fc94af4e0c9bcf7abb5e336ec9c431e5/checks).
- `threads` [`3b11fd1464b9afe721d350868a3f6fa2639aaec8`](https://github.com/po4yka/ratatoskr-threads/commit/3b11fd1464b9afe721d350868a3f6fa2639aaec8/checks).

All 17 selected child CI sets were freshly re-read before workspace source review. Child acceptance is complete; workspace pin, lock, provisioning and publication tasks remain open.


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


## Published verified snapshot

Workspace `282fc0c34edf72c23df78ac362bfcb97dcf8a999` was published to main after all 17 selected child revisions passed full local gates, independent source review and exact-commit CI. Every expected and observed root check passed (8 checks): [workspace checks](https://github.com/po4yka/ratatoskr-workspace/commit/282fc0c34edf72c23df78ac362bfcb97dcf8a999/checks). The committed lock SHA-256 is `b387699a8093cbea0cc2f8d91efede49d97716c796ebb41c8bc8bc0b607f8f87`. Local acceptance includes the 131-test workspace gate, deterministic lock, healthy doctor and original default Molecule checks. The combined profile passed 14 scenarios before the first snapshot, and its fresh run passed all 14 again after the polling correction. Owned disposable fixtures were removed. Protected user files and clean baseline submodules were checked again.

OBS-024 tasks 3.13–3.16 are now checked, using this wave's genuine pre-implementation RED evidence. No new test-order exception was used. Existing historical exceptions remain recorded. Rollout and rollback remain as stated in the changeset; retain the ZIP security fixes in any corrective snapshot and stop Notes emission before an older strict reader. No production host, credentials, DNS or Cloudflare account was changed. Real Obsidian Sync/MFA remains deferred by the owner, and the original OBS-024 change remains active.
