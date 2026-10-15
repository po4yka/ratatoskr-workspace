# Workspace ADRs

> Status: Proposed  
> Last reviewed: 2026-08-20

Use `docs/adr/NNNN-short-title.md`. Status values: Proposed, Accepted, Rejected, Deprecated, or Superseded.

Each ADR contains context, decision drivers, considered options, decision, consequences, security/privacy, compatibility/migration, validation, and follow-up. Accept an ADR before implementation depends irreversibly on it; supersede rather than rewrite history.

## Initial backlog

- ADR-0001: Multi-repository superproject versus monorepo.
- ADR-0002: Git submodules as compatible snapshot mechanism.
- ADR-0003: Task worktrees and one-writer rule.
- ADR-0004: Manifest and lockfile source-of-truth split.
- ADR-0005: Neutral agent-kit and generated Claude/Codex configuration.
- ADR-0006: Changeset lifecycle and release snapshot semantics.
- ADR-0007: Read-only-first workspace MCP boundary.

## Accepted

- [ADR-0008](0008-openspec-and-test-first.md): OpenSpec as the planning layer, and a test-first task shape.
- [ADR-0009](0009-ansible-for-the-single-host.md): Ansible provisions the single host from pinned, attested artifacts.
- [ADR-0012](0012-content-delivery-api-description-in-sites.md): The Content Delivery API description lives in `ratatoskr-sites`, and the site SDK pins it with a digest lock.

## Proposed

- [ADR-0010](0010-notes-and-obsidian-vault-connections.md): A notes service connects Obsidian vaults through one channel each (Sync, plugin or CLI).
- [ADR-0011](0011-independent-sites-on-the-single-host.md): Independent sites read releases through a public API and run on the host.
