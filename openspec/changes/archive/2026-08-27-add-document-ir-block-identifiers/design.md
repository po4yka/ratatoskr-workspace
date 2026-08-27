## Context

See proposal.md and the modified `document-ir` requirement. Current Document IR blocks are ordered
but unaddressable beyond their position. Knowledge stores immutable source revisions and needs a
first-version annotation anchor that names a specific block without claiming ownership of source text.

## Goals / Non-Goals

**Goals:**

- Give every block in one immutable Document IR revision a unique, serializable identifier.
- Make anchor validation deterministic across Contracts, Knowledge, and Extractor.
- Record dependency order, verification, and rollback for the affected repositories.

**Non-Goals:**

- Cross-revision highlight rebasing, source-text storage in Knowledge, a new major contract version,
  a compatibility layer, or an annotation-sharing protocol.

## Decisions

### Block identity is explicit in the shared type

`ratatoskr-contracts` adds a typed block identifier to every serialized Document IR block and validates
uniqueness within a document revision. Extractor allocates the identifier while building the document;
the value remains stable for the lifetime of that immutable revision. Knowledge treats it as opaque.
Using a block ordinal was rejected because a front insertion changes an otherwise valid anchor, while
a content hash was rejected because identical blocks need distinct addresses.

### Anchor validity binds both revision and text range

The shared contract defines offsets as Unicode scalar values and requires the consumer to check the
Document ID, content digest, block ID, and non-empty bounds against the supplied revision. It does
not prescribe a database table or an API. This preserves the bounded-context boundary: Knowledge owns
its highlights and Extractor owns source construction.

### Implementation order is contracts, consumer, producer, workspace snapshot

Contracts changes and tests land first. Knowledge then compiles against the new contract and validates
anchors but does not fetch source content. Extractor produces IDs as it emits Document IR. Workspace
pins advance only after child gates and a consumer/producer round-trip check pass. The development
status permits a direct first-version change; no old deployment or database data exists to migrate.

## Risks / Trade-offs

- [A producer emits duplicate IDs] → contract-level serialization and producer tests reject duplicate
  IDs before publication.
- [Different offset units across implementations] → name Unicode scalar values in the shared spec and
  use boundary fixtures containing multi-byte text.
- [A consumer accepts a document with another revision's text] → require both source document ID and
  content digest in the validated anchor tuple.

## Migration Plan

1. Implement and validate the contract change in `ratatoskr-contracts`.
2. Land this store specification and changeset record.
3. Implement and validate Knowledge's user-content consumer.
4. Implement and validate Extractor's block-ID producer.
5. Run the documented cross-repository round-trip, update workspace pins, and publish the verified
   snapshot.

Rollback before deployment is a coordinated revert of child commits and the workspace pin. No data
migration or compatibility route exists because the fleet is still in first-version development.
