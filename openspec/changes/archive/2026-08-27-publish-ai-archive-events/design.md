## Context

See [proposal.md](proposal.md) and the `ai-archive-event-lifecycle` delta.
The published `ratatoskr-ai-archive-contracts` crate now defines an import
fact, self-contained conversation added/updated facts, and a scoped tombstone
fact. It does not yet define project added/updated facts or a project tombstone
subject. Knowledge already has a durable archive-conversation inbox and family
pipeline, but no deletion intake or project flow for that family. ChatGPT has a
schema-level outbox but its reconciler does not yet enqueue external facts.

## Goals / Non-Goals

**Goals:**

- Publish one authoritative contract revision with self-contained, replay-safe
  import/conversation/project provenance and an explicit tombstone payload.
- Make contract fixtures the executable producer/consumer boundary.
- Give Knowledge a scoped, idempotent deletion path that removes only
  Knowledge-owned derivatives and leaves raw archive evidence with its owner.
- Give ChatGPT a contract conversion/outbox rule reusable by a future Claude
  producer change.

**Non-Goals:**

- Browser/session acquisition, inference work in either archive service, or
  direct access to Knowledge tables from a producer.
- Deletion from absence in an export, hard deletion of raw exports, and
  archive-wide retention-policy design beyond the authoritative tombstone fact.
- Transport/broker topology, public search UI, bulk reindexing, or asset event
  families; those need separately published contracts.

## Decisions

### D1: Make each conversation event independently evidence-linked

The contract will add a compact immutable import-provenance member to added and
updated conversation facts.  It carries the owning archive id, provider,
owner, raw `BlobRef` (including its digest), import completion time, and parser
name/version.  The consumer validates that it agrees with the embedded
conversation before durable admission.  Existing `AiArchiveImport` remains the
full import head and must agree with the repeated provenance.

An event-order-only join was rejected: a consumer that begins at a conversation
event or replays a retained message cannot verify raw provenance without an
earlier event.  Repeating a small immutable reference is less sensitive than
embedding export bytes and preserves state-carried transfer.

### D2: Add project facts and one explicit, scoped tombstone fact

`ratatoskr-ai-archive-contracts` will define project added/updated payloads
with the same immutable import provenance as conversations and a normalized
project content digest. It will extend the single
`ai_archive.subject.tombstoned.v1` fixture family with a typed project subject.
Every subject carries owner, provider, stable archive and subject identities,
deletion reason, evidence reference, observed time, and optional parser
name/version. The contract rejects a tombstone with a subject that is not in
its declared scope. It does not express `MissingFromLatestSnapshot`.

Separate archive, conversation, and project deletion event types were rejected: they
would duplicate evidence and deduplication rules while the subject reference
already makes the removal scope explicit.  A generic untyped `deleted` JSON
event was rejected because consumers could not validate the subject or prevent
cross-tenant removal.

### D3: Consumers retain receipt history and delete by source identity

Knowledge accepts every archive fact through its durable inbox keyed by event
identity. It records archive provenance beside both conversation and project
source identities, derives the deletion scope from the validated owner, archive
id, and subject reference, then atomically removes or makes unavailable every
Knowledge-owned source reference, analysis run/output, projection input, search
document, and embedding for that scope.  It writes a deletion audit receipt so
replay is a no-op.  A conversation tombstone is narrower than an archive
tombstone; tenant deletion remains Knowledge's existing explicit operation.

Marking only the visible search row deleted was rejected because retries or
reindexing could resurrect a derived result.  Deleting a producer BlobRef was
rejected because ownership stays with the archive context.

### D4: Producers convert reconciled observations into transactional facts

After a raw export is stored and reconciliation validates a normalized import,
each producer serializes the contract payloads and enqueues them with the same
commit that records the normalized state.  It emits one import fact followed by
one added or updated fact for every current conversation revision; redelivery
uses the durable outbox event identity.  A producer enqueues a tombstone only
from an explicit tombstone record and preserves the source evidence reference.

Publishing directly after reconciliation was rejected because a crash could
leave normalized state without a recoverable fact.  Inferring tombstones from
missing observations was rejected by the archive's snapshot semantics.

## Risks / Trade-offs

- [The repeated provenance fields can diverge from the import head] → Contract
  fixture and producer tests compare both payload forms before publishing; the
  consumer rejects a mismatched conversation fact.
- [An archive tombstone can cover many derived rows] → Knowledge scopes and
  batches its deletion transaction by source identity, records an audit receipt,
  and makes retries idempotent.
- [A producer update could arrive before the consumer deployment] → Rollout
  keeps tombstone publication disabled until the pinned Knowledge gate passes.
- [A malformed provider deletion signal is overly broad] → The producer accepts
  only the closed deletion-reason set and requires a typed subject plus evidence
  reference before enqueueing.

## Migration Plan

1. `ratatoskr-contracts`: add the payloads, validation, schema compatibility
   fixtures, and event conformance tests; publish the resulting revision.
2. `ratatoskr-knowledge`: pin that revision; add conversation/project inbox
   validation and scoped deletion tests/implementation; pass its family and
   search-deletion gates.
3. `ratatoskr-chatgpt`: pin the same revision; add RED contract-fixture,
   linkage, and tombstone-outbox tests before implementation; pass its full
   gate.  A Claude producer adopts the published contract in a separate change.
4. Advance fleet pins only after all three repositories report their named
   green gates.

Before step 3, rollback is to retain the currently published three facts.  Once
a tombstone is emitted, retain the event in the transactional outbox and retry
it until a compatible consumer records its deletion receipt; do not roll back
by resurrecting derived state.
