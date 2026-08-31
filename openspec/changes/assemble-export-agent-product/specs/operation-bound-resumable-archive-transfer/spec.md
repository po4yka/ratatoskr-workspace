## Purpose

Defines how one authenticated Platform archive operation owns a resumable, digest-verified transfer
from preparation through provider acceptance without allowing retry to create competing imports.

## ADDED Requirements

### Requirement: Preparation binds one operation to one immutable transfer declaration
Platform SHALL accept an export-agent device's supported provider, idempotency key, whole-archive
SHA-256, byte size, media type, and fixed chunk size before any payload byte. It SHALL atomically bind
the resulting operation, owner, provider, declaration, and resumable transfer session. Replaying the
same request SHALL return the same operation and transfer identity; changed metadata under the same
key SHALL be refused.

#### Scenario: New preparation returns a bound resumable transfer
- **WHEN** an authorized export-agent device prepares a valid ChatGPT or Claude archive
- **THEN** Platform returns one operation identifier and the operation-bound open transfer state
  without receiving archive bytes

#### Scenario: Identical preparation replays safely
- **WHEN** the device repeats a preparation with the same idempotency key and exact declaration
- **THEN** Platform returns the original operation and transfer identity and creates no new operation

#### Scenario: Changed preparation conflicts
- **WHEN** the device reuses an idempotency key with a different provider, digest, size, media type,
  or chunk size
- **THEN** Platform refuses the request and leaves the original binding unchanged

### Requirement: Transfer recovery remains inside the prepared operation
The operation-bound transfer SHALL implement the fleet blob-transfer open, indexed chunk, status,
and finalize semantics. A client that loses an acknowledgement SHALL query the same transfer and
send only missing chunks. An expired transfer MAY be replaced only within the same non-terminal
operation and immutable declaration; retry MUST NOT create another archive operation.

#### Scenario: Interrupted delivery resumes missing chunks
- **WHEN** some chunks were acknowledged before connectivity was lost
- **THEN** status identifies exactly the received indices and the client can complete the same
  operation by sending only missing chunks

#### Scenario: Relaunch does not prepare again
- **WHEN** a client relaunches with a durable operation binding and an incomplete transfer
- **THEN** it recovers or replaces the transfer within that operation and issues no second prepare

#### Scenario: Divergent chunk cannot corrupt a session
- **WHEN** different bytes are sent for an already recorded chunk index
- **THEN** Platform reports the blob-transfer conflict and retains the originally recorded chunk

### Requirement: Only a verified complete transfer reaches the owning archive service
Platform SHALL finalize only after every expected chunk is present and the streamed bytes match the
prepared size and SHA-256. It SHALL then deliver those verified bytes to the receipt route selected
by the operation's provider while injecting the operation correlation. Upload acknowledgement SHALL
mean only provider acceptance; operation success SHALL come only from the provider's terminal
report.

#### Scenario: Digest mismatch never reaches provider
- **WHEN** finalization computes a digest different from the prepared declaration
- **THEN** Platform refuses finalization, sends no archive to a provider, and does not mark the
  operation successful

#### Scenario: Verified Claude archive reaches only Claude
- **WHEN** a Claude-bound transfer finalizes with the declared bytes
- **THEN** Platform sends it only to the configured Claude receipt route with the bound operation
  correlation and returns provider acceptance without claiming import completion

#### Scenario: Provider rejects receipt
- **WHEN** the selected provider does not accept the finalized archive
- **THEN** Platform records a safe non-success operation outcome and exposes no private upstream text

### Requirement: Archive transfer authority is owner- and device-scoped
Every preparation, transfer-status, chunk, and finalize request SHALL require an active
`export_agent` device session owned by the same user as the operation. Callers MUST NOT select an
upstream listener, inject operation correlation headers, read another user's transfer status, or
resume a revoked device's work.

#### Scenario: Foreign device cannot inspect transfer status
- **WHEN** another user's valid export-agent credential asks for an operation transfer status
- **THEN** Platform returns the same bounded not-found response used for absent authority

#### Scenario: Revoked device cannot resume
- **WHEN** a revoked device presents a previously valid operation and transfer identity
- **THEN** Platform refuses the request without changing stored chunks or the local client's archive
