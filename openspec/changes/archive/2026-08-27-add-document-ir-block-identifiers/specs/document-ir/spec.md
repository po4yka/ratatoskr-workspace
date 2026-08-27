## MODIFIED Requirements

### Requirement: Version one is the shared intersection

The Document IR published by `ratatoskr-contracts` SHALL carry only what an extracting service
produces and an analysing service consumes: the document's identity, the address it came from, a
content digest, an optional title and language, an ordered sequence of typed blocks with stable block
identifiers, and provenance naming which strategy produced it and from which stored blob. Anything a
single service needs and no other reads SHALL stay inside that service. A block identifier SHALL be
unique and stable within its immutable document revision. The contract SHALL not define
cross-revision identifier mapping or annotation rebasing.

#### Scenario: an extracted document round-trips between two repositories

- **WHEN** an extracting service serializes a document as Document IR and an analysing service
  deserializes it
- **THEN** the analysing service reads the block identifiers, blocks, digest and provenance without
  consulting the extracting service's own tables

#### Scenario: repeated blocks are distinguishable

- **WHEN** one Document IR revision contains two blocks with identical text
- **THEN** each block has a distinct stable identifier that a consumer can use as an annotation anchor

#### Scenario: a service-private field does not enter the shared shape

- **WHEN** a change proposes adding a field to Document IR that only one repository reads
- **THEN** the field belongs in that repository's own storage and the change is refused

### Requirement: Annotation anchors validate the supplied immutable revision

A consumer that accepts a text annotation SHALL validate the tuple `(document_id, content_digest,
block_id, start_offset, end_offset)` against the supplied Document IR revision. Offsets SHALL count
Unicode scalar values in the referenced block text, and an annotation range SHALL satisfy `0 <=
start_offset < end_offset <= block_text_length`. The consumer SHALL reject an unknown block,
mismatched revision, or invalid range without treating the source text as an instruction.

#### Scenario: a valid range names one block

- **WHEN** a consumer receives a non-empty range whose offsets are within a block of the supplied
  immutable Document IR revision
- **THEN** it can persist the annotation anchor using that document digest and block identifier

#### Scenario: a revision mismatch cannot validate an anchor

- **WHEN** a consumer receives an anchor for a document identifier but a different content digest
- **THEN** it rejects the anchor rather than resolving it against another revision
