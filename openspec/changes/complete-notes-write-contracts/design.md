## Context

See proposal.md for the scope. Contracts is pinned at 66bdb0c; its current main 7424416 only adds the Tokio lock update. `VaultWritePath` has one regex used by both serde and the generated schema. `ConflictRaised` uses a strict private deserialize mirror and schema branch transforms. Platform reads it strictly. Notes stores the stale list and returns it from the conflict API, but its event has only the first path.

## Goals / Non-Goals

Goals: complete OBS-024 3.13–3.16 with observed RED before each implementation; prove consumer acceptance and producer output; retain a reproducible fleet snapshot.

Non-goals: real Sync/MFA tests, production deployment, database changes, unrelated dependency updates, archiving OBS-024 or changing unknown-field policy.

## Decisions

1. Keep one regex for `VaultWritePath`. Tighten segment end and colon rules in that regex, so the parser and schema use identical rules. Retain the explicit first-segment configuration exclusion. A second service-only validator would leave the contract inconsistent; a new dependency or shared macro refactor is unnecessary.
2. Add `Option<Vec<VaultPath>>` to the public conflict payload and its private wire mirror, with default and omission for `None`. Keep existing optional-field null handling. Do not invent list order, uniqueness or cardinality validators beyond OBS-024; the Notes producer already selects an ordered nonempty stale group. `path` remains the first item emitted by that producer. The schema uses an equivalent `anyOf` for the optional typed array. The TypeScript projector intentionally refuses non-primitive array-form `type` values, so the field schema uses the existing supported representation without changing that safety rule. The old valid fixtures must remain byte-canonical. Add registry field metadata for the new private path data and bless only the expected public API difference.
3. Release the strict Platform conflict consumer first. Contracts and Platform can land while Notes still emits the old form. Source inspection finds no other conflict-event reader in the fleet; pin-only consumers can run alongside Notes after Platform CI, and all must pass before pins. Platform tests must prove the expanded event applies. Update all Rust contracts references and locks to one SHA, without sibling path dependencies. Notes then adds the optional field initialization and emits its existing persisted stale list in the same transaction as the conflict. No storage definition changes are needed.
4. Inspect generated client snapshots by their declared input set. Refresh only copies whose inputs or source-pin policy require it. Platform publishes the new write-path schema in OpenAPI. Sites publishes raw contract references at its Cargo pin, so the SDK must refresh its contracts lock and both API descriptions together. Refresh the Web Platform snapshot as the direct write client. Mobile uses the unchanged GitHub subset; Plugin and Export Agent keep their independent device-operation shapes. Existing Web conflict lookup and Plugin/Export Agent file-name guards remain acceptance checks; no real Sync account is available.
5. Use task worktrees under `.workspaces/obs029/`, with root as the only writer for each repository. Pin the exact CI-green commits. Root OpenSpec uses the nearest local root in the isolated workspace, as confirmed by `context --json`; the registered primary store remains untouched until verified publication.

## Risks / Trade-offs

- Tightened validation refuses formerly accepted names → adapters already refuse those names; test each write path and target, and preserve valid hidden names, dots and internal spaces. This is a first-major development correction explicitly requested in OBS-024.
- Old strict consumers reject the added field → publish and verify Platform before Notes. Preserve absence in old fixtures. Roll back the producer first; replay of new events requires an expanded consumer.
- Fleet pin-only updates have broad build cost → use each repository's own gate with isolated test services and the machine build gate. Preserve every unrelated upstream commit and dirty worktree.
- Synthetic device results do not prove Obsidian Sync → label that boundary and keep OBS-024 6.7 open.

## Migration Plan

Publish contracts after TDD, generation, compatibility and review. Wait for its CI. Expand Platform and wait for its CI, then complete Notes producer TDD and CI. Validate the unrelated pin-only Rust consumers alongside that chain. Refresh any required client metadata. Validate the exact proposed snapshot in the disposable integration profile and the workspace gates. Advance gitlinks, regenerate the lock deterministically, publish the workspace and wait for all CI. Record SHAs, checks and rollback in OBS-029. If a gate fails, stop promotion. After publication, use a separately verified corrective snapshot that retains SEC-030 ZIP fixes. Stop new Notes emission first and keep the expanded Platform reader while stale_paths events can replay. Do not restore ZIP 8.6.0 as a normal rollback release. No production operation is authorized.
