# Document IR at the repository boundary

## Purpose

Defines the canonical document shape that extraction produces and analysis consumes across a
repository boundary, including ordered content and provenance.

## Requirements

### Requirement: Version one is the shared intersection

The Document IR published by `ratatoskr-contracts` SHALL carry only what an extracting service
produces and an analysing service consumes: the document's identity, the address it came from, a
content digest, an optional title and language, an ordered sequence of typed blocks, and provenance
naming which strategy produced it and from which stored blob. Anything a single service needs and no
other reads SHALL stay inside that service.

#### Scenario: an extracted document round-trips between two repositories

- **WHEN** an extracting service serializes a document as Document IR and an analysing service
  deserializes it
- **THEN** the analysing service reads the blocks, the digest and the provenance without consulting
  the extracting service's own tables

#### Scenario: a service-private field does not enter the shared shape

- **WHEN** a change proposes adding a field to Document IR that only one repository reads
- **THEN** the field belongs in that repository's own storage and the change is refused

### Requirement: Document IR blocks extraction, not the extracting service

Document IR SHALL be published before the extracting service implements its parse step, and SHALL
NOT be a precondition of that service starting. Configuration, fetching and address policy SHALL be
implementable against no Document IR at all.

#### Scenario: the extracting service starts before the shape exists

- **WHEN** the extracting service implements its configuration, its address policy and its fetch step
- **THEN** none of that work references Document IR, and it merges before contracts publishes the
  shape
