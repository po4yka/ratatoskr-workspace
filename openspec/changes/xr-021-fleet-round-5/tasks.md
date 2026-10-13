## 1. Implementation by repository

Dependency order. Every child repository pushed its Round 5 commits directly to `main` under the repository owner's authorization, so no pull request exists to link; each item cites the pushed head and its hosted CI result as read through the GitHub API on 2026-10-13. The commits of each repository, with the R5 ids they implement, are listed in `changesets/XR-021-fleet-cross-repo-fixes.yaml` under `round_5`.

- [x] 1.1 `ratatoskr-contracts` at `d98967b7b7ee80442c93ef4657140068955c8f61` (R5-11, R5-12: the registered messages `knowledge.deletion_acknowledged` and `platform.stream_erasure_requested`, additive; the one wave-1 commit). Hosted CI: 8 of 8 check runs succeeded.
- [x] 1.2 `ratatoskr-platform` at `3275d523d004787aa5871266b8636dd0b11e74e6` (R5-04, R5-11, R5-12, R5-13). Hosted CI: 6 of 6.
- [x] 1.3 `ratatoskr-extractor` at `b5655232c10df6253bab2e9f97e13f913cf21547` (R5-02). Hosted CI: 6 of 6.
- [x] 1.4 `ratatoskr-knowledge` at `577ccc3935ae0620d9952d05a42b7f4da2e18f42` (R5-02, R5-03, R5-08, R5-11). Hosted CI: 5 of 5.
- [x] 1.5 `ratatoskr-channel-digests` at `65a5df7a7f1d6c82a1ce6213cacb980897680d58` (R5-07). Hosted CI: 5 of 5.
- [x] 1.6 `ratatoskr-chatgpt` at `6e9508764be8f9f876f4ddee611707951459b3a5` (R5-06, R5-11, R5-12). Hosted CI: 5 of 5.
- [x] 1.7 `ratatoskr-claude` at `272b6833d7207241416c1b8b00012ade4e234f22` (R5-06, R5-08 documentation, R5-11, R5-12). Hosted CI: 5 of 5.
- [x] 1.8 `ratatoskr-x` at `cf21321f1286ebaa85181b498cf76a5687211978` (R5-11). Hosted CI: 5 of 5.
- [x] 1.9 `ratatoskr-instagram` at `171caf11830e786900a7aafe88689f5e87f54b23` (R5-09, R5-11). Hosted CI: 5 of 5.
- [x] 1.10 `ratatoskr-threads` at `e8cb95cfb074ae87c01c4fe8dca5f0988f687ba0` (R5-11). Hosted CI: 5 of 5.
- [x] 1.11 `ratatoskr-telegram` at `a8a337ad504e2a7f89a218fa972edcfa6078193e` (R5-10). Hosted CI: 5 of 5.
- [x] 1.12 `ratatoskr-export-agent` at `22c14fdc8310b043772cc0ea6874abae575a66b0` (R5-05). Hosted CI: 4 of 4.
- [x] 1.13 `ratatoskr-github` at `80aaa84a4c581336f88e034aeb8799248e010c22` and `ratatoskr-vault` at `b810b26b730de840fb2aa3225165d7a677df80a8`: the contracts pin only (every Rust repository resolves the one contracts revision). Hosted CI: 5 of 5 each.
- [x] 1.14 Browser-extension, mobile and web have no Round 5 work and do not move.
- [x] 1.15 `ratatoskr-workspace`, last: this change, the harness checks, the native harness fixes and legs, the documentation, the changeset record and the pins. The commits and their hosted CI are recorded in 8.2.

## 2. The Round 5 behaviour is recorded

- [x] 2.1 Write this change: the proposal, the design and the spec deltas for `fleet-deletion-delivery`, `fleet-bus-observability`, `ai-archive-upload-path`, `content-document-identity`, `knowledge-ingest-limits`, `channel-digest-chain`, `social-capture-lifecycle`, `content-capture-command` and `fleet-bus-topology`, from the contract sections R5-02 to R5-13. No test: documentation. `openspec validate --all --strict` is the gate.

## 3. Workspace harness checks

- [x] 3.1 RED: update `bus_durables.rs` (23 service durables, the five `*_deletion_acks` rows, `platform_stream_erasure`, the declared length of `DOMAIN_CONSUMERS`, a row matcher that resolves a named filter constant) and `bus_acl.rs` (the five durables with their owners, the three publish rights, invariant 7), and add `tombstone_acks.rs` and `alert_rules.rs`. Run against the Round 4 pins before the pins advanced: `bus_durables.rs` failed four tests (Platform's rows and `platform_stream_erasure`, the five owner literals, the declared length of 18, the unmodified-table precondition of the mutation test), `bus_acl.rs` failed two (no consumer-info permission for the five durables; no holder of the two new publish rights), `tombstone_acks.rs` failed two (five producers without a durable) and `alert_rules.rs` failed three (the rule file did not exist); each for the stated reason and not for a compile error. The invariant 7 test passed against the Round 4 pins, so its mutation test is its red.
- [x] 3.2 RED: add `base_urls.rs`. It passed at once against the Round 4 pins (it closes a coverage gap, R4 verdict 2), so it carries two mutation tests (a changed port, a renamed table row).
- [x] 3.3 GREEN: the pins advance (task 7.1) and the checks pass: `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --all-features --locked -- -D warnings` and `cargo test --workspace --all-features --locked` in `harness/`. Invariant 7 as the contract words it ("starts with `$JS.API.STREAM.`") also catches the stream info of the browser worker's KV bucket; the check allows that one subject and the spec says so.
- [x] 3.4 Update `docs/QUALITY_GATES.md` with the checks and what each cannot see. No test: documentation.

## 4. The native smoke harness

- [x] 4.1 RED, in part: extend `integration/tests/native_smoke_contract_test.sh` with the cases of R5-14: the interpreter choice against three stub interpreters (one that accepts a connection and never answers, one without `cryptography`, one good), `run.sh --dry-run f3` exiting 3 with `MISSING: python with HTTP serving and cryptography`, `q` returning non-zero on a psql error and an assertion over it failing, no flow naming `ingest_failures`, the F6 probe order and the `untilt` search wait, F1 waiting for fresh capabilities, the fixture builders being deterministic, the fake OpenRouter's status schedule, the receipt stand-in, the tap streaming `text/event-stream`, and no file naming `XR-021-r4`. The cases were committed together with their fixes (workspace commit `4d95fa7`). An old copy of the harness fails the new test at its first new line, which has no `py_select`; the later cases were not each run against the old code, so only the first is shown to fail first.
- [x] 4.2 GREEN: the harness fixes of `4d95fa7`: `py_select`, `q` and the assertion helper, the removed `ingest_failures` table, `RATATOSKR_SMOKE_REF`, per-flow logs and control files, the F1 wait, the F6 probe order and search wait, the series-3 digest (the old NOT RUN was a lookup of an export that the Civet conversation deletion removes, not non-determinism; the builders are byte-deterministic and the digest is recorded at upload in `$S/fx/<name>.sha256`), and the assertions written against behaviour the services no longer have. The contract test passes.
- [x] 4.3 Add the legs: F0 (the 23 durables, `platform_stream_erasure`, the deployed ACL probes, the lag series on 9464, the alert file parsed as YAML), F1 (staging reaper, dead token, readiness, the Claude knowledge file, a corrupt archive per provider, repeated keys, the 401 stand-in, a 256 MiB archive), F2 (one document identity, 2 MiB and 7.85 MB conversations, the credential and database outages, a Termed 400, a non-envelope message), F3 (a held progress stream), F4 (the retention timer, the scheduler occurrence), F5 (a social deletion reaching Knowledge), F6 (resend and acknowledgement, stream erasure, the foreign-subject probe, the owner after a mapping change for both providers). The README lists what each could not show.

## 5. Documentation

- [x] 5.1 `integration/native/README.md` records, per flow, that it was run through `run.sh` as committed, with the assertion count, and what each flow could not show; the state directory and the evidence root are `XR-021-r5`. `docs/DEPLOYMENT_TARGET.md` is unchanged: no port row is wrong (R5-01). No test: documentation.

## 6. The native smoke is run

- [x] 6.1 Every flow F0 to F7 was run through `integration/native/run.sh` as committed (workspace commit `4d95fa7`, one at a time, on the developer's Mac) against the `origin/main` of each child, which are the commits of 1.2 to 1.13 that each flow uses: F0 157 assertions, F1 127, F2 93, F3 67, F4 74, F5 64, F6 76 (run right after F1, which keeps the data F6 needs) and F7 49, every one `PASS` with no failed assertion, every submodule clean and no ACL violation in the NATS log outside F0's deliberate probes. The flows were exported with `RATATOSKR_SMOKE_REF=origin/main`, not built from the pinned checkouts. Faked, seeded and not exercised hops are in the changeset under `round_5.native_smoke`; the legs that stayed NOT RUN are listed there with the reason.
- [ ] 6.2 NOT DONE: RED evidence for the Round 5 legs. The plan required each leg that tests a Round 5 fix to be run first against the Round 4 head of the repository it covers (staging reaper at platform `1624d03`, same PDF twice at extractor `b44ba81` and knowledge `4bf28dd`, the 2 MiB conversation and the credential outage at knowledge `4bf28dd`, the progress stream at telegram `04c25a5`, resend, acknowledgement and stream erasure at chatgpt `78b3dfa`, the Claude plan after a mapping change at claude `6f27d83`). None was run, so none of those legs is shown to fail without its fix. This task stays open, and with it this change, until each is run or the owner accepts the gap.

## 7. The pins advance and the round is recorded

- [x] 7.1 Move fourteen gitlinks (contracts, platform, extractor, knowledge, channel-digests, chatgpt, claude, x, instagram, threads, telegram, github, vault, export-agent) to the Round 5 heads, set `contracts_sha` in the changeset to `d98967b7b7ee80442c93ef4657140068955c8f61`, update `EXPECTED_PINS` in `harness/crates/workspace-cli/tests/committed_snapshot.rs`, and regenerate `workspace.lock`. Browser-extension, mobile and web do not move. No new test: generated and configuration files; the harness checks and `ws lock check` are the gate.
- [x] 7.2 Extend `changesets/XR-021-fleet-cross-repo-fixes.yaml` with the `round_5` block: the child commits with the R5 ids, the breaks, the exclusions and open lows of R5-15, the amended residual risks, the harness results, and the native smoke results exactly as reported. `composed_integration.status` stays `native smoke only`. No test: documentation.

## 8. Verification

- [x] 8.1 Run `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --all-features --locked -- -D warnings` and `cargo test --workspace --all-features --locked` in `harness/`, `./ws manifest check`, `./ws lock check`, `./ws status`, `./ws doctor`, `openspec validate --all --strict`, `git diff --check`, and the integration contract tests that do not need Docker.
- [ ] 8.2 Publish and confirm the hosted CI of the pushed commits. Recorded in the changeset after the run is read.

## 9. Archive

- [ ] 9.1 NOT DONE: `xr-021-fleet-round-3` and `xr-021-fleet-round-4` are archived first, in that order, because this change restates their run-report text in a MODIFIED delta. This change is archived only when every task is ticked; task 6.2 and task 8.2 are open, so it is not archived. An archive with an unticked task is the false close that `openspec validate --archived` exists to refuse.
