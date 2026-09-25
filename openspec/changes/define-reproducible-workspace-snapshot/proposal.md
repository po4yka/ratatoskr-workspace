## Why

The workspace currently cannot identify or reproduce the compatible Ratatoskr fleet: the sixteen child checkouts are untracked local clones, while the semantic manifest, generated lock, gitlinks, and executable consistency gate do not exist. This makes `main` incapable of satisfying its documented invariant that it names one verified system snapshot.

## What Changes

- Add all sixteen product repositories as read-only Git submodules under their established `repos/` paths, pinned to the exact audited `main` revisions recorded by WS-013.
- Add `workspace.toml` as the semantic catalogue for repository identity, path, remote, kind, dependency edges, commands, contracts, deployment profiles, ownership, and security classification; commit SHAs remain outside the manifest.
- Add a Rust `ws` harness slice that parses and validates the manifest, inspects gitlinks and `.gitmodules`, computes a deterministic `workspace.lock`, reports drift, and rejects inconsistent or dirty baseline snapshots.
- Add the generated `workspace.lock` containing exact child SHAs plus deterministic contract/schema/generated-client digests available at the pinned revisions.
- Add CI and repository tests that prove manifest, `.gitmodules`, gitlinks, and lock agreement, deterministic lock generation, unique topology, acyclic dependencies, reachable pinned commits, clean baselines, and explicit failure on drift.
- Add WS-013 coordination state and update architecture, development, testing, quality-gate, and onboarding documentation from planned to implemented behavior.
- **BREAKING**: `repos/` changes from operator-created ignored clones to tracked submodule gitlinks. A fresh checkout must initialize submodules before workspace integration commands can use child files.

## Capabilities

### New Capabilities

- `workspace-snapshot`: Defines the authoritative, reproducible fleet snapshot and the validation behavior that keeps semantic metadata, gitlinks, and generated lock data consistent.

### Modified Capabilities

None.

## Impact

WS-013 touches only `ratatoskr-workspace` implementation and history. In dependency order, the pinned repositories are `ratatoskr-contracts`; the backward-compatible consumers `ratatoskr-platform`, `ratatoskr-extractor`, `ratatoskr-knowledge`, `ratatoskr-github`, and `ratatoskr-vault`; producers and integrations `ratatoskr-x`, `ratatoskr-instagram`, `ratatoskr-threads`, `ratatoskr-chatgpt`, `ratatoskr-claude`, and `ratatoskr-telegram`; clients `ratatoskr-web`, `ratatoskr-mobile`, `ratatoskr-browser-extension`, and `ratatoskr-export-agent`; and finally `ratatoskr-workspace`. No child repository receives a source change or branch, so there are no child merges; the workspace commit is the only merge and must land last.

The change adds a Rust workspace harness and its reviewed manifest/serialization/hash/CLI dependencies, a committed manifest and generated lock, sixteen gitlinks, CI checks, WS-013 changeset metadata, and documentation. Provider behavior, child application code, deployment, full task-worktree orchestration, PR automation, MCP, release tagging, and automatic merging stay outside this change.

Rollback before publication is deletion of the task branch/worktree. After publication, rollback is a normal revert of the workspace commit: it removes the gitlinks, manifest, lock, harness slice, and gate together and restores the explicitly non-reproducible bootstrap state; no child history or runtime data changes.
