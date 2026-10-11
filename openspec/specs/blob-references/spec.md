# Stored bytes across repositories

## Purpose

Defines how services exchange durable artifact references while preserving byte integrity and
service ownership without introducing a shared blob service.

## Requirements

### Requirement: A blob is named by a reference, not served by a service

A service that stores bytes outside its database SHALL make them reachable to another service by
publishing a `BlobRef`, carrying the owning service, a content digest with its algorithm, the media
type and the byte length. No repository SHALL provide a blob storage service, and no contract SHALL
require one.

#### Scenario: one service hands a stored artifact to another

- **WHEN** an extracting service stores a fetched page and publishes an event referencing it
- **THEN** the event carries a `BlobRef` and not the bytes, and a consumer resolves the reference
  without calling an API belonging to a blob service

#### Scenario: the digest identifies the bytes

- **WHEN** a consumer resolves a `BlobRef` and hashes what it read
- **THEN** the digest matches the one in the reference, or the consumer treats the artifact as
  missing rather than as changed

### Requirement: The owning service owns the bytes

Each service SHALL write its own blobs, under a content-addressed path of its own on the deployment
target's durable device, and SHALL NOT write into another service's. The control plane SHALL own no
blobs at all.

#### Scenario: the control plane stores no extracted content

- **WHEN** a change proposes storing a document, a summary or an embedding in the control plane
- **THEN** the change is refused, because the control plane does not own extracted content

#### Scenario: a blob outlives the event that announced it

- **WHEN** the event announcing a blob has aged out of the bus
- **THEN** the blob is still readable by its reference, because its lifetime belongs to the owning
  service and not to the message

### Requirement: A consumer may read a producer's blob root read-only

On the single-host deployment target, a consumer MAY read the bytes of a `BlobRef` directly from the owning service's content-addressed root, without a blob service and without an HTTP transfer, when the owning service has granted a dedicated read group on that root. The consumer SHALL verify the reference before using the bytes (owner service, digest algorithm, digest, byte length, and a fresh hash of what it read), SHALL copy the verified bytes into its own store when it needs them as its own, and SHALL NEVER write, rename or delete anything under the producer's root. The root SHALL be created with the owning service's user and the read group, with the setgid bit so new files inherit the group, and the owning service SHALL write with a umask that leaves the group able to read. The Telegram root `/mnt/nvme/ratatoskr/blobs/ratatoskr-telegram` and its group `ratatoskr-telegram-blobs` are the first instance.

#### Scenario: The extractor reads a Telegram PDF

- **WHEN** the extractor resolves a `BlobRef` owned by `ratatoskr-telegram`
- **THEN** it reads the file through the read group, verifies it, stores its own copy with the same digest, and leaves the Telegram root unchanged, verified by `services/extractor/tests/blob_pdf_pipeline.rs` in `ratatoskr-extractor`

#### Scenario: A reference names the wrong owner

- **WHEN** the extractor is given a `BlobRef` whose owner is not `ratatoskr-telegram`
- **THEN** the run fails with the class `blob_owner` and nothing is read from the peer root

### Requirement: Registration and erasure of a content-addressed blob follow one lock protocol

ChatGPT, Claude and Knowledge keep content-addressed blob stores that are shared across tenants and exports, so an erasure that re-checks whether a digest is still referenced and an import that stores identical bytes and registers a reference afterwards SHALL be serialized by one lock per digest: `pg_advisory_xact_lock(hashtextextended('blob:' || <digest_hex>, 0))` in the service's own database. An eraser SHALL, for each erase-action item and in one transaction, take the digest lock, re-check every reference column with the function the planner uses, then either skip the item as shared or erase the bytes idempotently and mark the item purged, committing while still holding the lock. A registrar SHALL take the digest lock before inserting the first row that references a digest and SHALL then verify the blob is present; if it is missing it SHALL re-store the bytes when it still holds them and otherwise fail the import run with a retryable class and register nothing. The tenant lock stays and nests outside the digest lock, and several digests are locked in ascending order. The invariant is that no committed row references a missing blob.

#### Scenario: A deletion races an import of identical bytes

- **WHEN** one transaction erases a digest while another registers a reference to the same bytes
- **THEN** the second either finds the bytes present and registers, or re-stores them, and no committed row references a missing blob, verified by `crates/knowledge/tests/deletion_blob_race.rs` in `ratatoskr-knowledge` and the interleaving tests of `ratatoskr-chatgpt` and `ratatoskr-claude`

#### Scenario: The bytes are gone and cannot be re-stored

- **WHEN** an eraser won and the registrar no longer holds the bytes
- **THEN** the import run fails with a retryable class and no reference row is written
