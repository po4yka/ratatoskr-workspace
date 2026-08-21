## Context

The shared Document IR and `BlobRef` contracts are already published. `ratatoskr-knowledge` has no
code or consumer yet. This change coordinates the first Knowledge slice without changing either
contract or introducing a public event.

## Goals / Non-Goals

**Goals:**

- Fix the source identity, grounding, version, validation, and evidence guarantees that another
  repository can rely on later.
- Keep the first implementation independently testable with a fake provider.

**Non-Goals:**

- A new shared Rust contract crate or event payload.
- Real inference providers, search, embeddings, indexing, backfill, or client rollout.

## Decisions

### Knowledge owns the first result type

The first article-analysis type is a strict provider-output and persisted-result contract inside
`ratatoskr-knowledge`. No other repository consumes it in this slice, so adding a shared contracts
crate now would be speculative. A later event or client API change must move the boundary shape into
`ratatoskr-contracts` under its own workspace change.

Alternative: publish an event contract now. Rejected because there is no consumer or event pipeline in
scope and no compatibility need yet.

### Existing source contracts merge first

Knowledge pins the already published identifier and Document IR packages. Extractor needs no change:
the source document identifier, digest, ordered blocks, and provenance already satisfy the input.

### One extra attempt is the whole initial budget

The initial request may use one further attempt for either an eligible transient failure or a
repairable validation failure. This proves both policies while preventing stacked retry and repair
loops. Real-provider work can revise the budget only with measured cost and failure evidence.

## Risks / Trade-offs

- [The internal result later differs from a public event] → Define the event only when its first
  consumer exists and classify compatibility then.
- [A fake provider misses transport behavior] → Keep transport outside this change; the real adapter
  must add its own timeout, rate, and error tests.

## Migration Plan

Merge and deploy `ratatoskr-knowledge` after its pinned contracts. No other repository changes.
Rollback stops the new service and removes its disposable development schema and owned blobs. No
published consumer, backfill, or production analysis data exists.
