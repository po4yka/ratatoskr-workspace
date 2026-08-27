## Context

See `proposal.md` and the `ai-archive-analysis-intake` delta. The published AI-archive crate now
carries import, project, conversation, Artifact, tombstone, and archive-analysis completion facts.
Knowledge admits all lifecycle envelopes, analyses conversations, retains project/Artifact
receipts, and removes derived conversation data on authoritative tombstones.

## Goals / Non-Goals

**Goals:**

- Establish one independently interpretable fact shape for each normalized subject revision.
- Make provenance and current-result selection deterministic across at-least-once delivery.
- Propagate explicit removal to Knowledge without conflating it with source-archive retention.

**Non-Goals:**

- Changing provider acquisition, parsing, or raw BlobStore ownership.
- Giving Knowledge Claude credentials, raw export bytes, or write access to archive schemas.
- Inferring deletion from snapshot absence or specifying model/provider analysis internals.

## Decisions

### State-carried facts instead of ordered import replay

Each add/update includes its complete normalized subject and provenance. This lets Knowledge admit a
delayed event without reading producer storage or relying on a bus replay window. The alternative,
an import-reference-only event, would not meet the standalone or export-digest provenance boundary.

### Producer-owned revision linkage

Linkage checks use owner, archive id, subject kind/id, and normalized-content digest against the
immutable state-carried producer fact; that fact retains the raw export digest and parser stamp.
A Knowledge analysis-run id is intentionally not written back to the producer, because that would
couple archive persistence to Knowledge's implementation.

### Explicit tombstones

A single typed tombstone fact has a subject-kind discriminator so it covers projects,
conversations, and Artifacts without a parallel removal vocabulary. It carries a reason and
immutable evidence reference without claiming that raw evidence was deleted. The alternative of
using an absent next snapshot is rejected because exports can be partial.

## Risks / Trade-offs

- [Larger state-carried events expose more normalized content to the bus] → contract fixtures and
  authorization checks keep payloads limited to the normalized subject; raw bytes and credentials
  are prohibited.
- [Out-of-order delivery can race removal] → Knowledge retains deliveries but uses the tombstone as
  the current state and never re-projects an older source revision.
- [Contract and consumer changes must land together] → merge contracts first, then Knowledge, then
  producers; producers keep the new publisher disabled until Knowledge's intake is available.

## Migration Plan

1. `ratatoskr-contracts` adds typed payloads, envelope registrations, JSON-schema fixtures, and
   contract conformance tests.
2. `ratatoskr-knowledge` accepts the new facts, persists idempotency/linkage state, and proves
   search deletion on a removal fixture.
3. `ratatoskr-claude` publishes its outbox facts transactionally after normalized projections and
   tombstones are durable.
4. A future ChatGPT producer change adopts this already-published v1 interface independently.

Rollback stops Claude producer delivery while retaining raw exports and durable outbox/inbox
evidence; tombstones already accepted continue to suppress derived projections.
