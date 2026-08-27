# Workspace implementation plan

> Status: Proposed  
> Last reviewed: 2026-08-27

## Milestones

1. Define and validate `workspace.toml` and `workspace.lock` formats.
2. Materialize current repositories as pinned submodules.
3. Implement `ws status`, `ws doctor`, graph, and drift reporting.
4. Implement idempotent task worktree creation and verification.
5. Add repository command execution and structured results.
6. Add Claude Code and Codex adapters with one-writer enforcement.
7. Coordinate one real cross-repository changeset.
8. Add task-namespaced integration profiles. Started with the manual `web-operational` profile;
   general profile generation remains open.
9. Add PR reconciliation, lock generation, and release snapshots.
10. Expose read-only MCP resources before any mutating MCP tools.

## First vertical slice

A manifest with two repositories is parsed; status reports pins; a task creates one worktree; one safe repository check runs; result and cleanup are durable and idempotent.

## Definition of Done

Requirements and threat controls are implemented; Git operations are tested; commands are bounded; no secrets appear in output; child checks pass; integration evidence is stored; docs and ADR status are updated.

Deferred: automatic merge, production deployment, broad MCP writes, and remote multi-tenant execution.
