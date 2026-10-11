## ADDED Requirements

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
