## 1. Manifest and dependency semantics

- [x] 1.1 Add failing tests `harness/crates/workspace-core/tests/manifest.rs::complete_fleet_manifest_is_accepted`, `duplicate_identity_is_rejected`, `commit_fields_are_rejected`, and `missing_required_repository_is_rejected`; assert that the absent parser/validator cannot yet accept the valid fixture and cannot produce the required complete diagnostics, then run the targeted test and observe the specified red failures.
- [x] 1.2 Add the Rust harness workspace, pinned toolchain, lockfile, lint/security policy, typed v1 manifest model, complete-fleet validation, and stable diagnostics; verify task 1.1 tests pass through `build-gate -- cargo test --manifest-path harness/Cargo.toml -p workspace-core --test manifest --jobs 4`.
- [x] 1.3 Add failing tests `harness/crates/workspace-core/tests/dependencies.rs::valid_graph_has_stable_order`, `unknown_dependency_is_rejected`, and `complete_cycle_is_reported`; assert the stable dependency order and full error/cycle values, then run the targeted test and observe red failures caused by missing graph behavior.
- [x] 1.4 Implement typed dependency edges, reference validation, deterministic topological sorting, and complete cycle reporting; verify task 1.3 tests pass through the gated targeted test command.

## 2. Git topology and baseline safety

- [x] 2.1 Add failing temporary-superproject tests `harness/crates/workspace-core/tests/git_topology.rs::manifest_gitmodules_and_gitlinks_agree`, `path_remote_and_mode_mismatches_are_reported`, and `uninitialized_submodule_reports_bootstrap_command`; assert exact mismatch values and no repository mutation, then run them red against the missing Git inspector.
- [x] 2.2 Implement bounded system-Git inspection of `.gitmodules`, index gitlink modes/SHAs, canonical public remotes, initialization state, and reachability without implicit fetch/checkout; verify task 2.1 tests pass through the gated targeted test command.
- [x] 2.3 Add failing tests `harness/crates/workspace-core/tests/baseline.rs::head_drift_is_reported`, `tracked_and_untracked_changes_are_reported`, and `inspection_never_mutates_a_dirty_child`; record HEAD, status porcelain, refs, and file contents before/after and observe red failures caused by missing baseline-health behavior.
- [x] 2.4 Implement read-only baseline status and strict health checks that distinguish uninitialized, HEAD drift, tracked dirt, and untracked dirt; verify task 2.3 tests pass and every before/after assertion is unchanged.

## 3. Deterministic lock and content evidence

- [x] 3.1 Add failing tests `harness/crates/workspace-core/tests/lock.rs::same_inputs_render_byte_identically`, `lock_has_stable_lexical_order`, `host_and_time_do_not_enter_lock`, and `stale_lock_reports_semantic_diff_without_rewrite`; run them twice with different temporary roots and environment values and observe the required red failures.
- [x] 3.2 Implement the v1 lock model, canonical TOML renderer, normalized manifest/`.gitmodules` SHA-256, semantic comparison, and atomic explicit output path; verify task 3.1 tests pass and two independently generated fixture locks have identical SHA-256.
- [x] 3.3 Add failing tests `harness/crates/workspace-core/tests/digests.rs::file_digest_reads_pinned_blob`, `directory_digest_is_canonical`, `missing_declared_path_fails`, `path_escape_fails`, and `non_blob_entries_fail_closed`; run the targeted test and observe red failures caused by missing pinned-object digesting.
- [x] 3.4 Implement SHA-256 evidence over declared files and canonical Git trees at the gitlink commit, with path validation and fail-closed type handling; verify task 3.3 tests pass through the gated targeted test command.

## 4. Operator CLI and hosted gate

- [x] 4.1 Add failing CLI tests `harness/crates/workspace-cli/tests/commands.rs::manifest_check_is_read_only`, `lock_check_rejects_stale_output`, `status_reports_without_repair`, `doctor_aggregates_snapshot_failures`, and `uninitialized_output_names_exact_bootstrap_command`; run the binary tests red before command implementations exist.
- [x] 4.2 Implement `ws manifest check`, `ws lock generate`, `ws lock check`, `ws status`, and strict `ws doctor`, stable exit codes, human diagnostics, and the root `./ws` launcher; verify task 4.1 tests pass and `git diff --exit-code` remains clean after every read-only command in a fixture.
- [x] 4.3 Add a failing repository test `harness/crates/workspace-cli/tests/ci_contract.rs::workspace_ci_initializes_and_verifies_snapshot`; assert that the absent workflow does not yet recursively initialize submodules or invoke `ws doctor`, then observe the red failure.
- [x] 4.4 Add `.github/workflows/ci.yml` with pinned actions, recursive public submodule checkout, Rust format/lint/build/test/security gates, and exact workspace doctor verification; verify task 4.3 passes and `actionlint`/`zizmor` checks available in the repository accept the workflow.

## 5. Materialize the audited fleet snapshot

- [x] 5.1 Add failing real-tree integration test `harness/crates/workspace-cli/tests/committed_snapshot.rs::committed_workspace_is_complete_and_current`; assert sixteen exact repository IDs, gitlinks, current audited SHAs, digest evidence, and a fresh lock, then observe failure because `workspace.toml`, `.gitmodules`, gitlinks, and `workspace.lock` are absent.
- [x] 5.2 Add `workspace.toml`, sixteen public HTTPS submodules at the WS-013 audited SHAs, explicit dependency/contract/profile/digest metadata, and generate `workspace.lock` only through `ws lock generate`; no separate test because these are configuration and generated artifacts whose behavior is the previously red test 5.1. Verify test 5.1, `./ws manifest check`, `./ws lock check`, `./ws status`, and `./ws doctor` all pass without changing any child HEAD or status.
- [x] 5.3 Add `changesets/WS-013-reproducible-workspace-snapshot.yaml` recording workspace ownership, all read-only pinned repositories, dependency order, exact SHAs, rollout, revert rollback, checks, proof boundaries, and final publication fields; no failing test because this is coordination configuration. Verify its repository IDs and SHAs mechanically against `workspace.lock`.

## 6. Documentation and full verification

- [x] 6.1 Update `README.md`, `DEVELOPMENT.md`, `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`, `docs/REQUIREMENTS.md`, `docs/IMPLEMENTATION_PLAN.md`, `docs/TESTING.md`, and `docs/QUALITY_GATES.md` to separate implemented snapshot behavior from later harness milestones and document clone/bootstrap/check/drift/rollback commands; no failing test because this is documentation. Verify every command shown exists and its help or non-mutating check runs successfully.
- [x] 6.2 Run `openspec validate define-reproducible-workspace-snapshot --strict`, `openspec validate --all --strict`, `openspec validate --archived`, `git diff --check`, shell syntax/static integration tests, existing workspace integration smokes available without provider credentials, and the complete Rust gate through one top-level `build-gate`; review the final diff for secrets, scope creep, gitlink mode `160000`, generated-lock freshness, dirty baselines, and accidental child edits. Record exact results in WS-013.

## 7. Implementation by repository

- [ ] 7.1 `ratatoskr-workspace` — stage only WS-013 paths and gitlinks, inspect the staged diff, commit with the repository's message convention, push the task branch, open the workspace pull request, wait for exact-SHA hosted checks, merge only when explicitly authorized, and record the PR URL plus merged commit in WS-013. No child repository PR exists because all sixteen children are read-only published snapshot inputs; verification is the exact remote branch/PR/main SHA and clean task worktree.
