## ADDED Requirements

### Requirement: Platform removes abandoned archive staging

Edge SHALL run one bounded reaper over the archive staging root every `RATATOSKR__ARCHIVE_STAGING__SWEEP_INTERVAL_SECONDS` (default 300, 30 to 3600) when an archive receiver is configured, handling at most 200 sessions and 200 orphan directories per sweep, oldest first. A transfer row SHALL be reaped when its `expires_at` has passed, or its `session_state` is `failed`, or it is `finalized` and its directory is left over, or its owning operation has been terminal for more than 600 seconds; the token directory SHALL be removed first and the row second, so that a failure leaves the row for the next sweep. A row that is open, unexpired and owned by a non-terminal operation SHALL never be touched. An orphan is a directory named `rst_*` with no transfer row and a modification time older than 3600 seconds; stray `.readiness-*` files older than that are removed too. The sweep SHALL never follow a symbolic link, never leave the staging root and remove only names that match the token grammar. Each sweep SHALL re-check that the root is writable and that the volume's free space is at least twice `archive_staging.max_archive_bytes`, and set the `archive_staging` readiness accordingly. The series `platform_archive_staging_removed_total{reason="expired"|"failed"|"finalized"|"terminal"|"orphan"}`, `platform_archive_staging_oldest_directory_age_seconds` and `platform_archive_staging_directories` SHALL be exported on the operator listener.

#### Scenario: An upload is abandoned

- **WHEN** a client opens a session, sends one chunk and stops, and the session's expiry passes
- **THEN** within two sweep intervals the directory and the row are gone, a fresh open session and its directory are untouched, an orphan directory an hour old is removed, and the removed counter counts each reason, verified by `archive_staging_reaper.rs` in `ratatoskr-platform` and flow F1 of the native smoke when it is run

#### Scenario: The staging volume becomes unwritable

- **WHEN** the staging root is made unwritable
- **THEN** `archive_staging` turns false on `/health/ready` within two sweep intervals and true again when it is restored

### Requirement: Opening a dead transfer session replaces it

Opening a transfer SHALL replay the stored token only for a row whose `session_state` is `open` and unexpired. A `failed` or expired row SHALL be replaced by a new session (the old directory is removed, the new row inserted) and the response SHALL be `201`; a `finalized` row SHALL replay its token so that finalize returns the stored completion.

#### Scenario: A digest mismatch is opened again

- **WHEN** a session ended `failed` after a digest mismatch and the client opens the same operation again with a fresh `Idempotency-Key`
- **THEN** a new token is returned, the old directory is gone, and the upload completes

#### Scenario: The token row was dropped

- **WHEN** a client holds a token whose row was removed
- **THEN** `status`, `chunk` and `finalize` answer 404 for it and a reopen returns a new token

### Requirement: The Export Agent classifies Platform answers and bounds its retries

The Export Agent SHALL classify an answer of Platform's archive routes by the route and the status. On `prepare` and `open`, 400, 422 and 409 SHALL be permanent refusals, 404 SHALL be a retryable unavailability that counts toward the attempt cap, and 408, 429 and 5xx SHALL be retryable and honour `Retry-After`. On `status`, `chunk` and `finalize`, 404 SHALL mean the session is expired and SHALL reopen the transfer, 400 on `chunk` and `finalize` SHALL be retryable (the next attempt reconciles through `status`), and 408, 429 and 5xx SHALL be retryable. The `retryable` member of a parsed error envelope SHALL decide first, any other 4xx SHALL be permanent unless the envelope says otherwise, and 401, 403 and 413 SHALL keep their meaning (pairing lost, permanent, permanent). A reopen SHALL clear the stored token and acknowledged chunks and open with a fresh `Idempotency-Key`; the number of reopens per entry SHALL be bounded (default 3, stored in the checkpoint) and the fourth SHALL fail the entry. Consecutive retryable failures SHALL be bounded (default 24 attempts, delays doubling from 5 seconds to a 3600 second cap) and the entry that reaches the bound SHALL stop with the reason `retries_exhausted`, shown by the menu projection.

#### Scenario: The agent was offline for more than a day

- **WHEN** a stored resumption token was expired by Platform and the agent resumes
- **THEN** the first `chunk` or `status` answers 404, the agent reopens a session and completes the upload

#### Scenario: Platform keeps answering 404

- **WHEN** four reopens in a row end in a 404
- **THEN** the entry fails instead of retrying for ever

#### Scenario: A retryable failure repeats

- **WHEN** the 25th consecutive retryable failure happens
- **THEN** the entry stops with `retries_exhausted`; this behaviour is covered by the Swift tests of `ratatoskr-export-agent`, because the native smoke does not run the Swift client
