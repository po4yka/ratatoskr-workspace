## 1. Implementation by repository

Dependency order. Every child repository pushed its commits directly to `main` under the repository owner's authorization, so no pull request exists to link; each item cites the pushed head and its hosted CI result (every check run on that commit concluded `success` when read on 2026-10-11). The commits of each repository are listed in `changesets/XR-021-fleet-cross-repo-fixes.yaml`.

- [x] 1.1 `ratatoskr-contracts` at `ad16855c4e7f3d52cd118274faa3b8f3ab4da576` (CONTRACTS_SHA), merged first.
- [x] 1.2 `ratatoskr-platform` at `f13a78587009f2a6bd5369e413e5f56b83141c0d`.
- [x] 1.3 `ratatoskr-extractor` at `da1247ae3f842ee9ad1550fc0afc8780b5a16026`.
- [x] 1.4 `ratatoskr-knowledge` at `3833d489d444270d854afa31e38dc87247d7e477`.
- [x] 1.5 `ratatoskr-channel-digests` at `a476079ec0115c38ab8c76e9280bf23a1ea89539`.
- [x] 1.6 `ratatoskr-github` at `dfb5a88090e9f84f1d9e48b27c47a8b7a1085c56`.
- [x] 1.7 `ratatoskr-vault` at `0a6c8d4700f7202633b5671e59341cb7d3f8bbc0`.
- [x] 1.8 `ratatoskr-x` at `f1810d5078eb688aa3715c2edb95e87e2d742e16`.
- [x] 1.9 `ratatoskr-instagram` at `956f0cb66c8357297db68140715f8413cd3f7adc`.
- [x] 1.10 `ratatoskr-threads` at `51b0fdd968ab4817b6bf2bf63a5f0174dd78855c`.
- [x] 1.11 `ratatoskr-chatgpt` at `c72a1faddb713afb43a95f44bb3f275c67789ac3`.
- [x] 1.12 `ratatoskr-claude` at `f3194364cac2a1bbf8f4483670c08195415c47ce`.
- [x] 1.13 `ratatoskr-telegram` at `b43c62554b61cd70f89f581887d5903d74cdff5e`.
- [x] 1.14 `ratatoskr-browser-extension` at `ff8bdd8e8816a499e34ba3aaefcfdd3879dea282`.
- [x] 1.15 `ratatoskr-export-agent` at `da1acd41f20ce972b7530aad9c231ba7bd9b4a6c`.
- [ ] 1.16 `ratatoskr-workspace`, last: specs, port table, the two harness checks, the changeset record and the pins. Committed locally on `main`; closes when it is published, which is outside the step that wrote it.

## 2. The cross-repository behaviour is recorded

- [x] 2.1 Write the five capability specs and the added `blob-references` requirement from the contract sections. No test: documentation. `openspec validate --all --strict` is the gate.

## 3. The port table is the complete allocation

- [x] 3.1 Add `harness/crates/workspace-core/tests/port_allocation.rs::the_ports_table_is_unique_and_covers_every_documented_listener`. Run against the previous table it failed with the assertion `the Ports table does not allocate these documented listeners: [8098, 8222, 9081, 9082, 9083, 9084, 9085, 9086, 9087, 9088, 9095, 9469, 9470, 9570]`.
- [x] 3.2 Rewrite the `## Ports` table of `docs/DEPLOYMENT_TARGET.md`, add the NATS monitoring row, the monitoring-bridge paragraph, the NATS bind description, the Telegram blob root and its group. The test of 3.1 passes.

## 4. No two listeners claim one port

- [x] 4.1 Add `port_allocation.rs::no_two_deploy_examples_bind_the_same_port_and_every_bind_is_allocated`, with the matcher checked against the real example files and the matches recorded in the file's header comment. Run against the previous pins it failed with `port 9467 is claimed by extractor ... and by telegram ...` and with the unallocated `9469` and `9570`.
- [ ] 4.2 The test passes against the advanced pins (task 7.1). No production code: the test is the deliverable, and the manifest-path resolution it needs is `workspace-core`'s manifest loader.

## 5. The bus permissions cannot drift

- [x] 5.1 Add `harness/crates/workspace-core/tests/bus_acl.rs` with `platform_conf_has_exactly_the_thirteen_identities`, `every_service_fragment_equals_its_platform_stanza`, `extractor_permissions_conf_is_gone` and `non_edge_stanzas_obey_the_permission_invariants`. Run against the previous pins all four failed: seven identities found, six service copies missing, `extractor-permissions.conf` present, and eighteen fixed durables without their consumer-info permission.
- [ ] 5.2 The four tests pass against the advanced pins (task 7.1). No production code: a plain-text splitter in the test file.

## 6. The changeset is recorded

- [ ] 6.1 Write `changesets/XR-021-fleet-cross-repo-fixes.yaml` with every child commit, the rollout, the rollback and the verification actually run. No test: documentation.

## 7. The pins advance

- [ ] 7.1 Move fifteen gitlinks to the pushed heads, add the `vault` to `github` edge to `workspace.toml`, update `EXPECTED_PINS` in `harness/crates/workspace-cli/tests/committed_snapshot.rs`, and regenerate `workspace.lock` with `./ws lock generate --output workspace.lock`. No new test: generated and configuration files; the gates are `committed_workspace_is_complete_and_current`, tasks 4.2 and 5.2, `./ws manifest check`, `./ws lock check`, `./ws status` and `./ws doctor`.

## 8. Composed integration and verification

- [ ] 8.1 Run the profile contract tests under `integration/tests/` and attempt the composed profiles under `integration/`; record in the changeset what ran and, for each profile that could not start, exactly why. A profile that did not run is recorded as not run and never as passed.
- [ ] 8.2 Run `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --all-features --locked -- -D warnings` and `cargo test --workspace --all-features --locked` in `harness/`, `openspec validate --all --strict`, `openspec validate --archived` and `git diff --check`.
