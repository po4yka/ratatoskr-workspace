## Why

> **Owner acceptance decision, 2026-10-21.** The owner removed real Obsidian Sync acceptance from the completion criteria on 2026-10-21. This includes the MFA test environment, live propagation and race checks, recorded-session replay, and the resource, login, token and directory-mode checks that require that environment. Affected tasks close by this scope decision. These checks were not run. Product behavior, authentication, existing automated tests and the recorded TDD exceptions do not change. OBS-024 is complete under these criteria. OBS-023 tasks 3.4 (written support answers) and 3.5 (physical iOS) remain separate open work.

At the start of OBS-031, OBS-024 retained real Sync check 6.7 and aggregate Notes item 1.2. The local CLI and Keychain gaps were closed at snapshot 8012207. The owner decision of 2026-10-21 removes the real Sync criterion and completes OBS-024.

## What Changes

- Run the real signed Obsidian 1.14.4 CLI on a separate synthetic vault and profile. Recheck all twelve missing responses against the recorded engine outputs. Keep empty stdout unverified.
- Run the existing opt-in Keychain round-trip and delete test with the owner-approved UUID service and fake values only.
- Record exact commands, versions, results and cleanup. Correct stale status references after OBS-029. Apply the owner decision of 2026-10-21: real Sync-dependent acceptance is not required.
- If a defect appears, first add and run a behavioral RED test, then make the smallest scoped fix under a separate repository-local plan. No speculative behavior change is planned.

## Capabilities

### New Capabilities

None. This is an acceptance and documentation change; `skip_specs: true` applies.

### Modified Capabilities

None. Existing product contracts and requirements stay in force.

## Impact

Repositories: Export Agent is the subject of local validation; workspace owns the cross-repository acceptance record. A confirmed child fix must pass its local gates, review and exact-commit CI before workspace pins. With no child fix, the verified pins stay at their current SHAs. No dependency, database, protocol or deployment change is planned.

Outside scope: Sync/MFA, physical iOS, support messages, personal credentials and vaults, production hosts and the independent OBS-023 deferred work. Nothing has shipped in this wave. Documentation rollback is an additive correction; any later product fix must define its rollback before implementation.
