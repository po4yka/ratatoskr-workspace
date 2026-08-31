## Purpose

Defines the canonical event by which Extractor makes one immutable Document IR revision durably available to Knowledge without changing the existing v1 wire payload.

## ADDED Requirements

### Requirement: Extracted documents use a registered typed event
`ratatoskr-contracts` SHALL register `content.document.extracted.v1` as an internal event whose payload is the canonical v1 `Document`, whose producer is `ratatoskr-extractor`, and whose consumer is `ratatoskr-knowledge`. The registration SHALL generate and validate the event schema and compatibility fixtures from the same payload type used for `content.document`.

#### Scenario: Existing document wire shape remains canonical
- **WHEN** a valid existing `content.document.extracted.v1` envelope is decoded through the typed contract
- **THEN** its payload decodes as the same `Document` value and re-encodes without a wrapper, renamed field, or later major version

#### Scenario: Invalid document content is refused
- **WHEN** an extracted-document envelope contains an invalid Document IR payload or an unknown field forbidden by the Document contract
- **THEN** contract validation rejects the event before it can be admitted as Knowledge work

### Requirement: Document fact identity is internally consistent
An extracted-document delivery SHALL use subject `evt.content.document.extracted.v1`; its envelope event type SHALL be `content.document.extracted.v1`, producer SHALL be `ratatoskr-extractor`, and aggregate identity SHALL equal the payload `document_id`.

#### Scenario: Extractor publishes a consistent fact
- **WHEN** Extractor completes one document revision
- **THEN** the published subject, envelope event type, producer, aggregate identity, and payload document identity satisfy the extracted-document contract

#### Scenario: Conflicting transport identity is rejected
- **WHEN** any subject, event type, producer, aggregate identity, or payload document identity conflicts with the extracted-document contract
- **THEN** Knowledge records a non-sensitive permanent rejection and creates no analysis or search projection
