## 1. Implementation by repository

Dependency order. Every child repository pushed its round 2 commits directly to `main` under the repository owner's authorization, so no pull request exists to link; each item cites the pushed head and its hosted CI result (every check run on that commit concluded `success` when read on 2026-10-11). The commits of each repository are listed in `changesets/XR-021-fleet-cross-repo-fixes.yaml` under `round_2`.

- [x] 1.1 `ratatoskr-contracts` at `5426cf3096733d714c59b02ec41e946fdedcd94d`. Its `origin/main` is one commit ahead (`460057a`, a CI action bump), so the snapshot pins the round 2 head.
- [x] 1.2 `ratatoskr-platform` at `8f8a8d8318f3c4ad44a508f8124cf923bc5552e8`.
- [x] 1.3 `ratatoskr-extractor` at `cf64d84cb6f41c929fd9b836fd47bb3f57bd23dc`.
- [x] 1.4 `ratatoskr-knowledge` at `14326b4b1a5f83b83d601c3df17dd9726aae1248`.
- [x] 1.5 `ratatoskr-channel-digests` at `30d6cd74b429f85f2a59f754b755cf800a1c8520`.
- [x] 1.6 `ratatoskr-github` at `7891aea45541192a0201e8ec61d430253dbabcee`.
- [x] 1.7 `ratatoskr-vault` at `24adc4cd782fdcc17a33890488cfc8376979186d`.
- [x] 1.8 `ratatoskr-x` at `da4ab3d8e9674f4b2e126266a6179702a01e0254`.
- [x] 1.9 `ratatoskr-instagram` at `b4d13176e3b728ae69f55148f34f84da5e0f87f7`.
- [x] 1.10 `ratatoskr-threads` at `9cf3707cdb26f6782392e102d8fd65d03724d9b8`.
- [x] 1.11 `ratatoskr-chatgpt` at `bd852e8483603423cd08f1a79c452b7946974c48`.
- [x] 1.12 `ratatoskr-claude` at `c242ac567c0ac7278f1a43b99ca39875847ac2dc`.
- [x] 1.13 `ratatoskr-telegram` at `869333b8d78395526096f183b219afba71ca8573`.
- [x] 1.14 `ratatoskr-browser-extension` at `70011f9e9c57877caf2f75ae0ba436456845ad5f`.
- [ ] 1.15 `ratatoskr-workspace`, last: this change, the two harness checks, the profile library, the changeset record and the pins. Closes when it is published and its hosted CI is green, which is outside the step that wrote it.

## 2. The round 2 behaviour is recorded

- [x] 2.1 Write the spec deltas for `fleet-bus-topology`, `ai-archive-receipt-binding`, `channel-digest-chain`, `blob-references`, `social-capture-lifecycle` and `repository-analysis-intake` and the new capability `operation-report-authority` from the contract sections R2-01 to R2-16. No test: documentation. `openspec validate --all --strict` is the gate and passes.

## 3. Every Edge upstream with an implementation has a listener

- [x] 3.1 Add `harness/crates/workspace-core/tests/edge_upstreams.rs::every_implemented_edge_upstream_is_bound_by_its_owner` and `routes_without_a_service_are_exactly_vault_social_and_ai`, with the bind matcher moved into `tests/support/binds.rs`. Run against the previous pins the first failed with `Edge routes KNOWLEDGE to 127.0.0.1:8091, but no deploy example of knowledge binds that port outside its operator (__ADMIN__) listener (0 examples read ...)` and the same for GITHUB, CHATGPT and CLAUDE; the second passed, because the route table itself did not change.
- [x] 3.2 The tests pass against the round 2 pins (task 6.1), which ship `knowledge.conf.example`, `github.conf.example`, `chatgpt.conf.example` and `claude.conf.example`. The matches are recorded in the file's module comment. `port_allocation.rs` still passes after the matcher moved.

## 4. Durable names agree across repositories

- [x] 4.1 Add `harness/crates/workspace-core/tests/bus_durables.rs` with the table of the 18 service-owned durables and the six others, the Platform row scan, the owner literal scan and a mutation test. The first run failed because the Telegram durable is declared through two named constants and not as a row (a defect in the test, fixed by a `platform_row` flag); it did not fail on the previous pins afterwards, because the names and filters already agreed there. The mutation test is what proves the scan reports a renamed durable and a changed filter.
- [x] 4.2 The scan passes against the round 2 pins. Limitation (a literal assembled at run time is invisible) is stated in the file's module comment and in `docs/QUALITY_GATES.md`.

## 5. Integration profiles run under the deployed ACL

- [x] 5.1 Add `integration/tests/nats_conf_test.sh`. Run before the library existed it failed with `missing .../integration/lib/nats-conf.sh`; run against the previous Platform pin with the library in place it failed with `the deployed max_payload of 8MB did not survive rendering`, because that pin had no `max_payload`.
- [x] 5.2 Add `integration/lib/nats-conf.sh` (`render_nats_conf`, `append_nats_test_user`) and generalize the nkey fixture to `integration/fixtures/nkeys.go`. The test passes against the round 2 Platform pin. The plan's third override, `jetstream.max_file_store: 2GB`, is not applied: the native smoke showed that Edge refuses to start with it.
- [x] 5.3 Extend `export_agent_product_profile_test.sh`, `telegram_library_profile_test.sh` and `telegram_notification_profile_test.sh`. Run before the change they failed with `runner does not source the NATS rendering library` (twice) and `profile service knowledge lacks RATATOSKR__API__LISTEN_ADDRESS: 127.0.0.1:8091`.
- [x] 5.4 Switch `run-export-agent-product.sh`, `run-telegram-library.sh` and `run-telegram-notification.sh` and the two compose files to the rendered ACL and the dedicated listeners; the TG-010 driver reports as `ratatoskr-extractor` because of the report authority. The three contract tests pass. They were run with a stand-in `docker` command that exits 0, because the daemon is not reachable here, so the sentinel-container step of the Telegram tests was not exercised and no composed profile was started.

## 6. The pins advance and the round is recorded

- [x] 6.1 Move fourteen gitlinks to the round 2 heads, update `EXPECTED_PINS` in `harness/crates/workspace-cli/tests/committed_snapshot.rs`, and regenerate `workspace.lock` with `./ws lock generate --output workspace.lock`. No new test: generated and configuration files; the gates are `committed_workspace_is_complete_and_current`, tasks 3.2 and 4.2, `./ws manifest check`, `./ws lock check`, `./ws status` and `./ws doctor`.
- [x] 6.2 Update `docs/DEPLOYMENT_TARGET.md`, `docs/QUALITY_GATES.md` and `integration/README.md`. No test: documentation; `port_allocation.rs` still passes.
- [x] 6.3 Extend `changesets/XR-021-fleet-cross-repo-fixes.yaml` with the `round_2` block: the child commits, the exclusions, the amended residual risks, the harness results and the native smoke results exactly as reported. No test: documentation.

## 7. The native multi-service smoke

- [x] 7.1 Built in round 3 (task 5.1 of `xr-021-fleet-round-3`): the `integration/native/` harness (`run.sh`, the flow scripts, the fixtures) and `native_smoke_contract_test.sh`, ported from the by-hand scripts and applying the findings below. NOT test first, and none of the committed flows has been run through `run.sh` yet (task 5.2 of the round 3 change stays open); the results in the changeset still come from the by-hand scripts.
- [x] 7.2 Record in the changeset the flows that ran and their results without upgrading any of them: AI-archive upload `passed: false` (Edge refuses non-production listeners, so the Edge-to-receiver hop was faked), channel digests `passed: true` with its hops not run or faked; the other five flows have no reported result and are recorded as not reported.

## 8. Verification

- [x] 8.1 Run `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --all-features --locked -- -D warnings` and `cargo test --workspace --all-features --locked` in `harness/`, `./ws manifest check`, `./ws lock check`, `./ws status`, `./ws doctor`, `openspec validate --all --strict`, `git diff --check`, and the profile contract tests that do not need Docker.
- [ ] 8.2 Publish and confirm the hosted CI of the pushed commit is green.
