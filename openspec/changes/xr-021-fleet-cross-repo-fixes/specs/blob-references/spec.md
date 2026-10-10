## ADDED Requirements

### Requirement: A consumer may read a producer's blob root read-only

On the single-host deployment target, a consumer MAY read the bytes of a `BlobRef` directly from the owning service's content-addressed root, without a blob service and without an HTTP transfer, when the owning service has granted a dedicated read group on that root. The consumer SHALL verify the reference before using the bytes (owner service, digest algorithm, digest, byte length, and a fresh hash of what it read), SHALL copy the verified bytes into its own store when it needs them as its own, and SHALL NEVER write, rename or delete anything under the producer's root. The root SHALL be created with the owning service's user and the read group, with the setgid bit so new files inherit the group, and the owning service SHALL write with a umask that leaves the group able to read. The Telegram root `/mnt/nvme/ratatoskr/blobs/ratatoskr-telegram` and its group `ratatoskr-telegram-blobs` are the first instance.

#### Scenario: The extractor reads a Telegram PDF

- **WHEN** the extractor resolves a `BlobRef` owned by `ratatoskr-telegram`
- **THEN** it reads the file through the read group, verifies it, stores its own copy with the same digest, and leaves the Telegram root unchanged, verified by `services/extractor/tests/blob_pdf_pipeline.rs` in `ratatoskr-extractor`

#### Scenario: A reference names the wrong owner

- **WHEN** the extractor is given a `BlobRef` whose owner is not `ratatoskr-telegram`
- **THEN** the run fails with the class `blob_owner` and nothing is read from the peer root
