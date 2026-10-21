## Context

> **Owner acceptance decision, 2026-10-21.** The owner removed real Obsidian Sync acceptance from the completion criteria on 2026-10-21. This includes the MFA test environment, live propagation and race checks, recorded-session replay, and the resource, login, token and directory-mode checks that require that environment. Affected tasks close by this scope decision. These checks were not run. Product behavior, authentication, existing automated tests and the recorded TDD exceptions do not change. OBS-024 is complete under these criteria. The owner also removed physical iOS checks and written support answers from acceptance. Those iOS checks were not run and the replies were not received. Tasks 3.4 and 3.5 close by this decision, and OBS-023 is complete.

See proposal.md. The initial workspace snapshot was `d1963abf88ff2134d141d2210b95a47d814e9aa7`; Export Agent is `e4be3b4fd54d17f85e9952097f1ded38f031d801`. At that snapshot, OBS-024 retained 6.7 and aggregate 1.2. The owner acceptance decision above supersedes that status. OBS-029 closed the separate contracts work. Old CLI records retain twelve empty responses. The owner approved the existing Keychain test with fake values on 2026-10-17.

## Goals / Non-Goals

Goal: give each remaining local acceptance gap observed evidence or an exact local blocker. Keep the historical evidence limits and TDD exceptions. Apply the owner decision of 2026-10-21 to remove real Sync acceptance gates.

Non-goals: new product behavior without a reproduced defect, personal vault or account access, Sync/MFA, iOS, support mail and production operations.

## Decisions

1. Use `.workspaces/obs031/workspace` and `.workspaces/obs031/repos/export-agent`, with root as the only writer. Preserve the baseline and prior evidence. Export Agent is an acceptance subject; edits require a confirmed defect and a local OpenSpec plan first.
2. Download the same official signed Obsidian 1.14.4 installer. Check the release SHA-256 and Apple signature before execution. Use a new profile and a copy of synthetic fixture notes. Do not reuse the personal app profile. No installer, app or test vault is committed.
3. Retry the twelve unanswered commands with finite per-call and total limits. Keep their raw stdout, stderr and status. Compare resolved links/backlinks with the engine fixture and typed tag/property outputs with the fixture metadata. A blank stdout is not proof of an empty result. Positive controls must answer. Keep an unanswered command open after the bound.
4. Run the existing opt-in Keychain test through build-gate. It uses an unpredictable service UUID and explicit fixture values. Check its result and deletion. No password prompt is automated. If the environment refuses access, record that refusal and continue independent CLI acceptance.
5. Existing investigations and documentation have no new behavioral RED. If a check exposes a product defect, stop implementation until a local plan and an observable failing regression exist. Do not manufacture a behavior change to obtain a RED result.
6. Run required gates for any changed child and its exact-commit CI before a pin. If validation finds no child defect, confirm the existing pinned snapshot instead. Publish the workspace record and wait for every expected and observed CI check.

7. Inspect the published Headless parser without executing it. Verify its archive against the committed npm integrity first, then compare its option declarations with the current Notes units. This can establish syntax, not real Sync effects.

## Risks / Trade-offs

- CLI silence can mask a transport failure: preserve raw responses, use positive controls and require explicit output.
- App state can mutate fixture files: use a new synthetic copy and retain its before/after hashes. Stop only the owned process.
- Keychain access can require UI: use only the approved existing test; retain failures and ask for any additional access.
- Shared build and disk limits: use build-gate and measure free space before heavy work. Preserve foreign jobs and caches.

## Migration Plan

No runtime change is planned. Publish any confirmed and reviewed child fix first, then validate and publish compatible pins. For records only, retain the current child pins and deterministic lock. Rollback is an additive record correction; a product fix must define its own rollback before code changes.
