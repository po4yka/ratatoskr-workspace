## Why

`ratatoskr-chatgpt` can reconcile normalized archive evidence but cannot safely
publish it to Knowledge: the published contract has imported, added, and updated
facts, but no tombstone fact.  That leaves downstream search unable to remove
derived results when authoritative deletion evidence arrives.

## What Changes

- Extend the published AI-archive event contract with an explicit, idempotent
  tombstone fact scoped to an archive or normalized graph entity and grounded in
  the producer's deletion evidence.
- Define the required event set and provenance for an imported archive and for
  added, updated, and tombstoned conversations and projects, including immutable export
  reference/digest and parser name/version.
- Define the Knowledge intake and deletion behavior: archive facts create or
  advance the current analysis/search source; a tombstone removes or tombstones
  every derived analysis and search projection for exactly that source without
  deleting producer-owned raw evidence.
- Define the rollout order, conformance fixtures, replay/out-of-order behavior,
  and rollback boundary for the shared contract and its producer and consumer.

## Capabilities

### New Capabilities

- `ai-archive-event-lifecycle`: Contract-bound publication and consumption of
  normalized AI-archive facts, including authoritative tombstone propagation.

### Modified Capabilities

- None.

## Impact

1. `ratatoskr-contracts` must add and publish project facts plus the tombstone
   payload, event types, JSON-schema compatibility fixtures, and package revision first.
2. `ratatoskr-knowledge` must pin that revision and implement durable
   tombstone intake/deletion for its AI-archive analysis and search family
   second.
3. `ratatoskr-chatgpt` must pin the same revision and enqueue the defined
   import, conversation, project, and tombstone facts from its transactional outbox
   third.  Claude producer rollout is outside this ChatGPT change.
4. Fleet integration pins the proven producer and consumer revisions last.

No consumer relies on the tombstone event before its contract dependency is
published, so rollback before producer rollout is to retain the existing three
facts and leave derived archive search unchanged.  After a producer publishes a
tombstone, rollback is not a safe replacement for the consumer: replay of the
idempotent fact must remain available until the consumer has applied it.  No
contract or producer behavior has shipped from this change yet.
