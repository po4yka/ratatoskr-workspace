# Spec Delta

## Purpose

Defines how a pending write that `ratatoskr-notes` checked reaches the Obsidian vault through the
connection's one channel (`sync`, `plugin` or `cli`), how the channel acknowledges or refuses it,
and how Ratatoskr tells the echo of its own write apart from a new change in the vault.

## ADDED Requirements

### Requirement: A write is delivered only through the connection's channel

Notes SHALL deliver a checked write only through the one channel of its connection. The write SHALL
stay pending until that channel acknowledges it with the hash that the file has in the vault after
the operation.

#### Scenario: A plugin device is offline

- **WHEN** the owner writes to a `plugin` connection whose device has not connected for a day
- **THEN** the operation stays `running` with the stage `delivering` and the reason
  `awaiting_device`, and it succeeds after the device connects and acknowledges, verified by
  `services/notes/tests/delivery_plugin.rs::offline_device_delivers_on_reconnect` in
  `ratatoskr-notes`

### Requirement: An acknowledgement with another hash makes the vault's bytes current

When a channel acknowledges a write with a hash that differs from the expected hash, notes SHALL make
the acknowledged bytes the current revision and publish one `evt.notes.file.changed.v1` for them.
The expected revision SHALL never become current. The operation SHALL succeed with the acknowledged
hash and the warning `notes.write.transformed`.

#### Scenario: The vault formats the file on save

- **WHEN** a device acknowledges a write with another hash, because a plugin in the vault reformatted
  the file
- **THEN** the reformatted bytes are the current revision, exactly one event names them, and the
  operation carries `notes.write.transformed`, verified by
  `services/notes/tests/echo.rs::different_ack_hash_becomes_current`

### Requirement: A refused delivery leaves the previous revision current

When a channel refuses a write, notes SHALL keep the previous revision current, SHALL raise a
conflict when the refusal is a base mismatch, and SHALL fail the operation with the channel's typed
error otherwise.

#### Scenario: The device refuses on a base mismatch

- **WHEN** a device reports `base_mismatch` for a delivered write
- **THEN** the previous revision stays current and one conflict is raised, verified by
  `services/notes/tests/write_pending.rs::device_base_mismatch_raises_conflict`

### Requirement: The write mode sets the Headless client mode

For a `sync` connection, notes SHALL configure the Headless client with the mode `bidirectional` and
the conflict strategy `conflict` while the write mode is on, and with the mode `pull-only` while the
write mode is off.

#### Scenario: Write-back is turned off

- **WHEN** the owner turns the write mode of a `sync` connection off
- **THEN** `ob sync-config --json` for that connection reports the mode `pull-only`, verified by
  `services/notes/tests/sync_mode.rs::write_mode_off_sets_pull_only`

#### Scenario: Write-back is turned on

- **WHEN** the owner turns the write mode of a `sync` connection on
- **THEN** the recorded `ob sync-config` call names `bidirectional` and the conflict strategy
  `conflict`, verified by `sync_mode.rs::write_mode_on_sets_bidirectional`

### Requirement: The sync channel writes the working tree atomically

For a `sync` connection, notes SHALL write a file into the working tree only while it holds a
per-file lock, only after it confirmed that the file still has the hash of the write's base, and only
through a temporary file in the same folder and an atomic rename. When the file changed before the
write, notes SHALL NOT write it and SHALL raise a conflict.

#### Scenario: Sync changes the file just before the write

- **WHEN** the Headless client changes a file after its write passed the queue check and before notes
  writes it
- **THEN** notes does not write the file and raises a conflict, verified by
  `services/notes/tests/sync_write.rs::tree_change_before_write_conflicts`

#### Scenario: A reader sees a partial file

- **WHEN** another process reads a file while notes writes it
- **THEN** it reads either the old bytes or the new bytes and never a mix, verified by
  `sync_write.rs::reader_never_sees_partial_file`

### Requirement: Device channels read an ordered queue through Edge

For `plugin` and `cli` connections, notes SHALL hold checked writes in a queue ordered per
connection. The registered device SHALL read it through
`GET /v1/notes/connections/{connection_id}/device-operations?after=<cursor>` and SHALL report each
result through `POST /v1/notes/connections/{connection_id}/device-operations/{operation_id}/result`.
Only the device registered for the connection SHALL read or answer its queue.

#### Scenario: Another device reads the queue

- **WHEN** a device that is not registered for the connection reads its queue
- **THEN** the answer is `404` and no operation is disclosed, verified by
  `delivery_plugin.rs::foreign_device_reads_nothing`

#### Scenario: Operations keep their order

- **WHEN** notes queues a `rename` of `A.md` to `B.md` and then an `update` of `B.md`
- **THEN** the device receives the `rename` before the `update`, verified by
  `delivery_plugin.rs::queue_keeps_order`

### Requirement: A device checks the base before it applies

Before it applies an operation, the plugin or the export agent SHALL compare the hash of the local
file with the operation's base hash. When they differ, it SHALL NOT apply the operation, SHALL report
`base_mismatch` with the local hash, and SHALL send the local file through its change channel.

#### Scenario: The device has a newer local edit

- **WHEN** the plugin receives an `update` whose base hash differs from the local file's hash
- **THEN** the local file does not change and the plugin reports `base_mismatch`, verified by
  `test/apply-operation.test.ts::base mismatch is reported, not applied` in
  `ratatoskr-obsidian-plugin`

### Requirement: The plugin renames through Obsidian

The plugin SHALL apply a `rename` or a `move` through Obsidian's own file manager rename, so that
Obsidian updates the links on the device, and SHALL report the new hash of every file that changed.

#### Scenario: A rename on the device

- **WHEN** the plugin applies `rename` of `Projects/Alpha.md` to `Projects/Apollo.md`
- **THEN** it calls the file manager rename once, and its result lists every file whose links
  changed, verified by `test/apply-operation.test.ts::rename uses fileManager.renameFile`

### Requirement: The export agent applies operations through the Obsidian CLI

`ratatoskr-export-agent` SHALL apply `create`, `move`, `rename`, `delete` and `set_property` with
`obsidian create`, `obsidian move`, `obsidian rename`, `obsidian delete` and `obsidian property:set`
or `property:remove`. It SHALL never pass `permanent` to `obsidian delete`. It SHALL apply `update`
by an atomic file write.

#### Scenario: A rename through the CLI

- **WHEN** the agent applies `rename` of `Projects/Alpha.md` to `Projects/Apollo.md`
- **THEN** it runs `obsidian rename path=Projects/Alpha.md name=Apollo`, verified by
  `Tests/AgentCoreTests/ObsidianCliApplyTests.swift::testRenameUsesObsidianRename` in
  `ratatoskr-export-agent`

#### Scenario: A delete goes to the trash

- **WHEN** the agent applies `delete`
- **THEN** the recorded CLI arguments do not contain `permanent`, verified by
  `ObsidianCliApplyTests.swift::testDeleteNeverPermanent`

### Requirement: The export agent waits for a running Obsidian

When the Obsidian app is not running or its CLI is not enabled, the export agent SHALL leave every
operation in the queue and SHALL NOT launch Obsidian for a write. The operation SHALL stay `running`
with the stage `delivering` and the reason `awaiting_obsidian`.

#### Scenario: Obsidian is closed

- **WHEN** the agent finds no running Obsidian app
- **THEN** no operation is applied or removed from the queue, verified by
  `ObsidianCliApplyTests.swift::testClosedObsidianLeavesQueue`

### Requirement: The echo of Ratatoskr's own write is its acknowledgement

When an inbound change has the path and hash of a write that notes delivered through the same
channel and that is still pending, notes SHALL treat the change as the acknowledgement of that
write. The write's revision then becomes current, and notes SHALL publish exactly one
`evt.notes.file.changed.v1` for it.

#### Scenario: Sync brings back Ratatoskr's write

- **WHEN** notes writes a file through the `sync` channel and the Headless client reports the same
  path with the same hash
- **THEN** exactly one revision and one `evt.notes.file.changed.v1` exist for that write, verified
  by `services/notes/tests/echo.rs::own_write_is_acknowledged_once`
