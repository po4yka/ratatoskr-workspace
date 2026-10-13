# Spec Delta

## Purpose

Defines how Knowledge turns note file changes into analysis and search entries, and how it removes
derived data when a file or a connection goes away.

## ADDED Requirements

### Requirement: A note file change is itself the analysis request

Knowledge SHALL create analysis and search entries from received `evt.notes.file.changed.v1` events
alone, keyed idempotently by `file_id` plus revision. There SHALL be no separate command channel from
`ratatoskr-notes` into Knowledge. Knowledge SHALL analyse only Markdown files, and SHALL record other
media types as not analysable without an error.

#### Scenario: One revision creates one run

- **WHEN** Knowledge receives a `created` event and then two redeliveries of it
- **THEN** exactly one analysis run exists for that `file_id` and revision, verified by `services/knowledge/tests/notes_intake.rs::one_run_per_file_revision` in `ratatoskr-knowledge`

#### Scenario: An image is changed

- **WHEN** Knowledge receives an event for `Attachments/photo.png`
- **THEN** no analysis run is created, the message is acknowledged, and no error is logged, verified by `services/knowledge/tests/notes_intake.rs::non_markdown_file_creates_no_run` in `ratatoskr-knowledge`

### Requirement: Deletion and disconnection remove derived data

On a `deleted` event, Knowledge SHALL remove the analyses, embeddings and search entries of that
file. On `evt.notes.vault.disconnected.v1`, Knowledge SHALL remove them for every file of that
connection. A later redelivery of an older event SHALL NOT recreate derived data for a removed file.

#### Scenario: A connection is removed

- **WHEN** a connection with 30 analysed files is removed
- **THEN** no search query of the owner returns any of those files, and no embedding of them remains, verified by `services/knowledge/tests/notes_intake.rs::disconnect_removes_all_derived_data` in `ratatoskr-knowledge`

#### Scenario: An old event arrives after a delete

- **WHEN** an `updated` event with a lower connection sequence is redelivered after the `deleted` event of the same file
- **THEN** Knowledge creates no run and no search entry for it, verified by `services/knowledge/tests/notes_intake.rs::older_event_after_delete_creates_nothing` in `ratatoskr-knowledge`

### Requirement: Knowledge reads note bytes read-only from the owner's root

Knowledge SHALL read note bytes only by resolving the `BlobRef` of the event in the blob root of
`ratatoskr-notes`, read-only, through its membership of the group `ratatoskr-notes-blobs`. It SHALL
treat a digest mismatch as a missing artifact, not as a changed file.

#### Scenario: The bytes are missing

- **WHEN** the blob that an event names is not present in the notes blob root
- **THEN** Knowledge negatively acknowledges the message with the transient delay and creates no run, verified by `services/knowledge/tests/notes_intake.rs::missing_blob_is_transient` in `ratatoskr-knowledge`
