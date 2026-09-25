## 1. Implementation by repository

- [x] 1.1 `ratatoskr-workspace` — the only repository written. Implemented and committed on the task branch `feat/ws-fleet-init`; publishing the branch and opening the pull request is the owner's step, outside this change's authorization.

## 2. Copying the fleet files

- [x] 2.1 Add `harness/crates/workspace-core/tests/support/fleet.rs` (temporary source and target fixtures) and `harness/crates/workspace-core/tests/fleet.rs` with `rust_target_receives_every_shared_generated_and_rust_file`, `non_rust_target_receives_dependabot_but_no_rust_files`, `class_mismatch_fails_and_writes_nothing`, `differing_file_is_a_conflict_unless_forced`, `second_run_changes_nothing`, `absent_source_files_are_reported`, `hand_written_required_files_are_reported`, `only_committed_content_is_copied` and `advisories_are_withheld_from_a_source_with_nested_rust`, calling `workspace_core::fleet_init` through a stub that returns an empty report. Run `cargo test --locked --test fleet`: each test must fail on its first content assertion (a missing copied path, a missing conflict, an empty missing list), not on compilation.
- [x] 2.2 Implement `fleet_init` in `harness/crates/workspace-core/src/fleet.rs`; the nine tests from 2.1 pass.

## 3. The command line

- [x] 3.1 Add `fleet_init_copies_and_reports_missing_files` and `fleet_init_conflict_exits_with_validation_status` to `harness/crates/workspace-cli/tests/commands.rs`. Run `cargo test --locked --test commands`: both must fail because `ws fleet init` exits 64 with the usage text.
- [x] 3.2 Add `ws fleet init <target-dir> [--from <dir>] [--force]` to `harness/crates/workspace-cli/src/main.rs`; the two tests from 3.1 pass.

## 4. Documentation and verification

- [x] 4.1 Document the command in `README.md`, `DEVELOPMENT.md`, `docs/ARCHITECTURE.md`, `docs/REQUIREMENTS.md` and `docs/TESTING.md`. No test: documentation.
- [x] 4.2 Run `./ws fleet init` against a scratch copy of a fleet repository, then `cargo fmt --check`, `cargo clippy --all-targets --locked -- -D warnings` and `cargo test --locked` in `harness/`, `openspec validate --all --strict`, `openspec validate --archived` and `git diff --check`.
