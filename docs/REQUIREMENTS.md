# Workspace requirements

> Status: Proposed  
> Last reviewed: 2026-08-17

## Goals

1. Validate repository topology, commands, dependencies, contracts, profiles, and ownership from `workspace.toml`.
2. Pin exact compatible child revisions through gitlinks and a generated `workspace.lock`.
3. Create isolated task worktrees and enforce one writer per repository.
4. Coordinate changesets, checks, PRs, integration environments, and release snapshots.
5. Expose a constrained CLI and read-mostly MCP interface for coding agents.

## Non-goals

- Runtime domain data or provider credentials.
- Replacing child CI or merging all histories into a monorepo.
- Direct editing of baseline submodules.
- Unscoped agent Git or deployment access.

## Requirements

- Every cross-repository change has a changeset ID and explicit repository roles.
- Gitlinks, manifest, and lockfile must agree.
- Task preparation and cleanup are resumable and idempotent.
- Mutating commands require explicit task context and authorization.
- Child repositories remain independently cloneable, buildable, and testable.
- Contract rollout follows expand/migrate/contract.
- `main` represents a validated compatible snapshot.

## First-slice acceptance

- Parse and validate one manifest.
- Report repository and pin drift.
- Prepare and verify one task worktree.
- Run one repository-local check through the harness.
- Preserve audit output without secrets.
