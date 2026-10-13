# ai-archive-receipt-binding Specification

## Purpose
TBD - created by archiving change xr-021-fleet-cross-repo-fixes. Update Purpose after archive.

## Requirements

### Requirement: Platform forwards an archive to a receiver in one fixed shape

When an upload is finalized, Platform SHALL send `POST http://127.0.0.1:{8096|8097}/v1/ai-archives/receipt` to the ChatGPT or Claude receiver with `Content-Type: application/zip` exactly and no parameters, a `Content-Length` equal to the declared byte size, and these Edge-minted claims: `x-ratatoskr-user-id` (UUID), `x-ratatoskr-device-id` (UUID), `x-correlation-id` (1 to 200 characters), `x-ratatoskr-operation-id` (UUID), `x-ratatoskr-archive-sha256` (64 lowercase hexadecimal characters) and `x-ratatoskr-archive-byte-size` (a decimal integer above zero). The request SHALL carry no `Authorization` header and no `Cookie`. The body SHALL be the raw archive bytes, streamed from the verified staging file in 64 KiB frames and never buffered whole. The path, the media type and the six header names are constants of `ratatoskr_ai_archive_contracts::platform_receipt`, and Platform and both receivers SHALL import them instead of restating them. The public client-facing chunk route remains `PUT`.

#### Scenario: A receiver accepts what Platform sends

- **WHEN** Platform finalizes an upload of a verified archive
- **THEN** the receiver answers `202 Accepted` with an empty body, Platform ignores the upstream body and returns the stored completion, verified by `crates/public-api/tests/ai_archives_receipt.rs` in `ratatoskr-platform` and `crates/chatgpt-archive/tests/receipt_http.rs` in `ratatoskr-chatgpt` against the same constants

#### Scenario: A receiver refuses

- **WHEN** a receiver refuses the request for any reason
- **THEN** it answers with an `application/json` body carrying an error envelope with a non-empty code and `retryable: false`, because Edge replaces any other response with `edge.upstream_invalid_response`; the codes are `<provider>.auth.unauthenticated` (401: missing claims, an `Authorization` header present, an unknown tenant), `<provider>.request.invalid` (400: wrong or missing media type, a declared identity that disagrees), `<provider>.request.too_large` (413), `<provider>.request.method_not_allowed` (405) and `<provider>.server.internal` (500), with `<provider>` equal to `chatgpt` or `claude`

### Requirement: A receiver announces that it can receive

While its receipt route is mounted, a receiver SHALL answer `GET /v1/capabilities` on its listener without headers or claims with `200`, `application/json`, at most 65536 bytes, and the document `{"service":"chatgpt"|"claude","capabilities":["ai_archive.receipt"]}`, where `service` equals the Edge route name. Platform SHALL treat a provider as ready to receive only when its last probe is fresh and the document passes the shared validator `is_receipt_capability_document`. GitHub keeps its own capability document unchanged and SHALL serve it without requiring an authenticated user; its `POST /v1/gh/repositories/preview` route still requires the claim. The capability probe is the single loopback route exempt from the minted-claims requirement, because it carries no tenant data.

#### Scenario: A receiver is up but cannot receive

- **WHEN** a provider's listener answers the probe with a document that lacks `ai_archive.receipt` or names another service
- **THEN** Platform reports the provider as not ready and withholds its archive route, verified by `crates/public-api/tests/capabilities.rs` in `ratatoskr-platform`

#### Scenario: A receiver answers its own probe

- **WHEN** a ChatGPT or Claude receiver is asked for `/v1/capabilities` with no headers
- **THEN** the body equals `receipt_capability_document` for its service, verified by the receipt tests of `ratatoskr-chatgpt` and `ratatoskr-claude`

### Requirement: An incomplete import is never reported as complete

A producer SHALL NOT report `partially_succeeded` without at least one warning or an error, SHALL NOT report `failed` without an error, and SHALL NOT report `succeeded` with an error. The shared check is `OperationReported::validate`. For an archive whose completeness is anything other than complete, ChatGPT and Claude SHALL report `partially_succeeded` with exactly one warning with the code `ai_archive.import.incomplete` and the message `The archive was imported, but it is not complete.`, no field path and no error. Platform SHALL reject an invalid report, record it in the inbox and not apply its status.

#### Scenario: An archive is incomplete

- **WHEN** a receiver finishes an import whose completeness is not complete
- **THEN** its report has status `partially_succeeded`, one warning with that code and message, and no error

#### Scenario: A producer sends an inconsistent report

- **WHEN** Platform reads a report that is `partially_succeeded` with no warning and no error
- **THEN** it records the report as rejected and leaves the operation's status unchanged, verified by the operation-report tests of `ratatoskr-platform` and the contract test `crates/operation-contracts/tests/reported.rs` in `ratatoskr-contracts`

### Requirement: Chunk and archive sizes have stated ceilings

The chunk route `PUT /v1/ai-archives/{provider}/{operation_id}/uploads/{token}/chunks/{index}` SHALL accept a body of up to 16777216 bytes, while the other archive routes keep the framework's 2 MiB default. Platform SHALL carry a configurable archive ceiling `RATATOSKR__ARCHIVE_STAGING__MAX_ARCHIVE_BYTES` (default 2147483648, valid from 1048576 to 10737418240). Preparing an upload whose declared byte size exceeds the ceiling SHALL answer `413` with the `payload_too_large` error envelope, non-retryable, while a size of zero or less, a bad digest or a bad key stays `400`. Opening an upload session whose declared media type is not `application/zip` SHALL answer `400`. The export agent SHALL treat a `413` as a permanent failure without retry.

#### Scenario: An archive exceeds the ceiling

- **WHEN** a client prepares an archive whose byte size is above the configured ceiling
- **THEN** Platform answers `413` with a `payload_too_large` envelope that is not retryable, and the export agent stops that archive without retrying

#### Scenario: A chunk of the maximum size arrives

- **WHEN** a client sends a chunk of exactly 16777216 bytes
- **THEN** the route accepts it, and a chunk whose body length differs from its declared length is still refused by the exact-length check

### Requirement: Each importer binds its receipt on a dedicated listener

ChatGPT and Claude SHALL each bind the Platform receipt and the capability document on a dedicated loopback listener, `RATATOSKR__RECEIPT__LISTEN_ADDRESS`, default `127.0.0.1:8096` for ChatGPT and `127.0.0.1:8097` for Claude, and SHALL refuse a configuration in which it equals the operator listener. `POST /v1/ai-archives/receipt` and `GET /v1/capabilities` SHALL be mounted only on the receipt listener and only while the database and the staging root are configured. The receipt listener SHALL NOT serve `/metrics`, `/health/*` or `/version`; the operator listener (ChatGPT `127.0.0.1:9085`, Claude `127.0.0.1:9086`) SHALL serve those and SHALL NOT serve the receipt or the capability document.

#### Scenario: Edge probes the allocated port

- **WHEN** Edge probes `127.0.0.1:8096` or `127.0.0.1:8097` for the capability document
- **THEN** the importer answers it with the capability `ai_archive.receipt`, `/metrics` on that port is `404`, and the receipt path is `404` on the operator port, verified by `crates/chatgpt-archive/tests/receipt_http.rs` and `services/chatgpt-archive/tests/boot.rs` in `ratatoskr-chatgpt` and `services/claude-archive/tests/boot.rs` in `ratatoskr-claude`

#### Scenario: The two listeners are the same address

- **WHEN** the configuration names one address for both listeners
- **THEN** the service refuses to start with a typed configuration error, verified by the `config.rs` tests of both importers

### Requirement: The Platform receipt accepts exactly application/zip

Both importers SHALL answer `400` with a JSON `ErrorEnvelope` (`chatgpt.request.invalid` or `claude.request.invalid`) for a Platform receipt whose `Content-Type` is anything other than `application/zip`, compared as the header value. A receipt that carries an `Authorization` header SHALL be `401`, and `GET` on the receipt path SHALL be `405` with `Allow: POST`.

#### Scenario: An octet-stream receipt

- **WHEN** a receipt arrives with `Content-Type: application/octet-stream`
- **THEN** the answer is `400` with the importer's `request.invalid` code, verified by `crates/chatgpt-archive/tests/receipt_http.rs` in `ratatoskr-chatgpt`

### Requirement: A fact that is too large is not published and the import says so

ChatGPT and Claude SHALL NOT truncate or split a conversation. A fact whose serialized envelope exceeds `RATATOSKR__RECEIPT__MAX_EVENT_BYTES` (default 8000000, validated 65536..=8388608) SHALL NOT be enqueued, and the import's terminal operation report, built in the same transaction that projects the facts, SHALL be `partially_succeeded` with one warning `ai_archive.facts.too_large` in addition to `ai_archive.import.incomplete` when that also applies. The incomplete-import rule is unchanged: exactly one warning of that code.

#### Scenario: One conversation exceeds the event limit

- **WHEN** an archive holds one conversation larger than the limit and others that fit
- **THEN** the fitting facts are published, the large one is not, and the report is `partially_succeeded` with `ai_archive.facts.too_large`, verified by `crates/claude-archive/tests/fact_size_guard.rs` in `ratatoskr-claude` and `crates/chatgpt-archive/tests/contract_projection.rs` in `ratatoskr-chatgpt`

### Requirement: A user a receiver does not map is refused with 403 and the refused delivery ends the operation

A Platform user that is absent from a receiver's `RATATOSKR__RECEIPT__PLATFORM_ACCOUNTS` SHALL be answered `403` with the code `<provider>.account.unmapped`, `retryable: false` and the message `This user is not set up for archive import.`; `401` SHALL remain for a missing or malformed claim set and for an `Authorization` header that must not be there. When the forwarded response of a finalize is a permanent refusal (a `4xx` other than `408` and `429`), Edge SHALL end the delivery in the same request: the transfer session becomes `failed`, the operation is recorded `failed` with `platform.ai_archive.delivery_failed` at stage `delivery` and retryable, the staging directory is removed (a leak is logged), and the receiver's refusal is returned to the client unchanged. A `5xx`, a timeout or the mapped 502 SHALL leave the session open and the operation `accepted`, so the client may retry finalize. Every refused receipt and every permanently failed import SHALL be logged at WARN with a closed class and the operation or run identifier, never an archive path, name or content.

#### Scenario: A user is unmapped

- **WHEN** a paired device of a user the receiver does not map finalizes an upload
- **THEN** the answer is 403 with `<provider>.account.unmapped`, the operation is `failed` with `platform.ai_archive.delivery_failed`, the transfer session is `failed`, the staging directory is gone, the device's next `GET /v1/capabilities` is still 200, and the receiver logged the class `unmapped_account`, verified by the receipt tests of `ratatoskr-chatgpt` and `ratatoskr-claude`, the finalize tests of `ratatoskr-platform`, and flow F1 of the native smoke when it is run

#### Scenario: The receiver is down

- **WHEN** the receiver is stopped and the client finalizes
- **THEN** Edge answers 502 or 503 and the operation stays `accepted`, and after the receiver restarts the same finalize succeeds

### Requirement: An upstream 401 never reaches a device

Edge SHALL map an upstream `401` or `407` to the `UpstreamInvalidResponse` failure (`502`, `edge.upstream_invalid_response`) for every gateway route and for the archive receipt, logging only the class `upstream_unauthenticated` and the route name, because Edge sends no `Authorization` to a receiver and its own authentication happened before the forward, so an upstream 401 is a deployment or contract fault and never the device's. The export agent SHALL count a `401` as a rejected credential only when its body is an `ErrorEnvelope` with the code `platform.auth.unauthenticated`; any other 401, and any 401 without that body, is `unavailable` and never removes the pairing. A `403` on a finalize SHALL be a permanent failure with the existing attention state.

#### Scenario: A receiver answers 401

- **WHEN** a receiver answers 401 to a forwarded archive
- **THEN** the client receives 502 `edge.upstream_invalid_response`, and the export agent keeps the pairing, verified by the gateway tests of `ratatoskr-platform` and the client tests of `ratatoskr-export-agent`

### Requirement: Both receivers create the account on the first mapped receipt

ChatGPT and Claude SHALL insert the mapped account in the receipt transaction on first use, the Claude path with `insert into claude_archive.accounts (account_id, external_account_id) values ($1, 'platform-account:' || $1) on conflict (account_id) do nothing`, so that no operator inserts an account row by hand; the tenant-token path of Claude keeps requiring an existing account or organization.

#### Scenario: The first receipt of a mapped user

- **WHEN** the first archive of a mapped user reaches a Claude receiver whose account table is empty
- **THEN** the account row exists afterwards and the import proceeds, verified by `crates/claude-archive/tests/platform_account.rs` in `ratatoskr-claude` and flow F1 of the native smoke when it is run

### Requirement: A duplicate of a failed import is reported failed

`process_pending_once` of both receivers SHALL also select a `failed` import run that has a bound operation whose report is still unsent and SHALL enqueue the `failed` operation report for it, with the same code and retryability as the first failure (`<provider>.archive.invalid`, not retryable), so a second upload of bytes that failed permanently ends `failed` at once instead of waiting for the stale reaper.

#### Scenario: The same corrupt archive is uploaded twice

- **WHEN** a client uploads bytes that failed permanently, under a new idempotency key
- **THEN** the second operation reaches `failed` without waiting an hour, verified by the import tests of `ratatoskr-chatgpt` and `ratatoskr-claude` and flow F1 of the native smoke when it is run
