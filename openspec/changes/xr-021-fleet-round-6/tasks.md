## 1. Implementation by repository

Dependency order. Every child repository pushed its Round 6 commits to `main` under the repository owner's authorization, so no pull request exists to link; each item cites the pushed head and its hosted CI result as read through the GitHub API on 2026-10-13. The commits of each repository, with the R6 ids they implement, are listed in `changesets/XR-021-fleet-cross-repo-fixes.yaml` under `round_6`.

- [x] 1.1 `ratatoskr-channel-digests` at `a7cec3a1e13534fa226b8fcfd40425879db69060` (R6-02). Hosted CI: 5 of 5 check runs succeeded.
- [x] 1.2 `ratatoskr-knowledge` at `b5f2bbd786e039b3a49168c6914647f4e99acd19` (R6-01, R6-02 consumer). Hosted CI: 5 of 5.
- [x] 1.3 `ratatoskr-chatgpt` at `0b142eb82e1ad55bbe282acfd2996d80dd67e398` and `ratatoskr-claude` at `049922d7be40ac533d84b084f54bb56604abd5d2` (R6-03). Hosted CI: 5 of 5 each.
- [x] 1.4 `ratatoskr-github` at `da4f67991ad83111f3857e26f022bfdee80d85a7` (R6-01 pinning tests and documentation, no behaviour change). Hosted CI: 5 of 5.
- [x] 1.5 Platform, contracts, extractor, vault, x, instagram, threads, telegram, browser-extension, export-agent, mobile and web have no Round 6 work and do not move.
- [x] 1.6 `ratatoskr-workspace`, last: this change, the harness assertions and legs, the documentation, the changeset record and the pins. The commits and their hosted CI are recorded in 7.2.

## 2. The Round 6 behaviour is recorded

- [x] 2.1 Write this change: the proposal, the design and the spec deltas for `knowledge-ingest-limits`, `channel-digest-chain` and `fleet-deletion-delivery`, from the contract sections R6-01 to R6-04. No test: documentation. `openspec validate --all --strict` is the gate.

## 3. Workspace harness assertions

- [x] 3.1 RED: extend `integration/tests/native_smoke_contract_test.sh` with a scan of `fixtures/f1_scenario.py` (the digest-mismatch assertion must name `outcome` and `digest_mismatch` and no `404` alternative, the failed-row assertion must not accept a missing row, no PASS detail prints `dirs left=`). The scan was run against the committed file and failed on those three lines before the fix, and was proved on a good and a bad scratch scenario.
- [x] 3.2 GREEN: the F1 assertions assert the `200` with `outcome == digest_mismatch`, both digests, the transfer row `failed` immediately after finalize with the chunks still on disk, and a PASS detail that names what was removed and kept. F1 passes with 128 assertions, and a scratch copy with three wrong expectations fails exactly those assertions.
- [x] 3.3 The state directory and the evidence root are `XR-021-r6` (`lib/common.sh`, `run.sh`, `README.md`, the contract test).

## 4. The fleet map

- [x] 4.1 `docs/fleet-map.html` is corrected against the origin/main heads of the children and `docs/DEPLOYMENT_TARGET.md`: the receipt method is `POST`, the receipts are on 8096 and 8097, the operator listeners on 9085 and 9086, the `9467` and `9084` conflicts are gone, the bound ports are 8091, 8092, 8096, 8097 and 8098, the wired lanes and the API list are regenerated. The inventory of statements, with the file and line that proves each, is in the commit body. The page renders in a headless browser with no script error. No test: documentation.

## 5. The native legs

- [x] 5.1 F7: the 401 closure is replaced by a wait leg and a 503 leg. RED: on the Round 5 Knowledge pin the wait leg fails at its pending assertion.
- [ ] 5.2 NOT DONE: RED evidence for the F4 manifest retention leg and the F6 in-flight deletion leg. They were run against the Round 6 heads only; neither was run against the Round 5 heads, so neither is shown to fail without its fix. This task stays open, and with it this change, until each is run or the owner accepts the gap.

## 6. The native smoke is run

- [x] 6.1 F1 (128 assertions), F4 (84), F6 (86) and F7 (54) were run through `integration/native/run.sh` as committed, one at a time, against the Round 6 heads of the children (`RATATOSKR_SMOKE_REF=origin/main` or a scratch copy that pointed at the task clones), every one `PASS` with no failed assertion, every submodule clean and no ACL violation in the NATS log. The runs did not go through the pinned checkouts; Platform ran at its origin/main of that day, which differs from the pin by deployment files only. Faked, seeded and not exercised hops are in the changeset under `round_6.native_smoke`.
- [x] 6.2 F2 as a regression of the pump change: `run.sh f2` with no `RATATOSKR_SMOKE_REF`, so built from the pinned checkouts after the pins moved (platform 3275d52, extractor b565523, knowledge b5f2bbd, chatgpt 0b142eb, claude 049922d), ended `PASS` with 93 assertions, no ACL violation in the NATS log and every submodule clean. It does not delete anything, so it says nothing about the row lock.

## 7. The pins advance and the round is recorded

- [x] 7.1 Move five gitlinks (knowledge, github, channel-digests, chatgpt, claude) to the Round 6 heads, update `EXPECTED_PINS` in `harness/crates/workspace-cli/tests/committed_snapshot.rs`, and regenerate `workspace.lock`. No new test: generated and configuration files; the harness checks and `ws lock check` are the gate.
- [x] 7.2 Extend `changesets/XR-021-fleet-cross-repo-fixes.yaml` with the `round_6` block: the child commits, the breaks, the exclusions, the amended residual risks, the harness results and the native smoke results exactly as reported. `composed_integration.status` stays `native smoke only`. No test: documentation.

## 8. Verification

- [x] 8.1 Run `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --all-features --locked -- -D warnings` and `cargo test --workspace --all-features --locked` in `harness/`, `./ws manifest check`, `./ws lock check`, `./ws status`, `./ws doctor`, `openspec validate --all --strict`, `git diff --check`, and the integration contract tests that do not need Docker.
- [ ] 8.2 Publish and confirm the hosted CI of the pushed commits.

## 9. Archive

- [ ] 9.1 NOT DONE: `xr-021-fleet-round-5` is archived first, and its task 6.2 is open, so this change cannot be archived before it. This change is archived only when every task is ticked; tasks 5.2, 8.2 and 9.1 are open. An archive with an unticked task is the false close that `openspec validate --archived` exists to refuse.
