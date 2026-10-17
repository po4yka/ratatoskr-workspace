## 1. Plan and ownership

- [x] 1.1 Record OBS-029 ownership, bases, consumer order and rollback; verify clean assigned worktrees and strict OpenSpec. Planning and topology have no behavioral RED.

## 2. Implementation by repository

- [x] 2.1 `contracts`: publish the scoped reviewed change after its required local checks, record the full commit and successful CI in OBS-029. The owner authorizes direct main publication; no PR is required. Contract behavior uses section 3.
- [x] 2.2 `platform`: publish the scoped reviewed change after its required local checks, record the full commit and successful CI in OBS-029. The owner authorizes direct main publication; no PR is required. Behavior uses section 4.
- [x] 2.3 `channel-digests`: publish the scoped reviewed change after its required local checks, record the full commit and successful CI in OBS-029. The owner authorizes direct main publication; no PR is required. Pin-only metadata has no behavioral RED.
- [x] 2.4 `chatgpt`: publish the scoped reviewed change after its required local checks, record the full commit and successful CI in OBS-029. The owner authorizes direct main publication; no PR is required. Pin metadata has no behavioral RED. SEC-030 separately owns the approved ZIP update and filename checks.
- [x] 2.5 `claude`: publish the scoped reviewed change after its required local checks, record the full commit and successful CI in OBS-029. The owner authorizes direct main publication; no PR is required. Pin metadata has no behavioral RED. SEC-030 separately owns the approved ZIP update and filename checks.
- [x] 2.6 `extractor`: publish the scoped reviewed change after its required local checks, record the full commit and successful CI in OBS-029. The owner authorizes direct main publication; no PR is required. Pin-only metadata has no behavioral RED.
- [x] 2.7 `github`: publish the scoped reviewed change after its required local checks, record the full commit and successful CI in OBS-029. The owner authorizes direct main publication; no PR is required. Pin-only metadata has no behavioral RED.
- [x] 2.8 `instagram`: publish the scoped reviewed change after its required local checks, record the full commit and successful CI in OBS-029. The owner authorizes direct main publication; no PR is required. Pin metadata has no behavioral RED. SEC-030 separately owns the approved ZIP update and filename checks.
- [x] 2.9 `knowledge`: publish the scoped reviewed change after its required local checks, record the full commit and successful CI in OBS-029. The owner authorizes direct main publication; no PR is required. Pin-only metadata has no behavioral RED.
- [x] 2.10 `sites`: publish the scoped reviewed change after its required local checks, record the full commit and successful CI in OBS-029. The owner authorizes direct main publication; no PR is required. Pin-only metadata has no behavioral RED.
- [x] 2.11 `telegram`: publish the scoped reviewed change after its required local checks, record the full commit and successful CI in OBS-029. The owner authorizes direct main publication; no PR is required. Pin-only metadata has no behavioral RED.
- [x] 2.12 `threads`: publish the scoped reviewed change after its required local checks, record the full commit and successful CI in OBS-029. The owner authorizes direct main publication; no PR is required. Pin metadata has no behavioral RED. SEC-030 separately owns the approved ZIP update and filename checks.
- [x] 2.13 `vault`: publish the scoped reviewed change after its required local checks, record the full commit and successful CI in OBS-029. The owner authorizes direct main publication; no PR is required. Pin-only metadata has no behavioral RED.
- [x] 2.14 `x`: publish the scoped reviewed change after its required local checks, record the full commit and successful CI in OBS-029. The owner authorizes direct main publication; no PR is required. Pin-only metadata has no behavioral RED.
- [x] 2.15 `notes`: publish the scoped reviewed change after its required local checks, record the full commit and successful CI in OBS-029. The owner authorizes direct main publication; no PR is required. Behavior uses section 4.
- [x] 2.16 `site-sdk`: refresh the generated snapshots required by the new Sites and Platform descriptions, run its whole gate and independent review, publish and record successful CI. Generated copies and locks have no separate RED.
- [x] 2.17 `web`: refresh the Platform description and generated types, run its whole gate and independent review, publish and record successful CI. Generated copies and locks have no separate RED.
- [ ] 2.18 `workspace`: publish the scoped reviewed change after its required local checks, record the full commit and successful CI in OBS-029. The owner authorizes direct main publication; no PR is required. Workspace promotion uses section 6.

## 3. Contracts TDD (retained OBS-024 numbers)

- [x] 3.13 RED: add `write_request.rs::segment_that_ends_in_a_dot_or_a_space_is_refused` and `colon_is_refused`, invalid fixtures and path/target boundary cases; observe serde accepts the unsafe inputs and the generated schema also accepts them before implementation. Keep safe-name acceptance checks.
- [x] 3.14 GREEN: tighten `VaultWritePath` and regenerate outputs; verify both tests pass at serde and schema layers, including valid boundary names.
- [x] 3.15 RED: add `conflict.rs::raised_may_name_every_stale_path` and canonical `group-with-stale-paths.json`; observe the current serde and schema reject the optional field.
- [x] 3.16 GREEN: add the optional field to `ConflictRaised` and its wire mirror, generate schema and TypeScript, and verify the new fixture and every old fixture round trip. Add a malformed-path negative fixture and verify both layers refuse it.
- [x] 3.17 Run all contracts DEVELOPMENT gates, TypeScript compilation, generation determinism and API compatibility; inspect and bless only the expected API delta, run independent review, commit and push, then wait for all required CI. Generation and API baseline files have no separate RED.

## 4. Direct producer and consumer tests

- [x] 4.1 RED: in Platform `crates/operations/tests/notes_conflicts.rs`, add `a_group_conflict_with_stale_paths_is_applied`; on the old pin observe that the consumer refuses the event and no conflict result is recorded.
- [x] 4.2 GREEN: move Platform to the new contracts SHA; prove old and new events apply, and unsafe path/target requests are refused before enqueue. Run its full DEVELOPMENT gates, review and CI before Notes emission.
- [x] 4.3 RED: in Notes `services/notes/tests/link_rewrite_atomic.rs`, add an event-list assertion to `a_group_base_mismatch_names_the_local_hash_of_each_file`; observe the old producer emits no `stale_paths`.
- [x] 4.4 GREEN: move Notes to the new contracts SHA and emit the existing group stale list without changing single-file event bytes; verify the event and read API contain the same list, plus the full Notes gates, review and CI.

## 5. Fleet and client acceptance

- [x] 5.1 Move each remaining Rust consumer manifest and tracked lock to the one contracts SHA, preserving other dependencies. Run every repository gate and source-size checks; review each scoped diff and wait for successful CI. Pin-only changes have no behavioral RED.
- [x] 5.2 Inspect each client snapshot input and pin policy. Run the relevant Web conflict, Plugin path and Export Agent path tests. Refresh a client copy only if its declared inputs or pin policy require it; generated metadata has no separate RED. Record exact tests and any unavailable live evidence.

## 6. Snapshot promotion

- [x] 6.1 Prove the combined proposed commits pass the disposable Notes/Platform/Sites integration profile, including command refusal and conflict propagation; record the exact revisions and teardown result.
- [x] 6.2 Stage task-root gitlinks to successful child commits, update the XR-021 contracts source and committed-snapshot expectations, generate workspace.lock twice and compare bytes. Pin and generated configuration have no separate RED; retain the contracts drift guard.
- [x] 6.3 Run workspace fmt, clippy, all tests, deny, doctor, lock check, strict current and archived OpenSpec, and applicable disposable provisioning acceptance. Inspect the final diff and independent source reviews before publication.
- [ ] 6.4 Publish the verified workspace snapshot and wait for every required CI check. Record full SHAs, rollout/rollback and the final snapshot; update OBS-024 3.13–3.16 only with observed evidence, keep unrelated deferrals open, and verify clean baseline submodules and protected user files.

## 7. CI projection timing correction

- [x] 7.1 Extract the operation-result poll predicate without behavior changes and run the existing HTTP tests. This refactor has no new RED.
- [x] 7.2 RED: add an HTTP regression that returns an omitted list, an empty list, unrelated results, then the exact conflict result. Observe failure because the pending response omits `results`.
- [ ] 7.3 GREEN: keep polling when `results` is absent; preserve exact conflict matching and malformed-item failure. Run all HTTP/profile contract tests and the real combined profile, review, publish and wait for all workspace CI.
