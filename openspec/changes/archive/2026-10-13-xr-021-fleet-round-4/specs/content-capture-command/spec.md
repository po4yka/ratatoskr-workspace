## MODIFIED Requirements

### Requirement: Telegram accepts a PDF and refuses everything else truthfully

Telegram SHALL send only an `application/pdf` document through the blob path, to `POST /v1/captures/blobs` with the blob reference and the optional `origin` member and an `Idempotency-Key`, while a URL still goes to `POST /v1/captures`. A photo, any other document type and any non-document attachment SHALL receive the static reply "Unsupported attachment: Send a PDF document with a text layer; images, video, voice, and audio are not supported yet." Image capture is refusal-only until it has an OCR subsystem and an image block in the document model. Before an update is settled as failed, Telegram SHALL enqueue one static reply: "Ratatoskr is temporarily unavailable" when submission retries are exhausted, "Could not save this item" for a permanent refusal by Platform, and "Could not read the attachment" when the file could not be fetched, stored or typed. A pending Platform projection keeps its retry path with no reply. The update state stays failed even if the reply cannot be enqueued. The idempotency key of a capture SHALL be `hex(sha256("capture.v2|" || sender id || "|" || route path || "|" || exact request body bytes))`, derived from the same path and body value that is sent to Platform, so that a key never describes a body other than the one sent: the same body replays its operation, and a different body (the same PDF forwarded, a different media type) is a separate operation over the same content. A conflict from Platform for a capture SHALL be a transient class, retried within the bounded retries and answered with the temporarily-unavailable text on exhaustion, never with "Could not save this item". When Platform answers a capture with an unauthenticated status, Telegram SHALL drop the cached credential if it is still the current one, exchange a fresh session and retry once before it classifies a permanent refusal.

#### Scenario: A user sends a photo

- **WHEN** an update carries only a photo
- **THEN** the user receives the unsupported-attachment reply and no submission is made, verified by `services/webhook/tests/capture_attachments/mod.rs` in `ratatoskr-telegram`

#### Scenario: Platform is down for a PDF

- **WHEN** submission retries are exhausted
- **THEN** the user receives the temporarily-unavailable reply before the update is settled as failed, verified by `services/webhook/tests/capture_failures/mod.rs`

#### Scenario: The same PDF is sent plain and then forwarded

- **WHEN** a sender sends a PDF and then forwards the same PDF with a forward origin
- **THEN** two operations are accepted, two acknowledgements are sent and no refusal reply exists, verified by `services/webhook/tests/capture_submission/mod.rs` in `ratatoskr-telegram` and flow F3 of the native smoke when it is run

#### Scenario: The Platform session was lost

- **WHEN** Platform answers the first submit 401
- **THEN** Telegram exchanges a fresh session and the second attempt succeeds, and a second 401 is a permanent refusal

### Requirement: Telegram speaks to the allocated Edge

The Telegram deployment examples SHALL set `RATATOSKR__PLATFORM__AUDIENCE=edge`, the fixed audience of the Edge binary, and `RATATOSKR__PLATFORM__BASE_URL=http://127.0.0.1:8080`, and the compiled defaults SHALL be the same. After every successful token exchange Telegram SHALL bind the Telegram user to the Platform user in `telegram.identities`, so that notification admission can find an eligible chat; a changed mapping overwrites and a missing identity row is not an error. The notification bus ack wait SHALL be exactly 30 seconds, the value Edge fixes on the `ratatoskr_telegram_notifications` durable; the dispatcher refuses any other value, the validation message names Edge's fixed durable, and the workspace harness compares the constant `NOTIFICATION_ACK_WAIT_SECONDS` with Edge's durable table.

#### Scenario: The example files are pinned

- **WHEN** `services/webhook/tests/deployment_profile.rs` in `ratatoskr-telegram` reads the webhook and dispatcher examples
- **THEN** both name the audience `edge` and the base URL `http://127.0.0.1:8080`

#### Scenario: An ack wait Edge does not provision

- **WHEN** the dispatcher is configured with an ack wait of 31
- **THEN** its configuration check fails naming Edge's fixed durable, verified by `crates/core/tests/notification_config.rs` in `ratatoskr-telegram` and by `service_ack_wait_constants_agree_with_edges_durable_table` in the workspace harness
