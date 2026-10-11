## ADDED Requirements

### Requirement: Registration and erasure of a content-addressed blob follow one lock protocol

ChatGPT, Claude and Knowledge keep content-addressed blob stores that are shared across tenants and exports, so an erasure that re-checks whether a digest is still referenced and an import that stores identical bytes and registers a reference afterwards SHALL be serialized by one lock per digest: `pg_advisory_xact_lock(hashtextextended('blob:' || <digest_hex>, 0))` in the service's own database. An eraser SHALL, for each erase-action item and in one transaction, take the digest lock, re-check every reference column with the function the planner uses, then either skip the item as shared or erase the bytes idempotently and mark the item purged, committing while still holding the lock. A registrar SHALL take the digest lock before inserting the first row that references a digest and SHALL then verify the blob is present; if it is missing it SHALL re-store the bytes when it still holds them and otherwise fail the import run with a retryable class and register nothing. The tenant lock stays and nests outside the digest lock, and several digests are locked in ascending order. The invariant is that no committed row references a missing blob.

#### Scenario: A deletion races an import of identical bytes

- **WHEN** one transaction erases a digest while another registers a reference to the same bytes
- **THEN** the second either finds the bytes present and registers, or re-stores them, and no committed row references a missing blob, verified by `crates/knowledge/tests/deletion_blob_race.rs` in `ratatoskr-knowledge` and the interleaving tests of `ratatoskr-chatgpt` and `ratatoskr-claude`

#### Scenario: The bytes are gone and cannot be re-stored

- **WHEN** an eraser won and the registrar no longer holds the bytes
- **THEN** the import run fails with a retryable class and no reference row is written
