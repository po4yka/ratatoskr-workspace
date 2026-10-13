## ADDED Requirements

### Requirement: A document has one identity per owner and content digest

The document identifier of an extracted document SHALL be derived, never minted: the first 16 bytes of SHA-256 over `"ratatoskr.document.v1\0"`, the owner's UUID bytes and the content digest's hexadecimal bytes, with the version nibble set to 8 and the RFC 4122 variant bits set. The extractor's document assembly SHALL take the owner instead of an identifier, so that no parser can mint one and the same blocks for the same owner always produce the same identifier. The same bytes captured twice (plain then forwarded, by a blob and by a URL, by two operations) SHALL complete both operations, emit an `evt.content.document.extracted.v1` for each with equal `Document.content_digest` and equal `document_id`, and name `document:<id>` with that one identity in both operation reports. Knowledge SHALL register at most one `source_refs` row per tenant, extractor owner context and content digest: when a row with an equal digest exists under another source document identifier it SHALL reuse it, create no run and answer `AlreadyAnalysed`, and the database SHALL carry a partial unique index that enforces this and resolves a conflict on either key to the existing row. Two tenants with the same digest SHALL each keep their own document.

#### Scenario: The same PDF is captured twice

- **WHEN** one PDF is captured once as a blob and once through a URL
- **THEN** two operations succeed, library search returns one document, and both extracted events carry the same `document_id`, verified by the extractor and Knowledge tests against real PostgreSQL and by flows F2 and F3 of the native smoke when they are run

#### Scenario: An older extractor mints two identifiers

- **WHEN** Knowledge receives two events with equal digests and different document identifiers
- **THEN** it still keeps one `source_refs` row, one analysis run and one search document

#### Scenario: Two tenants share a digest

- **WHEN** two tenants capture the same bytes
- **THEN** each keeps its own document
