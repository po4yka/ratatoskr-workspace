## 1. Implementation by repository

Dependency order. Every child repository pushed its round 4 commits directly to `main` under the repository owner's authorization, so no pull request exists to link; each item cites the pushed head and its hosted CI result as read through the GitHub API on 2026-10-12. The commits of each repository, with the R4 ids they implement, are listed in `changesets/XR-021-fleet-cross-repo-fixes.yaml` under `round_4`.

- [x] 1.1 `ratatoskr-platform` at `1624d037f3bf8b682d16ed5b273e5a82d1c3fe24` (R4-11, documentation). Hosted CI: 6 of 6 check runs succeeded.
- [x] 1.2 `ratatoskr-knowledge` at `4bf28ddce1fd0247c2e41e3d417ec572fcf11308` (R4-05). Hosted CI: 5 of 5.
- [x] 1.3 `ratatoskr-channel-digests` at `a0ee415a3342ff4da30ec9085fa6a23661c4cc8a` (R4-06). Hosted CI: 5 of 5.
- [x] 1.4 `ratatoskr-github` at `cc8c78d70880f68e3985ef437867a7b8146619d4` (R4-09). Hosted CI: 5 of 5.
- [x] 1.5 `ratatoskr-threads` at `ba00a1e2114d2b59e7a93526e423ba4c6ccc12b8` (R4-07). Hosted CI: 5 of 5.
- [x] 1.6 `ratatoskr-telegram` at `04c25a5346df1acf95fa01f82bb984053026fafd` (R4-08). Hosted CI: 5 of 5.
- [x] 1.7 `ratatoskr-claude` at `6f27d836a3670554866b50da3636cd0410a65f04` (R4-02, R4-03). Hosted CI: 5 of 5.
- [x] 1.8 `ratatoskr-chatgpt` at `78b3dfa0dede9b7d9cd23e17ce64836eec2a11df` (R4-04, R4-10). Hosted CI: 5 of 5.
- [x] 1.9 `ratatoskr-x` at `f57fdda0e2d3ded31c0a387364506ab301a8ca7a`, the commit that moves the test CA certificate into its own fixture and repairs the red `fleet / invariants` check of the round 3 pin (round 3 task 1.7). Hosted CI: 5 of 5.
- [x] 1.10 Contracts, extractor, vault, instagram, browser-extension, export-agent, mobile and web have no round 4 work. Contracts gained a CI-action update (`460057a`) that changes no contract file; its pin stays.
- [x] 1.11 `ratatoskr-workspace`, last: this change, the harness checks, the native harness fixes, the documentation, the changeset record and the pins. Published as f9302cc (specs, checks, harness fixes, documentation, changeset) and bd843fdb4422103727c6a677e95db44b5c09f720 (the nine pins); the five required checks of bd843fd are recorded in 8.2.

## 2. The round 4 behaviour is recorded

- [x] 2.1 Write this change: the proposal, the design and the spec deltas for `ai-archive-import-completeness`, `fleet-ingest-redelivery`, `channel-digest-chain`, `social-capture-lifecycle` and `content-capture-command`, from the contract sections R4-02 to R4-08 and R4-10. No test: documentation. `openspec validate --all --strict` is the gate.

## 3. Workspace harness checks

- [x] 3.1 RED: add `harness/crates/workspace-core/tests/schema_in_place.rs` (`no_schema_adds_a_column_after_creating_a_table`, `the_constraint_additions_that_close_a_foreign_key_cycle_are_allowed`, and two tests of the scan itself). Run against the round 3 pins: the first test failed for the stated reason, reporting the seven ChatGPT statements at lines 75, 312, 314, 316, 318, 343 and 345 and nothing else; the other three passed.
- [x] 3.2 RED: extend `bus_durables.rs` with `service_ack_wait_constants_agree_with_edges_durable_table` and a mutation test. Run against the round 3 pins: the first failed because Telegram states no `NOTIFICATION_ACK_WAIT_SECONDS`, and no other row disagreed.
- [x] 3.3 GREEN: the pins advance (task 7.1) and the checks pass: `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --all-features --locked -- -D warnings` and `cargo test --workspace --all-features --locked` in `harness/`.
- [x] 3.4 Update `docs/QUALITY_GATES.md` with both checks and what each cannot see. No test: documentation.

## 4. The native smoke harness

- [x] 4.1 RED: extend `integration/tests/native_smoke_contract_test.sh` with the cases of R4-12: no file names the round 3 state directory, `assert` leaves a caller's `name`, `cond`, `detail` and `line` visible, `assert_s04_durables` passes for a broker that holds the whole table, the `getMe` body of the fake Bot API has every key of the `bot-api` crate's fixture, F3 counts no reply with `wc -l` and asserts the status of the forwarded capture, and the fake OpenRouter answers a repository-analysis prompt with a schema-valid body. Each case was shown failing for its stated reason before its fix: the stale state directory, the four shadowed variables, the durable assertions against the previous `assert.sh` and `nats.sh`, the two missing `getMe` keys, the `wc -l` count in F3, and the 400 for the repository family.
- [x] 4.2 GREEN: `assert` uses `_assert_`-prefixed locals, `assert_s04_durables` renames its loop variables, `fake_bot_api.py` carries `can_connect_to_business` and `has_main_web_app`, F3 counts bot calls by method and reads the tap-recorded status of every `/v1/captures*` call, `fake_openrouter.py` answers the repository family, F7 requires a completed closure and keeps the failed closure as a separate leg, and the state directory and the evidence root are `XR-021-r4`. The contract test passes with shellcheck installed.
- [x] 4.3 Add the legs that are written in the flow files: F0 (a declared 9 MiB publish, the dispatcher's `check-config` with an ack wait of 31 and of 30, an idle notification subject), F3 (plain then forwarded, a redelivered update, the loss of the Platform session), F5 (an escaped Threads query) and F7 (the completed closure, the failed closure, the PAT registration). NOT RUN: none of these legs has met a service; `integration/native/README.md` says so. The legs of the plan that are not written (F1, F2, F4, F5 browser extension and F6) are listed there too.

## 5. Documentation

- [x] 5.1 `docs/QUALITY_GATES.md` records the new checks, the rule that the native smoke is a manual, machine-dependent run that is not a CI gate, and what the native harness fixes do and do not show; `integration/native/README.md` records, per flow, whether it was run through `run.sh` as committed (none) and what each flow could not show. `docs/DEPLOYMENT_TARGET.md` is unchanged: no port row is wrong (R4-01). No test: documentation.

## 6. The native smoke is run

- [ ] 6.1 NOT DONE: running any flow through `integration/native/run.sh` as committed. The round 4 native smokes (AI-archive upload, channel digests, Knowledge ingestion) passed from by-hand scripts under `.workspaces/XR-021/smoke/` and are recorded in the changeset with the hops they faked, seeded or did not exercise. F0, F3, F5, F6 and F7 were not run by any means in round 4. Until a flow is run through `run.sh`, this task stays open.

## 7. The pins advance and the round is recorded

- [x] 7.1 Move nine gitlinks (platform, knowledge, channel-digests, github, threads, telegram, claude, chatgpt, x) to the round 4 heads, update `EXPECTED_PINS` in `harness/crates/workspace-cli/tests/committed_snapshot.rs`, and regenerate `workspace.lock`. Contracts, extractor, vault, instagram, browser-extension, export-agent, mobile and web do not move. No new test: generated and configuration files; the harness checks and `ws lock check` are the gate.
- [x] 7.2 Extend `changesets/XR-021-fleet-cross-repo-fixes.yaml` with the `round_4` block: the child commits with the R4 ids, the breaks, the exclusions, the amended residual risks, the harness results, and the native smoke results exactly as reported. `composed_integration.status` stays `native smoke only`. No test: documentation.

## 8. Verification

- [x] 8.1 Run `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --all-features --locked -- -D warnings` and `cargo test --workspace --all-features --locked` in `harness/`, `./ws manifest check`, `./ws lock check`, `./ws status`, `./ws doctor`, `openspec validate --all --strict`, `git diff --check`, and the integration contract tests that do not need Docker.
- [x] 8.2 Publish and confirm the hosted CI of the pushed commits is green: bd843fdb4422103727c6a677e95db44b5c09f720, five of five required checks (zizmor / audit, fleet / invariants, openspec / specs, deny, snapshot) succeeded on 2026-10-12. The commit that records this result is checked the same way and named in the changeset.

## 9. Archive

- [ ] 9.1 NOT DONE: `xr-021-fleet-round-3` is archived first and then this change, each only when every task is ticked. Round 3 keeps task 5.2 open and this change keeps task 6.1 open, so neither is archived; an archive with an unticked task is the false close that `openspec validate --archived` exists to refuse. The order matters: this change restates round 3 requirement text in two MODIFIED deltas.
