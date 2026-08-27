## Context

See `proposal.md` for motivation. The v1 tombstone already carries the required subject, owner, and immutable evidence reference, and Knowledge already deletes by subject without branching on the reason string. The missing boundary is an honest owner-requested reason plus proof that the consumer accepts it before ChatGPT produces it.

## Goals / Non-Goals

**Goals:**

- Keep one event type and one contract major while adding the missing authority token.
- Prove consumer compatibility and producer atomicity in dependency order.
- Record exact rollback limits for irreversible privacy deletion.

**Non-Goals:**

- Implement Platform's account-erasure coordinator or change its contracts.
- Add Claude Archive production, client APIs, Compliance ingestion, or database migration tooling.
- Recreate deleted content during rollback.

## Decisions

### 1. Expand the existing reason vocabulary

`user_requested` is added to `AiArchiveTombstoneReason`. A new event would duplicate subject-deletion semantics, while `reconciliation_policy` would falsely describe the authority. The additive token preserves the existing payload and v1 event name.

### 2. Publish contracts, prove the consumer, then enable the producer

The repository order is contracts → Knowledge → ChatGPT → workspace verification. Knowledge's current deletion path is reason-independent, so its change is a contract-pin and integration-fixture proof rather than a second deletion implementation.

### 3. Use a non-sensitive audit blob as tombstone evidence

ChatGPT deletes the source archive bytes, so a source `BlobRef` cannot remain the deletion evidence. The producer stores a deterministic content-free audit document containing opaque operation/scope identifiers, category counts, and completion time; its immutable `BlobRef` is carried by tombstones. The audit document contains no source digest, content, title, filename, or external account reference.

## Risks / Trade-offs

- [An older exhaustive consumer rejects the new token] → Knowledge's pinned consumer and compatibility test land before production; other producers remain disabled for the token.
- [Blob evidence could accidentally retain private data] → schema/test fixtures restrict the audit blob to an allowlisted metadata shape and scan it for forbidden fields.
- [Rollback after deletion is misunderstood] → disable future production only; retain consumer support and never recreate derived state.

## Migration Plan

1. Contracts: add `user_requested`, fixtures, generated artifacts, compatibility evidence; gate, commit, merge, and push `main`.
2. Knowledge: advance the contract pin, prove scoped/replayed deletion with the new fixture; gate, commit, merge, and push `main`.
3. ChatGPT: advance the pin and implement plan item 9; gate, commit, merge, and push `main`.
4. Workspace: sync this delta, record exact child SHAs and checks available in the current bootstrap, validate OpenSpec, commit, merge, and push `main`.
5. Before step 3, rollback is normal revert in reverse order. After production, keep contract and consumer support; revert or disable only new producer requests.

## Implementation Evidence

- Contracts feature commit `66d9454737d86d93f49ead96c0f028c2aeda02ff` passed its full gate, published the `user_requested` fixture, and is reachable from remote `main`.
- Knowledge feature commit `8b884099407ee5e53739577b5134d8f17daa7635` passed its full gate, consumes the same contract pin, and proves scoped deletion, replay deduplication, sibling retention, and cross-tenant refusal. Its commit time precedes the producer commit.
- ChatGPT feature commit `154ff889cfe358fa8cfbe06a597c499d9a9cfbf1` passed formatting, deny, clippy, build, PostgreSQL 17 workspace tests, size, and OpenSpec gates before direct integration to remote `main`.
- `changesets/aiarch-009-privacy-deletion-lifecycle.yaml` records the exact compatible commits, rollout, rollback, privacy boundary, test evidence, and the absence of a workspace runtime harness in this architecture-bootstrap repository.
- Direct `main` pushes reported bypassed required status checks. Local gates and remote reachability are verified; hosted CI is not claimed.
