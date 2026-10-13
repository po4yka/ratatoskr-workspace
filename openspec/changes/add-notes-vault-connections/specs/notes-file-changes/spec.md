# Spec Delta

## Purpose

Defines the `evt.notes.file.changed.v1` contract: what a consumer receives when a file in a
connected vault changes, and which rules about paths, revisions, exclusions and order it can rely
on.

## ADDED Requirements

### Requirement: A file change names the path, the kind, the revision and the bytes

Every `evt.notes.file.changed.v1` SHALL carry the owner as `tenant_id`, the connection id, a stable
`file_id`, the NFC path, the kind (`created`, `updated`, `renamed` or `deleted`), the old path for
`renamed`, the revision as the lowercase hex SHA-256 of the bytes, a `BlobRef` owned by
`ratatoskr-notes` for every kind except `deleted`, the media type, and the connection sequence. It
SHALL NOT carry the file bytes or any part of the file text.

#### Scenario: A Markdown file is created

- **WHEN** a file `Projects/Plan.md` is created in a connected vault
- **THEN** one event is published with kind `created`, path `Projects/Plan.md`, a revision equal to the SHA-256 of the bytes, and a `BlobRef` whose digest equals the revision, verified by `services/notes/tests/file_events.rs::created_file_publishes_one_event_with_blob_ref` in `ratatoskr-notes`

#### Scenario: A consumer resolves the reference

- **WHEN** Knowledge reads the bytes that the `BlobRef` names from the notes blob root and hashes them
- **THEN** the hash equals the revision in the event, verified by `services/notes/tests/file_events.rs::blob_ref_digest_equals_revision` in `ratatoskr-notes`

### Requirement: Paths are NFC and collisions are refused, not merged

`ratatoskr-notes` SHALL publish every path in Unicode NFC. When two files of one connection have
paths that are equal after NFC normalisation and Unicode default case folding, the file that was
observed second SHALL get no revision and no event, and the connection SHALL report the condition
`notes.file.path_collision` with both paths.

#### Scenario: A vault holds two names that differ only in case

- **WHEN** a vault on a case-sensitive file system holds `Note.md` and `note.md`
- **THEN** exactly one of them is published, and the connection status lists `notes.file.path_collision` with both paths, verified by `crates/notes-index/tests/paths.rs::case_fold_collision_publishes_one` in `ratatoskr-notes`

#### Scenario: A macOS device sends an NFD path

- **WHEN** a device sends the path `Café.md` in NFD form
- **THEN** the event carries the NFC form, and a later change with the NFC form updates the same `file_id`, verified by `crates/notes-index/tests/paths.rs::nfd_path_is_published_as_nfc` in `ratatoskr-notes`

### Requirement: Excluded files are never published

`ratatoskr-notes` SHALL NOT publish a change for a path under `.obsidian/` or `.trash/`, under a
folder that the owner excluded for the connection, or for a file larger than the configured size
limit, whose default is 64 MiB. A file that becomes excluded SHALL be published once as `deleted`.

#### Scenario: A plugin setting changes

- **WHEN** `.obsidian/plugins/some-plugin/data.json` changes in a connected vault
- **THEN** no event is published, verified by `crates/notes-index/tests/paths.rs::obsidian_config_is_never_published` in `ratatoskr-notes`

#### Scenario: The owner excludes a folder

- **WHEN** the owner adds `Private/` to the excluded folders of a connection that has three files there
- **THEN** three `deleted` events are published, and later changes under `Private/` publish nothing, verified by `services/notes/tests/file_events.rs::excluding_a_folder_publishes_each_file_deleted_once` in `ratatoskr-notes`

### Requirement: An unchanged hash publishes nothing and the sequence has no gaps

A change whose bytes have the same SHA-256 as the current revision of that path SHALL create no
revision and SHALL publish no event. The connection sequence SHALL start at 1 for each connection
and SHALL increase by exactly one per published event of that connection, so that a consumer can
detect a missing event.

#### Scenario: A file is saved without a change

- **WHEN** a file is saved twice with identical bytes
- **THEN** only the first save publishes an event, verified by `services/notes/tests/file_events.rs::identical_bytes_publish_nothing` in `ratatoskr-notes`

#### Scenario: A consumer checks the sequence

- **WHEN** a test consumes every event of one connection after 100 mixed changes
- **THEN** the sequences are exactly 1 to the number of events, without a gap or a repeat, verified by `services/notes/tests/file_events.rs::connection_sequence_has_no_gaps` in `ratatoskr-notes`

### Requirement: The notes blob root is readable only by its read group

The blob root of `ratatoskr-notes` SHALL belong to the group `ratatoskr-notes-blobs`, and every
directory in it SHALL carry the setgid bit, so that every new file and directory has that group.
`ratatoskr-notes` SHALL write blobs with the umask 0027, so that a blob is readable by the group and
by no other user. The service user of `ratatoskr-knowledge` SHALL be a member of the group. A later
consumer joins the group through its own change.

#### Scenario: The notes service writes a blob

- **WHEN** `ratatoskr-notes` stores a new revision under a test blob root that was prepared as the deploy role prepares it
- **THEN** the new file has mode 0640 and the group `ratatoskr-notes-blobs`, and every new directory has mode 2750, verified by `services/notes/tests/blob_root.rs::new_blob_is_group_readable_and_not_world_readable` in `ratatoskr-notes`

#### Scenario: The host is provisioned

- **WHEN** Molecule converges the playbook and runs the verify case `notes_blob_read_group`
- **THEN** the group exists, the Knowledge service user is a member and can read a blob, and the service user of another repository, for example `ratatoskr-x`, cannot read it, in `ratatoskr-workspace`
