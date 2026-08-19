# Workspace documentation

> Status: Proposed  
> Last reviewed: 2026-08-19

- `ARCHITECTURE.md` — target superproject, harness, worktree, integration, and release architecture.
- `REQUIREMENTS.md` — functional and non-functional requirements.
- `DOMAIN.md` — workspace terminology, lifecycle, and invariants.
- `INTERFACES.md` — CLI, MCP, Git, GitHub, child-command, and integration boundaries.
- `DATA_MODEL.md` — manifest, lockfile, changeset, task, and release metadata.
- `THREAT_MODEL.md` — assets, trust boundaries, threats, and mitigations.
- `TESTING.md` — repository-local and workspace-level validation strategy.
- `IMPLEMENTATION_PLAN.md` — ordered vertical slices and Definition of Done.
- `DEPLOYMENT_TARGET.md` — **the one machine everything runs on**, and the storage, supervision, port
  and database contracts that follow from it. `Accepted`, and the first document to change when the
  host does.
- `QUALITY_GATES.md` — the static analysis, linters, CI and Git hooks that the 16 repositories have,
  the checks that were measured and rejected, and what arrives with the first code. `Implemented`.
- `adr/README.md` — ADR process and decision backlog.

Root documents: `README.md`, `AGENTS.md`, `DEVELOPMENT.md`, and `SECURITY.md`.

`Proposed` describes intended behavior; `Accepted` is approved design; `Implemented` requires code and passing evidence; `Deprecated` is retained for migration/history. Generated references should come from code or `workspace.toml`, not hand-maintained copies.
