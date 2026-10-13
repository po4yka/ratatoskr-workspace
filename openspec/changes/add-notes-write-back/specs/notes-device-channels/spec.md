> Requires `add-notes-vault-connections` (OBS-023) to be archived first.

# Spec Delta

## Purpose

Lets the owner's primary session upload the content of a write to
`/v1/notes/connections/{id}/blobs`, because write content never travels inside a command. The change
and manifest routes stay reserved for the connection's device. The existing device requirements are
unchanged.

## ADDED Requirements

### Requirement: Edge forwards a session upload on the blob route

Edge SHALL forward an upload on `/v1/notes/connections/{id}/blobs` from a primary session to
`ratatoskr-notes` in the `transfer` route class, with a minted claim that names the owner and the
session kind and no device id. Edge SHALL NOT decide which connection the session may use.

#### Scenario: Edge forwards a session upload

- **WHEN** a primary session uploads bytes through Edge to `/v1/notes/connections/{id}/blobs` on a stub notes upstream
- **THEN** the stub receives a minted claim with the owner and the session kind and no device id, verified by `crates/public-api/tests/notes_routes.rs::session_upload_claim_names_the_session_kind` in `ratatoskr-platform`

### Requirement: A primary session may upload write content and nothing else

`ratatoskr-notes` SHALL accept an upload on `/v1/notes/connections/{id}/blobs` from a primary
session of the connection's owner, and SHALL refuse with `notes.channel_mismatch` a change batch or a
manifest from a primary session. A blob that a session uploaded SHALL enter the vault only through a
write that the channel acknowledges.

#### Scenario: The owner uploads write content from a browser

- **WHEN** a primary session of the owner uploads bytes to `/v1/notes/connections/{id}/blobs` and sends no write
- **THEN** the blob is registered, and no revision and no `evt.notes.file.changed.v1` exist for it, verified by `services/notes/tests/write_content.rs::uploaded_blob_is_not_a_revision` in `ratatoskr-notes`

#### Scenario: A primary session sends a change batch

- **WHEN** a primary session of the owner sends a change batch to `/v1/notes/connections/{id}/changes`
- **THEN** the request is refused with `notes.channel_mismatch` and nothing is recorded, verified by `services/notes/tests/write_content.rs::session_cannot_send_change_batches` in `ratatoskr-notes`

#### Scenario: A session of another owner uploads

- **WHEN** a primary session of owner B uploads bytes to a connection of owner A
- **THEN** the response is `404` and no blob is registered, verified by `services/notes/tests/write_content.rs::foreign_session_upload_is_not_found` in `ratatoskr-notes`
