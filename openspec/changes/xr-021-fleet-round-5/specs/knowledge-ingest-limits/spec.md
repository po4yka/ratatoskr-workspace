## ADDED Requirements

### Requirement: Knowledge stores a snapshot up to the blob ceiling the producers can reach

Knowledge SHALL build its blob store with `RATATOSKR__LIMITS__BLOB_BYTES` alone; `RATATOSKR__LIMITS__RAW_RESPONSE_BYTES` SHALL remain the cap on one provider HTTP response and SHALL NOT bound a stored snapshot. Configuration validation SHALL refuse a `blob_bytes` below 8,388,608 (the broker's `max_payload`, the largest fact any producer can publish) and a `blob_bytes` below `raw_response_bytes`, with a message that names both limits; the default stays 16 MiB. A snapshot above `blob_bytes` SHALL still be rejected with a class and no partial state.

#### Scenario: A conversation of 7.9 million bytes

- **WHEN** ChatGPT or Claude publishes a conversation fact of 2 MiB, and one of 7.9 million bytes, under the deployed ACL
- **THEN** both are stored, analysed and searchable, verified by the Knowledge pipeline tests against real PostgreSQL and a real broker and by flow F2 of the native smoke when it is run

#### Scenario: A ceiling below the broker payload

- **WHEN** Knowledge is configured with `blob_bytes` of 8,388,607
- **THEN** startup is refused, and 8,388,608 is accepted

### Requirement: A provider failure an operator can fix does not lose content

Knowledge SHALL classify a provider answer so that 401 and 403 (`AuthError`), 402 (`PaymentRequired`) and 404 (`ModelUnavailable`) are recoverable by an operator: such a failure SHALL NOT be permanent, SHALL NOT count as a spent attempt, SHALL reopen the run to `queued` on the next delivery, and SHALL be redelivered with the delay `min(2 s * 2^(delivered - 1), 60 s)` for as long as it lasts, with a WARN carrying the family, the class and the delivery count (never content) from the second delivery on and the existing counter `knowledge_ingest_redeliveries_total` counting it. 408, 429 and 5xx SHALL stay transient, and 400, 422 and any other 4xx SHALL stay permanent and be rejected at the first delivery. The same classification SHALL apply wherever the embeddings and channel-recap adapters share it.

#### Scenario: The provider rejects the key for a while

- **WHEN** the provider answers 401, then 402, then 404 for a document capture, a social fact and an AI conversation in flight, and then answers 200
- **THEN** all three become searchable, nothing was terminated for it, the run rows carry no permanent failure and `knowledge_ingest_redeliveries_total` is above zero, verified by the provider and ingest tests of `ratatoskr-knowledge` and by flow F2 of the native smoke when it is run

#### Scenario: A request the provider refuses as invalid

- **WHEN** the provider answers 400
- **THEN** the delivery is rejected at its first attempt

### Requirement: An equal-time delivery with a later event identifier replaces the head

Knowledge SHALL move a source's analysis head when the delivery's `observed_at` is later than the head's, or equal and its event identifier is greater (event identifiers are UUIDv7 and time ordered), and SHALL report such a delivery as current. A strictly older delivery, or an equal one with a smaller event identifier, SHALL remain historical; a redelivery of an already claimed event SHALL remain a duplicate. The analysis revision stays keyed by content digest, so a changed digest is analysed again and an unchanged one is not.

#### Scenario: A survivor is re-announced with the stale head's instant

- **WHEN** a conversation is re-announced after a privacy deletion with the retained archive's original `imported_at`, equal to the stale head's
- **THEN** the re-announced text replaces the head, and the text only the deleted export held is not searchable, verified by the Knowledge replay test of Claude's survivor sequence and by flow F6 of the native smoke when its survivor leg is run

#### Scenario: Equal instants and equal digests

- **WHEN** two deliveries share `observed_at` and the content digest
- **THEN** the head keeps its analysis and no new revision is made
