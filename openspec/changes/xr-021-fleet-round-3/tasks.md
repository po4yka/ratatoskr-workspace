## 1. Implementation by repository

Dependency order. Every child repository pushed its round 3 commits directly to `main` under the repository owner's authorization, so no pull request exists to link; each item cites the pushed head and its hosted CI result as read through the GitHub API on 2026-10-12. The commits of each repository, with the R3 ids they implement, are listed in `changesets/XR-021-fleet-cross-repo-fixes.yaml` under `round_3`.

- [x] 1.1 `ratatoskr-platform` at `075c7efca80adad938843faf7ae194a35386d55f`. Hosted CI: 6 of 6 check runs succeeded.
- [x] 1.2 `ratatoskr-extractor` at `b44ba81637ff8979f9e3ad4ebbea967335f6bd6b`. Hosted CI: 6 of 6.
- [x] 1.3 `ratatoskr-knowledge` at `542cd6998deaa7228dbdf1fe9d48bfb99a639ad8`. Hosted CI: 5 of 5.
- [x] 1.4 `ratatoskr-channel-digests` at `cdbf87fbbc757d445c27c4e72950e755af29690e`. Hosted CI: 5 of 5.
- [x] 1.5 `ratatoskr-github` at `2bc979d27db9c82b5e347294cd48665769d4ecea`. Hosted CI: 6 of 6.
- [x] 1.6 `ratatoskr-vault` at `24573faf20882f3c55c47664c84f0b1458f8dff9`. Hosted CI: 5 of 5.
- [ ] 1.7 `ratatoskr-x` at `4a32e8eaa39771a2926d6932ff08f84848d7ce8a`. NOT GREEN: 4 of 5 check runs succeeded and `fleet / invariants` failed, because the fleet scan for committed private keys matches `crates/x-core/tests/config.rs` (a test fixture added for `EXTRA_CA_FILE`). Reported as a defect of the owning repository; this repository does not edit it. The pin is recorded as it is.
- [x] 1.8 `ratatoskr-instagram` at `79ae7767178b9a57a6a2a6e0f43a6218fcf4e88a`. Hosted CI: 5 of 5.
- [x] 1.9 `ratatoskr-threads` at `e3656d08da406537cd63c143d3dba5520e1aa43a`. Hosted CI: 5 of 5.
- [x] 1.10 `ratatoskr-chatgpt` at `d994f8b7a05436d0cdc81de51f608c601d70a8ac`. Hosted CI: 5 of 5.
- [x] 1.11 `ratatoskr-claude` at `49baae26bea34ecf3d87018ab8a2b96275ba12e3`. Hosted CI: 5 of 5.
- [x] 1.12 `ratatoskr-telegram` at `81aa9e2116ea9e61faad5da594dd3ae28df0dc46`. Hosted CI: 5 of 5.
- [x] 1.13 `ratatoskr-browser-extension` at `0aceedd44d2c9448c817cf6464fa6ea81917fd1c`. Hosted CI: the four checks of the commit succeeded; a separate `Dependabot Updates` run on the same commit failed, which is not a check of the code.
- [x] 1.14 `ratatoskr-export-agent` at `1009f2992a51e5a6ff54724d3a3bf762e1c30243`. Hosted CI: 4 of 4.
- [x] 1.15 `ratatoskr-workspace`, last: this change, the harness checks, the profiles, the native harness, the documentation, the changeset record and the pins. Published as 4df2b20cf440178b7c95c5b48317c2d1d38d9bcf; its five required checks (zizmor / audit, fleet / invariants, openspec / specs, deny, snapshot) concluded success on 2026-10-12.

## 2. The round 3 behaviour is recorded

- [x] 2.1 Write this change: the proposal, the design and the spec deltas for `fleet-bus-topology`, `operation-report-authority`, `ai-archive-receipt-binding`, `ai-archive-import-completeness`, `channel-digest-chain`, `postgres-provisioning`, `assertion-key-procedure` and `social-capture-lifecycle`, from the contract sections R3-01 to R3-20. No test: documentation. `openspec validate --all --strict` is the gate.

## 3. Inbox prefixes, one contracts revision, PostgreSQL roles, shared secrets

- [x] 3.1 RED: extend `bus_acl.rs` with `every_non_edge_stanza_subscribes_only_to_its_own_inbox_prefix`, `the_owner_repository_uses_the_prefix_literal` (with a mutation test that changes the literal and drops the call) and `every_identity_has_a_vendored_copy`, with `FRAGMENTS` grown from six to twelve; add `contracts_pin.rs`, `postgres_roles.rs` and `shared_secrets.rs`. Run against the round 2 pins: the new `bus_acl.rs` tests failed (every one of the twelve non-Edge stanzas subscribed to `_INBOX.>`; six vendored copies missing; no service wired a prefix), `contracts_pin.rs` failed (`chatgpt` and `claude` lock `5426cf3`, the changeset names `ad16855`), both `postgres_roles.rs` tests failed (the examples of channel-digests, chatgpt, claude, github, instagram, knowledge, telegram, threads, vault and x name a role nothing creates; github, instagram, threads, vault and x name another database or port; Knowledge's role file does not exist). `shared_secrets.rs` PASSED against the round 2 pins, because all four pairs are already spelled consistently; it did not fail first and guards against a rename.
- [x] 3.2 GREEN: the pins advance (task 7.1) and the checks pass.
- [x] 3.3 Update `docs/QUALITY_GATES.md` with the four checks and what each cannot see. No test: documentation.

## 4. Integration profiles

- [x] 4.1 RED: extend `web_operational_profile_test.sh` (the broker must run a rendered file for the Edge identity), add `no_unauthenticated_broker_test.sh`, and make `telegram_library_profile_test.sh` and `telegram_notification_profile_test.sh` require the webhook's `assertion-key` commands and forbid `genpkey` and `xxd`. Run before the change: `web_operational_profile_test.sh` and `no_unauthenticated_broker_test.sh` failed (`service nats does not start from a rendered configuration file`, `starts with command-line flags and no authorization`, `runner ... does not call render_nats_conf`), and the two Telegram tests failed with `runner does not generate the assertion key with the webhook command`.
- [x] 4.2 GREEN: `run-web-operational.sh` and `compose/web-operational.yaml` render and mount the ACL; the two Telegram runners build the webhook and call the new command; `integration/README.md` is corrected; `XPA-020.md` is marked superseded (its test rejects a full revision in it). The contract tests pass with a stand-in `docker` that accepts the sentinel container's `run`, `inspect` and `rm`; no Docker profile was started, because the daemon is not available here.

## 5. The native smoke harness

- [x] 5.1 `integration/native/` (`run.sh`, `lib/`, flows F0 to F7, `fixtures/`) and `integration/tests/native_smoke_contract_test.sh`. NOT test first: the harness was ported from the by-hand scripts and its contract test written after it. The test was shown able to fail by mutating the scripts (a `pkill`, a write under `/tmp`, an unknown binary name, a shellcheck warning, a `kill` of an unrecorded pid).
- [ ] 5.2 NOT DONE: running any flow through `run.sh`. None of the committed flows has been run as committed. The Round 3 smoke results in the changeset came from the by-hand scripts under `.workspaces/XR-021/smoke/`, which are not part of this repository.

## 6. Documentation

- [x] 6.1 `docs/DEPLOYMENT_TARGET.md` records the per-service inbox prefixes in the NATS row, the PostgreSQL provisioning order and per-service roles, the rule that a smoke needing Edge's routes runs on the production loopback ports with PostgreSQL on a private port, and the assertion-key procedure in the Telegram row; `docs/QUALITY_GATES.md` records that the native smoke is a manual, machine-dependent run and not a CI gate; `integration/README.md` points at `integration/native/README.md`. No test: documentation; `port_allocation.rs` still passes.

## 7. The pins advance and the round is recorded

- [x] 7.1 Move fourteen gitlinks (platform, extractor, knowledge, channel-digests, github, vault, x, instagram, threads, chatgpt, claude, telegram, browser-extension, export-agent) to the round 3 heads, update `EXPECTED_PINS` in `harness/crates/workspace-cli/tests/committed_snapshot.rs`, and regenerate `workspace.lock`. Contracts, mobile and web do not move. No new test: generated and configuration files; the gates are `committed_workspace_is_complete_and_current`, the checks of task 3, `./ws manifest check`, `./ws lock check`, `./ws status` and `./ws doctor`.
- [x] 7.2 Extend `changesets/XR-021-fleet-cross-repo-fixes.yaml` with the `round_3` block: the child commits with the R3 ids, the breaks, the exclusions, the amended residual risks, the harness results, and the native smoke results exactly as reported. `composed_integration.status` stays `native smoke only`. No test: documentation.

## 8. Verification

- [x] 8.1 Run `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --all-features --locked -- -D warnings` and `cargo test --workspace --all-features --locked` in `harness/`, `./ws manifest check`, `./ws lock check`, `./ws status`, `./ws doctor`, `openspec validate --all --strict`, `git diff --check`, and the integration contract tests that do not need Docker.
- [x] 8.2 Publish and confirm the hosted CI of the pushed commit is green: 4df2b20cf440178b7c95c5b48317c2d1d38d9bcf, five of five required checks succeeded on 2026-10-12.

## 9. Archive

- [ ] 9.1 PARTLY DONE: `xr-021-fleet-cross-repo-fixes` and then `xr-021-fleet-round-2` were archived in that order on 2026-10-12 (every task ticked, hosted CI of 4df2b20 green), and `openspec validate --archived` passes. This change is NOT archived: tasks 1.7 and 5.2 are open, and an archive with an unticked task is the false close `openspec validate --archived` exists to refuse.
