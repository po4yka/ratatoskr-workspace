## Why

The Knowledge process currently starts an admin listener, an indexer, and an optional channel-recap consumer, but it never opens the fleet's primary document and domain-event stream. Documents and events can therefore be published correctly while no durable Knowledge cursor accepts them, `/ready` still reports success, and an attempted direct wiring would lose admitted work or terminal facts across process crashes.

## What Changes

- Register the existing `content.document.extracted.v1` wire fact as a typed v1 contract while preserving its current envelope and `Document` payload shape.
- Have Platform pre-provision an exact-filter Knowledge pull durable on `ratatoskr_events`, the existing recap command durable, and a least-privilege Knowledge NKey. Knowledge verifies this topology and never creates or repairs it.
- Start a supervised Knowledge primary-event adapter for extracted documents, social source lifecycle facts, normalized AI-archive lifecycle facts, and repository-analysis requests.
- Persist envelope receipt, collision evidence, schedulable work, retry state, and terminal outbox state so acknowledgement, restart, redelivery, and inference retries cannot strand work or duplicate provider charges.
- Resume every persisted analysis state, apply social removals and AI-archive tombstones without stale resurrection, and publish Knowledge terminal facts from a transactional outbox with stable message identities.
- Make primary-bus connectivity, exact durable configuration, required analysis dependencies, and worker health part of readiness; drain or negatively acknowledge in-flight delivery before storage closes.
- Update Extractor to emit the registered typed document fact rather than constructing an unregistered event manually.
- Add an exact-SHA composed workspace profile that proves the real Extractor document path and canonical injected social, AI-archive, and repository paths through JetStream, Knowledge persistence/analysis/search, restart recovery, deletion suppression, and terminal publication.
- Deliver repositories in this order: `ratatoskr-contracts` first; `ratatoskr-platform` and the backward-compatible `ratatoskr-github` immutable-content read boundary next; `ratatoskr-knowledge` after those dependencies are available; `ratatoskr-extractor` after the typed contract is published; `ratatoskr-workspace` pins last after the combined profile passes.
- Keep live event publication work in X, Instagram, Threads, GitHub, ChatGPT, and Claude outside this change. Their canonical event injection is covered here, but their incomplete producer runtimes remain separately owned rollout dependencies and are not claimed as live end-to-end proof. The GitHub change here is limited to authenticated retrieval of an already-published immutable README reference.

Rollback stops upstream publication before stopping Knowledge, lets Knowledge drain bounded in-flight work and its terminal outbox, and preserves the Platform-owned durable cursor plus Knowledge inbox/work/outbox rows. The durable and stream are not deleted; child pins can then be rolled back in reverse dependency order without losing accepted work.

## Capabilities

### New Capabilities

- `document-extracted-event`: Defines the existing extracted-document fact as a canonical typed event without changing the v1 wire payload.
- `knowledge-main-event-stream`: Defines the exact Platform-owned consumer topology, accepted subject set, transport validation, acknowledgement boundary, readiness, and shutdown behavior for the primary Knowledge stream.
- `knowledge-analysis-work-recovery`: Defines durable admission, leased work, deterministic resume, tombstone suppression, terminal outbox publication, and replay behavior across all main analysis families.

### Modified Capabilities

None. Existing article, repository, social, and AI-archive analysis requirements retain their domain meaning; the new capabilities specify the missing shared runtime and durability behavior that makes those requirements executable.

## Impact

- `ratatoskr-contracts`: document event type, registry entry, schema, fixtures, and generated bindings.
- `ratatoskr-platform`: fixed consumer inventory, startup provisioning, NATS permissions and credential rendering, topology tests, and deployment documentation.
- `ratatoskr-github`: bounded owner-scoped immutable README read endpoint and service-auth policy; no event publisher change.
- `ratatoskr-knowledge`: config, event adapter, inbox/work schema definition, recovery scheduler, family pipelines, authenticated repository content resolution, general outbox publisher, readiness, metrics, shutdown, and tests.
- `ratatoskr-extractor`: typed document-event construction and contract pin.
- `ratatoskr-workspace`: KNO-018 changeset, task-namespaced integration profile, fault/replay fixtures, exact child SHAs, verification record, and final pins.
- No new major version, compatibility path, database migration, production dependency, secret, or direct cross-repository path dependency is introduced.
