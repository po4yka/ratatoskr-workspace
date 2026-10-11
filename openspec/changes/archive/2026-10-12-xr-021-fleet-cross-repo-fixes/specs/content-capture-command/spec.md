## ADDED Requirements

### Requirement: Content capture is one typed command

`content.capture.requested.v1` SHALL be a `CommandEnvelope` published to `cmd.content.capture.requested.v1` by `ratatoskr-platform` (for `POST /v1/captures`, `POST /v1/captures/blobs` and the webhook adapter) or by `ratatoskr-x` (for a linked article), and consumed by the extractor. The envelope SHALL carry a UUIDv7 `command_id`, aggregate `operation:<operation_id>`, a required tenant `user:<uuid>`, the issue time and the current schema version. The payload SHALL be exactly one of `{operation_id, idempotency_key, url}` and `{operation_id, idempotency_key, blob}`, where `idempotency_key` is a sha256 content digest of the caller's idempotency string (for X, of the capture identifier), `url` is an `http` or `https` string of at most 2048 characters, and `blob` is a `BlobRef` with a sha256 digest. A payload with both members, or with neither, SHALL be rejected by the deserializer and by the generated schema. The extractor SHALL derive its operation identifier from `payload.operation_id`, SHALL reject an `aggregate_id` that disagrees with it, and SHALL treat an undecodable or wrongly produced command as permanently invalid.

#### Scenario: A payload names both a url and a blob

- **WHEN** a command payload carries both members
- **THEN** it is rejected, verified by the invalid fixture `both-url-and-blob.json` and `crates/document-contracts/tests/capture_command.rs` in `ratatoskr-contracts`

#### Scenario: Old and new binaries meet

- **WHEN** a producer or consumer still on the earlier flat command document sends or reads a capture command
- **THEN** the message is terminated on decode and is not processed, which is why Platform, the extractor and X merge and deploy together

### Requirement: Platform accepts a blob capture only from the Telegram session

`POST /v1/captures/blobs` SHALL require a session, an `Idempotency-Key` of 1 to 255 characters (otherwise `400 platform.request.idempotency_key_required`) and a body `{"blob": <BlobRef>}`; unknown members of the body, such as `origin`, are tolerated and ignored. It SHALL answer `400 platform.request.invalid` unless the body parses, the digest algorithm is `sha256`, and the length is from 1 to 52428800 bytes, which equals the extractor's PDF ceiling. It SHALL answer `403 platform.auth.forbidden` unless the session kind is the Telegram mini app and the blob's owner service is `ratatoskr-telegram`. Success SHALL answer `202` with `{"operation_id":"<uuid>","status":"accepted"}`, with the same `401`, `409`, `429` and `504` as `POST /v1/captures`, in one transaction that reserves the key, creates the operation of kind `content.capture.submit`, enqueues the blob-form command and records the audit entry. `POST /v1/captures` and its request document SHALL NOT change, so the generated web, mobile and browser-extension clients do not drift. Platform does not judge whether the media type is extractable. The store is content-addressed and deduplicated across users, so the guard is the Telegram session kind, the owner allow-list and the unguessable 256-bit digest; that residual risk is documented.

#### Scenario: A web session names a Telegram blob

- **WHEN** a session that is not the Telegram mini app posts a valid blob reference
- **THEN** Platform answers `403`, verified by `crates/public-api/tests/capture_blobs.rs` in `ratatoskr-platform`

#### Scenario: Telegram resubmits with the same key

- **WHEN** Telegram posts the same blob and key twice
- **THEN** the second answer replays the first operation and no second command is enqueued

### Requirement: The extractor turns a Telegram blob into a document

For a blob command the extractor SHALL read the peer root `RATATOSKR__BLOBS__TELEGRAM_ROOT` (an absolute path, default `/mnt/nvme/ratatoskr/blobs/ratatoskr-telegram`, existence not required at startup), verify the reference (owner `ratatoskr-telegram`, sha256, length, a fresh hash of the bytes) and copy the verified bytes into its own store as an extractor-owned blob with the same digest. It SHALL never write, rename or delete in the peer root. Only `application/pdf` is extractable. A failed run SHALL be non-retryable and carry one of the classes `blob_owner`, `blob_missing`, `blob_mismatch`, `blob_unreadable`, `unsupported_media`, `pdf_encrypted`, `pdf_no_text_layer` or `parse`. The source SHALL be recorded as kind `blob` with the address `urn:ratatoskr:blob:sha256:<hex>`, host `ratatoskr-telegram`, and no URL normalization or address policy applied; the same user sending the same PDF reuses the source and starts a new run.

#### Scenario: A PDF with a text layer arrives

- **WHEN** the extractor reads a Telegram-owned PDF blob
- **THEN** it publishes `content.document.extracted.v1` with an extractor-owned raw reference, verified by `services/extractor/tests/blob_pdf_pipeline.rs` in `ratatoskr-extractor`

#### Scenario: The group does not exist on the host

- **WHEN** the extractor cannot read the peer root
- **THEN** the run fails with `blob_unreadable`, a host condition that no repository can repair

### Requirement: Telegram accepts a PDF and refuses everything else truthfully

Telegram SHALL send only an `application/pdf` document through the blob path, to `POST /v1/captures/blobs` with the blob reference and the optional `origin` member and an `Idempotency-Key`, while a URL still goes to `POST /v1/captures`. A photo, any other document type and any non-document attachment SHALL receive the static reply "Unsupported attachment: Send a PDF document with a text layer; images, video, voice, and audio are not supported yet." Image capture is refusal-only until it has an OCR subsystem and an image block in the document model. Before an update is settled as failed, Telegram SHALL enqueue one static reply: "Ratatoskr is temporarily unavailable" when submission retries are exhausted, "Could not save this item" for a permanent refusal by Platform, and "Could not read the attachment" when the file could not be fetched, stored or typed. A pending Platform projection keeps its retry path with no reply. The update state stays failed even if the reply cannot be enqueued.

#### Scenario: A user sends a photo

- **WHEN** an update carries only a photo
- **THEN** the user receives the unsupported-attachment reply and no submission is made, verified by `services/webhook/tests/capture_attachments/mod.rs` in `ratatoskr-telegram`

#### Scenario: Platform is down for a PDF

- **WHEN** submission retries are exhausted
- **THEN** the user receives the temporarily-unavailable reply before the update is settled as failed, verified by `services/webhook/tests/capture_failures/mod.rs`

### Requirement: Telegram speaks to the allocated Edge

The Telegram deployment examples SHALL set `RATATOSKR__PLATFORM__AUDIENCE=edge`, the fixed audience of the Edge binary, and `RATATOSKR__PLATFORM__BASE_URL=http://127.0.0.1:8080`, and the compiled defaults SHALL be the same. After every successful token exchange Telegram SHALL bind the Telegram user to the Platform user in `telegram.identities`, so that notification admission can find an eligible chat; a changed mapping overwrites and a missing identity row is not an error.

#### Scenario: The example files are pinned

- **WHEN** `services/webhook/tests/deployment_profile.rs` in `ratatoskr-telegram` reads the webhook and dispatcher examples
- **THEN** both name the audience `edge` and the base URL `http://127.0.0.1:8080`
