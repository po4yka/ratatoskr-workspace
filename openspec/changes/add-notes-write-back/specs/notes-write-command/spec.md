# Spec Delta

## Purpose

Defines the command that asks Ratatoskr to change a file in a connected Obsidian vault, the base
revision that every change must name, the pending state of a write until the vault acknowledges it,
the outcomes a writer can observe, and the conflict events that replace a silent overwrite.

## ADDED Requirements

### Requirement: A write is one typed command with one producer

`notes.file.write_requested.v1` SHALL be a `CommandEnvelope` on `cmd.notes.file.write_requested.v1`.
`ratatoskr-platform` SHALL be its only producer and `ratatoskr-notes` its only consumer. The envelope
SHALL carry a UUIDv7 `command_id`, the aggregate `operation:<operation_id>`, the tenant
`user:<uuid>` and the schema version. The payload SHALL carry `operation_id`, `idempotency_key` (a
sha256 digest), `connection_id`, `origin` and exactly one operation.

#### Scenario: Two operations in one payload are refused

- **WHEN** a payload carries both a `rename` and a `delete`
- **THEN** it fails validation against `notes/write-request.v1`, verified by the invalid fixture
  `two-operations.json` and `crates/notes-contracts/tests/write_request.rs::two_operations_are_refused`
  in `ratatoskr-contracts`

#### Scenario: Another service is registered as a producer

- **WHEN** `contracts.toml` registers a producer other than `ratatoskr-platform` for
  `notes.file.write_requested.v1`
- **THEN** `tools/contractsc/tests/live_message_types.rs::notes_write_request_has_one_producer` in
  `ratatoskr-contracts` fails and names the extra producer

### Requirement: The origin names who asked for the write

`origin` SHALL be `platform` for a write that the owner sent through the Ratatoskr API, or
`site:<site id>` for a write that the owner sent from a site. Any other value SHALL be refused.
Notes SHALL record the origin with the write, and SHALL repeat it in a conflict that the write
raises.

#### Scenario: An origin outside the two forms

- **WHEN** a payload carries `origin` `"site:"` or `"web"`
- **THEN** it fails validation, verified by the invalid fixtures `empty-site-origin.json` and
  `unknown-origin.json` and `write_request.rs::origin_has_two_forms`

#### Scenario: A conflict names the origin

- **WHEN** a write with `origin` `site:docs` ends in a conflict
- **THEN** `evt.notes.conflict.raised.v1` carries `origin` `site:docs`, verified by
  `services/notes/tests/conflict_merge.rs::conflict_repeats_the_origin` in `ratatoskr-notes`

### Requirement: Each file operation has its required fields

A file operation SHALL be one of `create` (path, `blob`), `update` (path, `base_hash`, `blob`),
`rename` and `move` (path, `base_hash`, target path), `delete` (path, `base_hash`) and
`set_property` (path, `base_hash`, frontmatter key, and either a `BlobRef` of an `application/json`
value, uploaded to notes first, or the instruction to remove the key). The content field is `blob`.
An operation that lacks a required field SHALL be refused.

#### Scenario: An update without a base hash is refused

- **WHEN** a producer serialises an `update` operation without `base_hash`
- **THEN** the payload fails validation, verified by the invalid fixture
  `update-without-base-hash.json` and `write_request.rs::update_requires_base_hash`

### Requirement: A conflict resolution names its conflict and its choice

A `resolve_conflict` operation SHALL carry the conflict id, the choice, and `blob` exactly when the
choice is `custom`. It carries no `base_hash`, because notes checks the resolution against the
current revision that the conflict recorded. A resolution that lacks a required field or carries
`blob` with another choice SHALL be refused.

#### Scenario: A custom resolution without content is refused

- **WHEN** a `resolve_conflict` operation has the choice `custom` and no `blob`, or another choice
  and a `blob`
- **THEN** the payload fails validation, verified by the invalid fixtures
  `custom-resolution-without-content.json` and `blob-without-custom-resolution.json` and
  `write_request.rs::custom_resolution_requires_content`

### Requirement: Paths stay inside the vault and outside its configuration

Every path and target path in a write SHALL be relative to the vault root. A path that is absolute,
that contains a `..` segment, or whose first segment is `.obsidian` in any letter case SHALL be
refused. A folder whose name only starts with `.obsidian`, such as `.obsidian-archive`, is not the
configuration folder.

#### Scenario: A path leaves the vault

- **WHEN** a payload names `../secrets.md`, `/Projects/Plan.md` or `.obsidian/app.json`
- **THEN** the payload fails validation and notes records nothing, verified by the invalid fixtures
  `parent-segment.json`, `absolute-path.json` and `config-folder.json` and
  `write_request.rs::paths_stay_inside_the_vault`

#### Scenario: The configuration folder is refused in any letter case

- **WHEN** a payload names `.OBSIDIAN/app.json`, `.Obsidian/x` or the bare name `.obsidian`
- **THEN** the payload fails validation, verified by the invalid fixtures
  `config-folder-uppercase.json`, `config-folder-mixed-case.json` and `config-folder-bare.json` and
  `write_request.rs::config_folder_is_refused_in_any_case`, and a payload that names
  `.obsidian-archive/Plan.md` is accepted, verified by the valid fixture `obsidian-like-folder.json`

### Requirement: Write content never travels in the command

Content, and the value that a `set_property` sets, SHALL be a `BlobRef` owned by `ratatoskr-notes`
with its SHA-256, which the caller uploaded first through
`/v1/notes/connections/{connection_id}/blobs`. The `BlobRef` of a property value SHALL have the media
type `application/json`. A payload that carries content or a property value inline SHALL be refused.
No byte of a note SHALL enter Edge's outbox or JetStream.

#### Scenario: Inline content is refused

- **WHEN** a payload carries the file text in a string field instead of a `BlobRef`
- **THEN** it fails validation, verified by the invalid fixture `inline-content.json` and
  `write_request.rs::content_is_a_blob_ref`

#### Scenario: An inline property value is refused

- **WHEN** a `set_property` carries the JSON value itself, or a `BlobRef` whose media type is not
  `application/json`
- **THEN** it fails validation, verified by the invalid fixtures `inline-property-value.json` and
  `property-value-not-json.json` and `write_request.rs::property_value_is_a_blob_ref`

#### Scenario: A marker in the note never reaches the bus

- **WHEN** the owner uploads a note that holds a unique marker string and sends a write that names
  it
- **THEN** neither Edge's outbox row nor the published envelope contains the marker, verified by
  `crates/public-api/tests/notes_writes.rs::write_command_carries_no_file_bytes` in
  `ratatoskr-platform`

#### Scenario: The named blob is missing

- **WHEN** a write names a `BlobRef` whose bytes notes does not hold
- **THEN** the operation fails with `notes.write.content_missing` and no revision changes, verified by
  `services/notes/tests/write_content.rs::missing_blob_fails_the_write`

### Requirement: A write is pending and serialised per file

An accepted write SHALL be pending. Notes SHALL process the writes to one file one at a time, in the
order it accepted them. A write SHALL reach the head of its file's queue only after the write before
it was acknowledged by the channel or failed.

#### Scenario: Two quick edits of one note

- **WHEN** an editor sends `update` A on revision H0 and then `update` B on the hash that A will
  produce, before A is acknowledged
- **THEN** B waits until A is acknowledged, then passes its base check, and both succeed in order,
  verified by `services/notes/tests/write_queue.rs::chained_edits_apply_in_order` in
  `ratatoskr-notes`

### Requirement: The base is checked at the head of the queue

When a write reaches the head of its file's queue, notes SHALL compare its `base_hash` with the hash
of the current revision. On a match notes SHALL deliver the write. On a mismatch notes SHALL raise a
conflict, SHALL keep the writer's content only as the writer's side of that conflict, and SHALL NOT
change the current revision.

#### Scenario: A write on an old revision does not overwrite

- **WHEN** the vault changed a file after the writer read it, and the writer sends `update` with the
  older `base_hash`
- **THEN** the current revision stays unchanged, no `evt.notes.file.changed.v1` is published for the
  write, and the outcome is `conflict`, verified by
  `services/notes/tests/write_base_hash.rs::stale_base_makes_a_conflict`

### Requirement: A revision becomes current only after the channel acknowledges it

The revision that a write produces SHALL become current, and notes SHALL publish
`evt.notes.file.changed.v1` for it, only after the connection's channel acknowledged the write. A
pending write SHALL NOT be visible to a consumer of note events or to a read of the current file.

#### Scenario: Knowledge never sees a phantom revision

- **WHEN** a write is delivered and the channel refuses it
- **THEN** no `evt.notes.file.changed.v1` names the write's hash, and a read of the file returns the
  previous revision, verified by
  `services/notes/tests/write_pending.rs::refused_delivery_publishes_nothing`

#### Scenario: An acknowledged write is published once

- **WHEN** the channel acknowledges a write with the expected hash
- **THEN** the revision becomes current and exactly one `evt.notes.file.changed.v1` names it, verified
  by `write_pending.rs::acknowledged_write_publishes_once`

### Requirement: A create never takes a path that exists

Notes SHALL deliver `create` only when, at the head of the queue, no live file has the same
case-folded, NFC-normalised path. Otherwise the outcome SHALL be `conflict`.

#### Scenario: Two creates race for one path

- **WHEN** two writers send `create` for `Ideas/Plan.md` and `ideas/plan.md`
- **THEN** exactly one is delivered and the other ends with the outcome `conflict`, verified by
  `write_base_hash.rs::case_folded_create_collision`

### Requirement: The same idempotency key gives the same result

A command whose `idempotency_key` and `connection_id` equal those of an earlier command SHALL NOT
queue its operation again, and notes SHALL report the earlier outcome again. The same key with a
different payload SHALL be refused as permanently invalid and SHALL change nothing.

#### Scenario: A writer retries after a timeout

- **WHEN** a writer sends the same `update` with the same idempotency key twice
- **THEN** one write is queued and both operations report the same outcome, verified by
  `services/notes/tests/write_idempotency.rs::retry_returns_same_revision`

#### Scenario: A key is reused with other content

- **WHEN** a writer reuses an idempotency key with different content
- **THEN** notes refuses the second command and the current revision does not change, verified by
  `write_idempotency.rs::reused_key_with_other_content_is_invalid`

### Requirement: A conflict event names all three sides

For the outcome `conflict`, notes SHALL publish `evt.notes.conflict.raised.v1` (contract
`notes/conflict.v1`) with the conflict id, the connection id, the path, the origin, the writer's
base hash, the current revision hash and the hash of the writer's content. The event SHALL carry
hashes and SHALL NOT carry file content.

#### Scenario: A conflict is raised

- **WHEN** an `update` ends with the outcome `conflict`
- **THEN** exactly one `evt.notes.conflict.raised.v1` names the three hashes and its payload holds no
  file content, verified by `conflict_merge.rs::conflict_event_carries_hashes_only`

### Requirement: A text conflict carries a three-way merge proposal

For a Markdown or plain-text file whose base revision is still stored, the conflict SHALL carry a
three-way merge proposal: the hash of the merged content and whether the merge has overlapping hunks.
For any other file the conflict SHALL carry no merge proposal. Notes SHALL never apply a merge
proposal on its own.

#### Scenario: A text conflict without overlap

- **WHEN** the vault changed the first paragraph and the writer changed the last paragraph of one base
- **THEN** the proposal has no overlapping hunks and its content holds both changes, verified by
  `conflict_merge.rs::disjoint_edits_merge_cleanly`

#### Scenario: A conflict on an attachment

- **WHEN** two writers change `assets/photo.png` from one base
- **THEN** the conflict carries no merge proposal, verified by
  `conflict_merge.rs::attachment_conflict_has_no_proposal`

### Requirement: A resolution is a write on the current revision

A conflict SHALL stay open until a `resolve_conflict` operation names `keep_current`,
`keep_writer`, `accept_merge` or `custom`. `accept_merge` SHALL be refused for a conflict without a
proposal. A resolution SHALL be queued and checked like any other write, and when the channel
acknowledges it, notes SHALL publish `evt.notes.conflict.resolved.v1` with the conflict id and the
resulting revision hash.

#### Scenario: A resolution races a new vault change

- **WHEN** the owner resolves a conflict while the vault changes the same file again
- **THEN** a second conflict is raised and nothing is overwritten, verified by
  `conflict_merge.rs::resolution_races_vault_change`

### Requirement: Every write is a Platform operation

A write SHALL be a Platform operation of kind `notes.file.write`. Notes SHALL report it through
`evt.platform.operation.reported.v1`: `running` with the stage `queued` or `delivering`, `succeeded`
with the new revision hash after the acknowledgement, and `failed` with a typed error otherwise. A
conflict SHALL be `failed` with the non-retryable code `notes.write.conflict` and the conflict id.

#### Scenario: A client follows a write to the end

- **WHEN** a client sends a write and reads the operation stream
- **THEN** it sees `accepted`, `running` and `succeeded` in that order, and the result names the new
  revision hash, verified by `services/notes/tests/write_operation.rs::write_reports_to_success`

#### Scenario: A client reads a conflict

- **WHEN** a write ends in a conflict
- **THEN** the operation is `failed` with `notes.write.conflict`, and its error names a conflict id
  that `GET /v1/notes/conflicts/{conflict_id}` returns, verified by
  `write_operation.rs::conflict_fails_with_its_id`

### Requirement: Edge accepts a write as an operation

Edge SHALL accept `POST /v1/notes/connections/{connection_id}/writes` and
`POST /v1/notes/conflicts/{conflict_id}/resolution` only from an authenticated session with an
`Idempotency-Key` header of 1 to 255 characters. It SHALL answer `202` with the operation id after
one transaction that reserves the key, creates the operation and enqueues the command with the
session's user as tenant and `origin` `platform`. The resolution body names `connection_id`,
`choice` and, for `custom`, `blob`.

#### Scenario: The idempotency key is missing

- **WHEN** a session posts a write without an `Idempotency-Key` header
- **THEN** Edge answers `400 platform.request.idempotency_key_required` and no operation is created,
  verified by `crates/public-api/tests/notes_writes.rs::write_requires_idempotency_key` in
  `ratatoskr-platform`

#### Scenario: The body does not validate

- **WHEN** a session posts a body that fails `notes/write-request.v1`
- **THEN** Edge answers `400 platform.request.invalid` and no command is enqueued, verified by
  `notes_writes.rs::invalid_body_is_refused`

### Requirement: One idempotency key names one write across the two write routes

One `Idempotency-Key` SHALL name one write across `.../writes` and `.../resolution`. A key reused
with another request on either route SHALL be refused with
`409 platform.request.idempotency_conflict`, and the same request sent again SHALL replay its answer.

#### Scenario: A key names one write across the two routes

- **WHEN** a session sends a resolution with an `Idempotency-Key` that a write already took
- **THEN** Edge answers `409 platform.request.idempotency_conflict`, and the first request sent again
  with the same key replays its answer, verified by
  `notes_writes.rs::a_key_is_one_write_across_the_write_and_resolution_routes`

### Requirement: Notes checks ownership and write mode

Notes SHALL check that the command's tenant owns the connection or the conflict. A foreign or
missing connection SHALL fail the operation with the one code `notes.connection.not_found`, so that
another user's connection is not disclosed. A connection whose write mode is off SHALL fail the
operation with `notes.write.disabled`. Neither failure SHALL change a revision.

#### Scenario: Another user names a connection

- **WHEN** a session of user B posts a write to a connection of user A
- **THEN** the operation fails with `notes.connection.not_found` and no revision of user A changes,
  verified by `services/notes/tests/write_authority.rs::foreign_connection_is_not_found`

#### Scenario: Write-back is off

- **WHEN** the owner writes to a connection whose write mode is off
- **THEN** the operation fails with `notes.write.disabled` and the vault is not changed, verified by
  `write_authority.rs::write_mode_off_is_refused`

### Requirement: The owner turns write mode on or off

Every connection SHALL start with write mode off. Edge SHALL proxy
`PUT /v1/notes/connections/{connection_id}/write-mode` (route class `control`, body
`{"write_mode":"on"|"off"}`, `Idempotency-Key` required) to notes and SHALL answer `202` with an
operation of kind `notes.connection.write_mode`, which notes reports. Turning write mode off SHALL
fail every write not yet delivered with `notes.write.disabled`.

#### Scenario: Write-back is turned on

- **WHEN** the owner sends `PUT .../write-mode` with `on` for a connection of their own
- **THEN** the operation succeeds and a following write is delivered, verified by
  `services/notes/tests/write_mode.rs::turning_on_enables_writes`

#### Scenario: Write-back is turned off with writes waiting

- **WHEN** the owner turns write mode off while two writes wait in a file's queue
- **THEN** both fail with `notes.write.disabled` and the current revision does not change, verified by
  `write_mode.rs::turning_off_fails_waiting_writes`

#### Scenario: Another user toggles write mode

- **WHEN** a session of user B sends `PUT .../write-mode` for a connection of user A
- **THEN** the operation fails with `notes.connection.not_found` and the mode does not change, verified
  by `write_mode.rs::foreign_toggle_is_not_found`

#### Scenario: The route has its class

- **WHEN** Edge's route table is loaded
- **THEN** `PUT /v1/notes/connections/{connection_id}/write-mode` is in the class `control` and
  requires an `Idempotency-Key`, verified by
  `crates/public-api/tests/notes_writes.rs::write_mode_route_is_control_class` in
  `ratatoskr-platform`
