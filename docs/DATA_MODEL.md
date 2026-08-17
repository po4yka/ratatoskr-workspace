# Workspace data model

> Status: Proposed  
> Last reviewed: 2026-08-17

This repository has no runtime PostgreSQL schema.

## Versioned state

- `.gitmodules` and gitlinks: exact child revisions.
- `workspace.toml`: semantic repository catalog, commands, dependencies, contracts, profiles, ownership, and classification.
- `workspace.lock`: generated resolved SHAs, contract digests, schema versions, and artifact metadata.
- `changesets/*.yaml`: logical change lifecycle, repository roles, rollout, rollback, and linked PRs.
- `agent-kit/`: neutral policies, roles, skills, and hooks.

## Ephemeral state

Ignored task directories contain worktrees, task context, command results, agent outputs, generated Compose overrides, and logs. They must be recoverable, bounded, and removable without changing authoritative pins.

## Constraints

- Repository IDs and paths are unique.
- Dependency graph is acyclic unless an explicitly supported edge type says otherwise.
- Lockfile is generated and never hand-edited.
- Changeset transitions are valid and append audit context.
- Secrets and provider data are forbidden.
- Release tags point to a fully validated lock and gitlink set.
