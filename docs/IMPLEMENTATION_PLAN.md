# Workspace implementation plan

> Status: Snapshot milestone implemented; later milestones proposed
> Last reviewed: 2026-08-30

## Milestones

1. Completed: define and validate format-v1 `workspace.toml` and `workspace.lock`.
2. Completed: materialize all sixteen product repositories as audited pinned submodules.
3. Completed for snapshot scope: implement `ws manifest check`, lock generate/check, status, and
   strict doctor. General graph and remote drift commands remain open.
4. Implement idempotent task worktree creation and verification.
5. Add repository command execution and structured results.
6. Add Claude Code and Codex adapters with one-writer enforcement.
7. Coordinate one real cross-repository changeset.
8. Add task-namespaced integration profiles. Started with the manual `web-operational` profile;
   general profile generation remains open.
9. Add PR reconciliation and release snapshots; deterministic lock generation is complete.
10. Expose read-only MCP resources before any mutating MCP tools.

## Implemented vertical slice

The semantic manifest describes all sixteen product repositories, Git gitlinks select exact audited
commits, the generated lock records normalized authority and pinned content digests, status is
read-only, and doctor is the strict local/hosted gate. Task lifecycle is the next vertical slice.

## Definition of Done

Requirements and threat controls are implemented; Git operations are tested; commands are bounded; no secrets appear in output; child checks pass; integration evidence is stored; docs and ADR status are updated.

Deferred: automatic merge, production deployment, broad MCP writes, and remote multi-tenant execution.
