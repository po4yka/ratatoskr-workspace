## Why

The published AI-archive contract now needs a completed rollout through Knowledge and Claude so
normalized project, conversation, Artifact, completion-linkage, and tombstone facts become
exercisable instead of contract-only.

## What Changes

- Publish complete, state-carried source facts and fixtures in `ai-archive-contracts`.
- Implement Claude Archive outbox publication and exact completion linkage.
- Implement Knowledge lifecycle admission, conversation analysis/search, and tombstone deletion.
- Define the rollout and rollback boundary for the three participating repositories.

## Capabilities

### New Capabilities

- `ai-archive-analysis-intake`: Contract-governed delivery, analysis linkage, search projection,
  and deletion propagation for normalized AI-archive source facts.

### Modified Capabilities

- None. The contract crate will begin its own implementation change against this agreed
  cross-repository interface.

## Impact

Merge in dependency order: `ratatoskr-contracts` first, `ratatoskr-knowledge` second, and
`ratatoskr-claude` third. ChatGPT is deliberately not a publisher in this change; it will use the
same v1 interface in a separate producer change. No consumer infers a tombstone from snapshot
absence. The change excludes provider crawling, archive-content inference by archive services,
raw-export transport, and direct cross-schema access. Rollback stops delivery while retaining raw
evidence and durable inbox/outbox records; no incomplete or inferred deletion is emitted.
