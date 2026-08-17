# Workspace domain model

> Status: Proposed  
> Last reviewed: 2026-08-17

## Terms

- **Workspace snapshot:** exact child SHAs plus semantic and generated metadata.
- **Repository entry:** manifest record for a child repository, commands, dependencies, contracts, and profiles.
- **Changeset:** coordination record for one logical multi-repository change.
- **Task worktree:** isolated writable checkout assigned to one task and repository.
- **Agent run:** constrained plan, implementation, or review execution.
- **Integration environment:** task-namespaced cross-service runtime.
- **Release snapshot:** validated workspace commit and immutable tag.

## Lifecycle

`draft -> planned -> workspaces_ready -> implementing -> validating -> prs_open -> merged -> pinned -> released -> closed`

## Invariants

1. Baseline submodules are read-only.
2. One repository has at most one writer per task.
3. Every cross-repository change has a changeset.
4. Gitlinks, manifest, and lock describe the same snapshot.
5. Agents write only inside assigned worktrees.
6. Workspace `main` is always a validated compatible state.
7. Secrets never enter workspace metadata or agent context.

The harness owns Git topology and release coordination; agents own only the code changes in their assigned repositories.
