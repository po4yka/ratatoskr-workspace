# Spec Delta

## Purpose

Defines how the owner reads the source of a site's pages, how an edit made on a site reaches the
source note through the notes write path, how a conflict comes back, and how a release follows.

## ADDED Requirements

### Requirement: The owner reads the source of a page in scope

With `draft.read`, the owner session SHALL be able to read, for any note in the site's publications,
its Markdown source, an opaque `source_ref` and its current revision hash, including notes that are
not yet in a release. A `source_ref` SHALL appear only in responses to a `site_owner` session. A
request for a note outside the site's publications SHALL get the same not-found error as an unknown
note.

#### Scenario: The owner opens a published page for editing

- **WHEN** the owner session requests `GET /v1/sites/{site}/drafts/pages/{slug}` for a published page
- **THEN** the response holds the page's current Markdown source, its `source_ref` and the revision hash that the notes service reports for that file
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_edits.rs::draft_page_returns_source_ref_and_revision`

#### Scenario: The owner asks for a note of another publication

- **WHEN** the owner session requests the source of a `source_ref` that belongs to a note the owner has but no publication of this site selects
- **THEN** Platform returns the not-found error
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_edits.rs::out_of_scope_source_is_not_found`

### Requirement: Edit content reaches notes as a blob before the edit

With `notes.edit`, `POST /v1/sites/{site}/drafts/sources/{source_ref}/blobs` (budget class
`transfer`) SHALL stream the new content to the notes transfer route of the connection that holds
the `source_ref`, and SHALL return a `BlobRef` and the content hash. Platform SHALL NOT keep the
content, and SHALL NOT write it to its outbox, its logs or JetStream.

#### Scenario: Content is uploaded

- **WHEN** the owner session uploads new content for a `source_ref` in scope
- **THEN** the response holds a `BlobRef` that names the notes service as owner, and a search of Edge's outbox, logs and the JetStream stream for a marker in that content finds nothing
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_edits.rs::edit_content_never_enters_outbox_logs_or_stream`

### Requirement: An edit becomes one write command that Edge produces

`POST /v1/sites/{site}/edits` with `notes.edit` SHALL accept a `source_ref`, a `base_hash`, the
content `BlobRef`, the content hash and an idempotency key. Platform SHALL resolve the `source_ref`
through the sites scope query to a connection id and a path, open one operation, and publish one
`cmd.notes.file.write_requested.v1` with that connection id, path, `base_hash`, `BlobRef` and
`origin: "site:<site id>"`. An edit SHALL change only the content of one existing file.

#### Scenario: An edit is accepted

- **WHEN** the owner session posts an edit with the current revision hash as `base_hash` and an uploaded `BlobRef`
- **THEN** Platform returns an operation id and publishes one write command with that connection id, path, `base_hash`, `BlobRef` and origin `site:<site id>`
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_edits.rs::edit_publishes_one_write_command_with_site_origin`

#### Scenario: The edit completes only when the vault has it

- **WHEN** the notes service reports that the channel acknowledged the write
- **THEN** the owner stream receives `edit.completed` with the new revision hash, and not before
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_edits.rs::edit_completed_follows_operation_success`

#### Scenario: An edit outside the publications

- **WHEN** the owner session posts an edit for a `source_ref` outside the site's publications
- **THEN** Platform returns the not-found error and publishes no command
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_edits.rs::out_of_scope_edit_is_not_found`

### Requirement: A repeated edit is idempotent

A repeated edit request with the same idempotency key SHALL return the same operation id and SHALL
publish no further command.

#### Scenario: A retried edit

- **WHEN** the same edit is posted twice with one idempotency key
- **THEN** both responses name the same operation and one write command is published
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_edits.rs::same_idempotency_key_same_operation`

### Requirement: A conflict reaches the site and is resolved by a new edit

When the notes service raises a conflict for an edit whose origin is `site:<site id>`, Platform SHALL
send `edit.conflicted` with the operation id and the conflict id to that site's owner sessions. With
`draft.read`, the owner SHALL be able to read that conflict's base, current and proposed versions for
a file in scope. A new edit whose `base_hash` is the current revision SHALL resolve it through the
ordinary write path.

#### Scenario: The note changed in Obsidian during the edit

- **WHEN** the owner posts an edit with `base_hash` H1 while the note's current revision is already H2
- **THEN** no content is overwritten and the owner stream receives `edit.conflicted` with the operation id and the conflict id
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_edits.rs::conflict_emits_edit_conflicted`

#### Scenario: The owner resolves the conflict

- **WHEN** the owner reads the conflict and posts an edit with `base_hash` H2 and the merged content
- **THEN** the edit completes and the owner stream receives `edit.completed`
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_edits.rs::new_edit_on_current_revision_resolves_conflict`

### Requirement: A release after an edit follows the publication's release mode

In a publication whose release mode is `manual`, an edit SHALL NOT start a release, and anonymous
callers SHALL see the content of the previous release until a release is requested. In a publication
whose release mode is `automatic`, an edit SHALL reach a release only through the selected-file
change that it causes; the SITE-025 requirement "A build starts only from the owner or from a
selected file change" owns that rule, and this change adds no other trigger.

#### Scenario: An edit in a manual publication is saved but not released

- **WHEN** an edit to a note of a `manual` publication completes and no release is requested
- **THEN** an anonymous `pages.read` request returns the content of the previous release, and the owner's `draft.read` request returns the edited content
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_edits.rs::manual_edit_does_not_start_a_release`

#### Scenario: An edit in an automatic publication

- **WHEN** an edit to a note of an `automatic` publication that already has its first release completes
- **THEN** Platform publishes no `cmd.sites.release.build_requested.v1` for it
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_edits.rs::automatic_edit_publishes_no_build_command`

### Requirement: A site session can request a release in either mode

A `site_owner` session with `notes.edit` SHALL be able to post `POST /v1/sites/{site}/releases`
whatever the release mode of the site's publications. The request SHALL publish one
`cmd.sites.release.build_requested.v1` and return an operation id. Edge SHALL be the only producer of
that command.

#### Scenario: The owner publishes a manual publication from the site

- **WHEN** a `site_owner` session posts to `/v1/sites/{site}/releases` for a site whose publication is `manual`
- **THEN** one release build command is published and, when it completes, every caller with `live.release` receives `release.published`
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_edits.rs::release_request_publishes_one_build_command_in_both_modes`

#### Scenario: The owner publishes an automatic publication from the site

- **WHEN** a `site_owner` session posts to `/v1/sites/{site}/releases` for a site whose publication is `automatic`
- **THEN** one release build command is published and Platform returns an operation id
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_edits.rs::release_request_publishes_one_build_command_in_both_modes`
