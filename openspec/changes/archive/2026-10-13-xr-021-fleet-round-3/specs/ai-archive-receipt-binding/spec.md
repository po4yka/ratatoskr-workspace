## ADDED Requirements

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
