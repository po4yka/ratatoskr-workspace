# Spec Delta

This delta requires `add-notes-write-back` (OBS-024) to be archived first.

## ADDED Requirements

### Requirement: A site owner session may register write content and nothing else

`ratatoskr-notes` SHALL accept an upload on `/v1/notes/connections/{id}/blobs` whose minted claim
names the connection's owner, the session kind `site_owner` and the origin `site:<site id>`, and
SHALL only register the blob: no change batch, no manifest, no revision and no
`evt.notes.file.changed.v1` follow from it. A change batch or a manifest with such a claim SHALL be
refused with `notes.channel_mismatch`.

#### Scenario: A site owner uploads edit content

- **WHEN** an upload with a minted claim of kind `site_owner` and origin `site:a` for the owner's connection completes, and no write follows
- **THEN** the blob is registered, and no revision and no `evt.notes.file.changed.v1` exist for it, verified by `services/notes/tests/device_channel.rs::site_owner_upload_registers_blob_only` in `ratatoskr-notes`

#### Scenario: A site owner sends a change batch

- **WHEN** a request with a minted claim of kind `site_owner` sends a change batch to `/v1/notes/connections/{id}/changes`
- **THEN** the request is refused with `notes.channel_mismatch` and nothing is recorded, verified by `services/notes/tests/device_channel.rs::site_owner_cannot_send_change_batches` in `ratatoskr-notes`

### Requirement: Edge keeps the session kind of a site upload

When Edge streams a site edit upload to `/v1/notes/connections/{id}/blobs`, the minted claim SHALL
name the session kind `site_owner` and the origin `site:<site id>`. Edge SHALL NOT present a
`site_owner` session to `ratatoskr-notes` as a primary session.

#### Scenario: The claim of a site upload

- **WHEN** a `site_owner` session of site `a` uploads through `POST /v1/sites/a/drafts/sources/{source_ref}/blobs` to a stub notes upstream
- **THEN** the stub receives a minted claim with the owner, the session kind `site_owner` and the origin `site:a`, and never the kind of a primary session, verified by `crates/public-api/tests/site_edits.rs::site_upload_claim_is_not_relabelled_as_primary` in `ratatoskr-platform`
