## 1. Implementation by repository

- [x] 1.1 `export-agent`: run the approved existing local Keychain check and CLI-backed acceptance at the exact pinned source; record command, test count, failures and cleanup. No new RED: acceptance of existing behavior. If a child fix is needed, add its local OpenSpec and a RED/GREEN pair before code, then require full gates, review and CI before pins.
- [ ] 1.2 `workspace`: publish the reviewed acceptance record after local checks and wait for every expected and observed CI check. Use the owner-authorized scoped commit and push workflow. Record exact child SHAs, pin decision and retained deferrals. No RED: documentation and snapshot metadata.

## 2. Local acceptance

- [x] 2.1 Reconcile all open OBS-024 and linked OBS-023 tasks against the current snapshot; record which need Sync, iOS or written support answers. Verify the checklist against the source task lists. No RED: investigation.
- [x] 2.2 Verify the official 1.14.4 installer digest and app signature; use a separate synthetic vault/profile and check the twelve unanswered CLI responses with bounded calls and explicit positive controls. Record exact output comparisons or remaining failures. No RED: recheck of an existing external tool.
- [x] 2.3 Run `RATATOSKR_KEYCHAIN_INTEGRATION=1 build-gate -- swift test --filter DeviceCredentialStoreTests.testMacOSKeychainRoundTripAndDelete` in the assigned Export Agent worktree. Record a real result, not a skipped test, and retain the fake-record cleanup result. No RED: owner-approved existing integration test.
- [x] 2.4 Recheck the production write adapter with the real isolated CLI and synthetic Notes peer. Verify exact bytes, result hashes and local cleanup; retain the declared synthetic boundary. No RED: existing acceptance check.

- [x] 2.5 Inspect the exact Headless 0.0.14 parser from the integrity-pinned published archive and compare the Notes unit mode/conflict flags. Record this as static syntax evidence only, with no account access or Sync claim. No RED: investigation of the existing external tool.

## 3. Verification and publication

- [x] 3.1 Run applicable workspace checks, strict current and archived OpenSpec, deterministic lock, manifest, doctor and final diff review. Check all baseline submodules and protected user files. No RED: validation only.
- [ ] 3.2 Publish the scoped record, wait for exact-commit CI, then update the primary checkout and verify its lock, pins and cleanliness. Keep OBS-024 6.7 and aggregate 1.2 open until real Sync evidence exists. No RED: publication metadata.
