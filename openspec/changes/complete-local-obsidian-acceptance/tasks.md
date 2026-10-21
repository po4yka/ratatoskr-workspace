## 1. Implementation by repository

- [x] 1.1 `export-agent`: run the approved existing local Keychain check and CLI-backed acceptance at the exact pinned source; record command, test count, failures and cleanup. No new RED: acceptance of existing behavior. If a child fix is needed, add its local OpenSpec and a RED/GREEN pair before code, then require full gates, review and CI before pins.
- [x] 1.2 `workspace`: publish the reviewed acceptance record after local checks and wait for every expected and observed CI check. Use the owner-authorized scoped commit and push workflow. Record exact child SHAs, pin decision and retained deferrals. No RED: documentation and snapshot metadata.

## 2. Local acceptance

- [x] 2.1 Reconcile all open OBS-024 and linked OBS-023 tasks against the current snapshot; record which need Sync, iOS or written support answers. Verify the checklist against the source task lists. No RED: investigation.
- [x] 2.2 Verify the official 1.14.4 installer digest and app signature; use a separate synthetic vault/profile and check the twelve unanswered CLI responses with bounded calls and explicit positive controls. Record exact output comparisons or remaining failures. No RED: recheck of an existing external tool.
- [x] 2.3 Run `RATATOSKR_KEYCHAIN_INTEGRATION=1 build-gate -- swift test --filter DeviceCredentialStoreTests.testMacOSKeychainRoundTripAndDelete` in the assigned Export Agent worktree. Record a real result, not a skipped test, and retain the fake-record cleanup result. No RED: owner-approved existing integration test.
- [x] 2.4 Recheck the production write adapter with the real isolated CLI and synthetic Notes peer. Verify exact bytes, result hashes and local cleanup; retain the declared synthetic boundary. No RED: existing acceptance check.

- [x] 2.5 Inspect the exact Headless 0.0.14 parser from the integrity-pinned published archive and compare the Notes unit mode/conflict flags. Record this as static syntax evidence only, with no account access or Sync claim. No RED: investigation of the existing external tool.

## 3. Verification and publication

- [x] 3.1 Run applicable workspace checks, strict current and archived OpenSpec, deterministic lock, manifest, doctor and final diff review. Check all baseline submodules and protected user files. No RED: validation only.
- [x] 3.2 Publish the scoped record, wait for exact-commit CI, then update the primary checkout and verify its lock, pins and cleanliness. OBS-024 6.7 and aggregate 1.2 are complete under the owner acceptance decision of 2026-10-21; no real Sync evidence is required. No RED: publication metadata.

## 4. Owner acceptance criteria update

- [x] 4.1 Apply the owner decision of 2026-10-21 across the three active plans, task lists, changesets and current acceptance records. Remove the real Sync/MFA and race gate; close dependent tasks by scope decision and retain the original evidence limits. Check strict current and archived OpenSpec, YAML, exact task dispositions, unchanged pins and lock, protected files and the final diff. No RED: documentation and owner acceptance criteria only.

- [x] 4.2 Apply the final owner acceptance decision of 2026-10-21: remove physical iOS and written support replies as completion gates, close OBS-023 3.4 and 3.5, and set OBS-023 complete. Reconcile the three plans, changesets, ADR, historical spike and acceptance records. Verify strict OpenSpec, YAML, no open tasks in OBS-023/024, unchanged pins and deterministic lock, protected files and the final diff. No RED: documentation and owner acceptance criteria only.
