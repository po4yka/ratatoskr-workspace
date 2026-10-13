# Spec Delta

## Purpose

Defines how a device channel, the Obsidian plugin or the macOS export agent, sends the changes of a
vault to Ratatoskr through Edge, and how it catches up after it was offline.

## ADDED Requirements

### Requirement: A device channel authenticates as a paired device

The Obsidian plugin SHALL pair through Platform's device pairing as a registered device of kind
`obsidian_plugin`. The `cli` channel SHALL use the existing registered device of
`ratatoskr-export-agent`. Edge SHALL authenticate the device and SHALL forward the request to
`ratatoskr-notes` with a minted claim that names the owner, the device id and the device kind. Edge
SHALL NOT decide which connection a device may use.

#### Scenario: Edge forwards a device request

- **WHEN** a paired plugin sends a change batch through Edge to a stub notes upstream
- **THEN** the stub receives a minted claim with the owner, the device id and the device kind `obsidian_plugin`, and no client-supplied identity header, verified by `crates/public-api/tests/notes_routes.rs::device_claim_names_the_device_kind` in `ratatoskr-platform`

### Requirement: The notes service enforces the owner and the channel of a connection

`ratatoskr-notes` SHALL answer `404` to a device request for a connection of another owner. It SHALL
refuse with `notes.channel_mismatch` a device request whose device kind does not match the channel
of the connection.

#### Scenario: A plugin of another owner sends changes

- **WHEN** a paired plugin of owner A sends a change batch to a connection of owner B
- **THEN** the response is `404`, and no change is recorded, verified by `services/notes/tests/device_channel.rs::foreign_connection_changes_are_not_found` in `ratatoskr-notes`

#### Scenario: The export agent sends changes to a plugin connection

- **WHEN** the export agent of the owner sends a change batch to a connection whose channel is `plugin`
- **THEN** the request is refused with `notes.channel_mismatch`, and no change is recorded, verified by `services/notes/tests/device_channel.rs::export_agent_on_plugin_connection_is_channel_mismatch` in `ratatoskr-notes`

### Requirement: One device channel connection has exactly one device

A `plugin` or `cli` connection SHALL record the device that created it, and `ratatoskr-notes` SHALL
accept changes for it only from that device. A second device that presents the same vault id SHALL
be refused with `notes.channel_mismatch` and a message that tells the owner to use Obsidian Sync to
share a vault between devices.

#### Scenario: A second phone opens a copied vault

- **WHEN** the owner's second device, with the same vault id in the vault folder, sends a connect request or a change batch for the vault
- **THEN** it is refused with `notes.channel_mismatch` and the Sync hint, and the connection keeps its first device, verified by `services/notes/tests/device_channel.rs::second_device_for_one_connection_is_refused` in `ratatoskr-notes`

### Requirement: The plugin keeps its credential outside the vault

The Obsidian plugin SHALL NOT write its device credential, or any token derived from it, into the
vault folder, including its own `data.json`. It SHALL keep the credential in storage that the
operating system protects outside the vault.

#### Scenario: The plugin pairs and syncs

- **WHEN** the plugin pairs, connects and sends a batch in a test vault
- **THEN** no file under the vault folder contains the credential or the refresh token, verified by `tests/credential.test.ts` "credential_never_written_to_data_json" in `ratatoskr-obsidian-plugin`

### Requirement: A change batch is bounded and ordered by the device sequence

A change batch SHALL hold at most 256 changes. Each change SHALL name the NFC path, the kind
(`created`, `updated`, `renamed` with the old path, or `deleted`), the SHA-256 and byte length of
the new bytes except for `deleted`, and the device's change sequence, which SHALL increase by one
per change.

#### Scenario: A batch skips a sequence number

- **WHEN** a batch starts at sequence 12 and the last committed sequence is 10
- **THEN** nothing in the batch is committed, and the response returns `notes.channel.sequence_gap` with the committed sequence 10, verified by `services/notes/tests/device_channel.rs::sequence_gap_commits_nothing` in `ratatoskr-notes`

#### Scenario: A batch is too large

- **WHEN** a device sends 257 changes in one batch
- **THEN** the batch is refused with `notes.channel.batch_too_large`, and nothing is committed, verified by `services/notes/tests/device_channel.rs::oversized_batch_commits_nothing` in `ratatoskr-notes`

### Requirement: A repeated batch has no second effect

The response to a batch SHALL name the highest sequence that `ratatoskr-notes` committed. A batch
whose changes were already committed SHALL be accepted again without a second revision or a second
event.

#### Scenario: A batch is sent twice

- **WHEN** a device sends the same batch twice because it did not receive the first response
- **THEN** both responses name the same committed sequence, and each change produces exactly one revision and one `evt.notes.file.changed.v1`, verified by `services/notes/tests/device_channel.rs::duplicate_batch_is_idempotent` in `ratatoskr-notes`

### Requirement: Bytes arrive before the change that names them

A change whose hash names bytes that `ratatoskr-notes` does not hold SHALL be refused with
`notes.channel.bytes_missing` and the list of missing hashes. A device SHALL upload such bytes through
the shared chunked, resumable transfer contract on `/v1/notes/connections/{id}/blobs`, which Edge
serves with the `transfer` route class. `ratatoskr-notes` SHALL verify the SHA-256 of every uploaded
blob before it accepts it.

#### Scenario: Bytes with a wrong hash are uploaded

- **WHEN** a device completes an upload whose bytes do not match the declared SHA-256
- **THEN** the upload is refused with `transfer.digest_mismatch`, and no blob is registered, verified by `services/notes/tests/device_channel.rs::upload_with_wrong_digest_is_refused` in `ratatoskr-notes`

### Requirement: A device reconciles by manifest after a gap

When a device cannot prove that it observed every change, it SHALL send a manifest of every indexed
path with its hash. `ratatoskr-notes` SHALL answer with the hashes it needs, and after the device
uploads them SHALL record exactly the changes that make its copy equal to the manifest: `created`
and `updated` for new or different paths, `deleted` for paths missing from the manifest, and
`renamed` when one missing path and one new path have the same hash.

#### Scenario: The vault changed while the plugin was disabled

- **WHEN** a test vault has 20 files in Ratatoskr, then while the plugin is disabled one file is edited, one is deleted, one is renamed and one is created, and then the plugin sends a manifest
- **THEN** Ratatoskr records exactly one `updated`, one `deleted`, one `renamed` and one `created` change, verified by `services/notes/tests/device_channel.rs::manifest_reconciles_offline_changes` in `ratatoskr-notes`

### Requirement: Both device channels give the same result as the sync channel

For the same vault content, the `plugin`, `cli` and `sync` channels SHALL produce the same set of
current paths, the same revision hashes and the same index.

#### Scenario: One fixture vault through three channels

- **WHEN** the fixture vault of `ratatoskr-notes` is connected once through each channel in the integration profile
- **THEN** the three connections report equal path sets, equal hashes and equal index digests, verified by `integration/tests/notes_channel_equivalence.sh` in `ratatoskr-workspace`
