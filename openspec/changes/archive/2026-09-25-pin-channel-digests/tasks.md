## 1. Implementation by repository

- [x] 1.1 `ratatoskr-workspace` — the only repository written; `ratatoskr-channel-digests` is a read-only pinned input. Implemented and committed on the task branch `feat/ws-fleet-init`; publishing the branch and opening the pull request is the owner's step, outside this change's authorization.

## 2. The harness requires channel digests

- [x] 2.1 Add `channel-digests` to `REPOSITORY_IDS` in `harness/crates/workspace-core/tests/support/mod.rs` and `tests/support/manifest.rs`, raise `git_topology.rs::manifest_gitmodules_and_gitlinks_agree` to seventeen pins, add `channel-digests` to the expected order in `dependencies.rs::valid_graph_has_stable_order`, and add `("channel-digests", "repos/integrations/channel-digests", <origin/main>)` to `EXPECTED_PINS` in `harness/crates/workspace-cli/tests/committed_snapshot.rs`. Run `cargo test --locked`: `complete_fleet_manifest_is_accepted` must fail with `manifest.repository.unexpected` for `channel-digests`, and `committed_workspace_is_complete_and_current` must fail on the repository count.
- [x] 2.2 Add `channel-digests` to `REQUIRED_REPOSITORIES` in `harness/crates/workspace-core/src/lib.rs`; the fixture tests from 2.1 pass and `committed_workspace_is_complete_and_current` still fails, now because the committed manifest lacks the entry.

## 3. The committed snapshot pins channel digests

- [x] 3.1 Add the `workspace.toml` entry and the submodule at `repos/integrations/channel-digests`, and regenerate `workspace.lock` with `./ws lock generate --output workspace.lock`. No new test: these are configuration and a generated file, and their test is 2.1's `committed_workspace_is_complete_and_current`, which must now pass along with `./ws manifest check`, `./ws lock check`, `./ws status` and `./ws doctor`.

## 4. Documentation and verification

- [x] 4.1 Update `README.md`, `DEVELOPMENT.md`, `docs/ARCHITECTURE.md`, `docs/REQUIREMENTS.md` and `docs/TESTING.md` where they list or count the pinned repositories. No test: documentation.
- [x] 4.2 Run `cargo fmt --check`, `cargo clippy --all-targets --locked -- -D warnings` and `cargo test --locked` in `harness/`, `openspec validate --all --strict`, `openspec validate --archived` and `git diff --check`.
