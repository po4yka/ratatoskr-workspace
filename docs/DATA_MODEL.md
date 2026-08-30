# Workspace data model

> Status: Snapshot model implemented; task state proposed
> Last reviewed: 2026-08-30

This repository has no runtime PostgreSQL schema.

## Versioned state

- `.gitmodules` and gitlinks: exact child revisions.
- `workspace.toml`: semantic repository catalog, commands, dependencies, contracts, profiles, ownership, and classification.
- `workspace.lock`: generated format-v1 data containing normalized manifest and `.gitmodules`
  SHA-256, exact gitlink commits, remotes, default branches, and declared file/tree digests.
- `changesets/*.yaml`: logical change lifecycle, repository roles, rollout, rollback, and linked PRs.
- `agent-kit/`: neutral policies, roles, skills, and hooks.

## Ephemeral state

Ignored task directories contain worktrees, task context, command results, agent outputs, generated Compose overrides, and logs. They must be recoverable, bounded, and removable without changing authoritative pins.

## Constraints

- Repository IDs and paths are unique.
- Canonical remotes are unique and commits never appear in `workspace.toml`.
- Dependency graph is acyclic unless an explicitly supported edge type says otherwise.
- Gitlinks alone select commits; the manifest describes semantics and the lock is derived evidence.
- Lockfile is generated only by `./ws lock generate --output workspace.lock` and never hand-edited.
- Changeset transitions are valid and append audit context.
- Secrets and provider data are forbidden.
- Release tags point to a fully validated lock and gitlink set.
