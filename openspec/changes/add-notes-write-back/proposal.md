# Proposal

> **Owner acceptance decision, 2026-10-21.** The owner removed real Obsidian Sync acceptance from the completion criteria on 2026-10-21. This includes the MFA test environment, live propagation and race checks, recorded-session replay, and the resource, login, token and directory-mode checks that require that environment. Affected tasks close by this scope decision. These checks were not run. Product behavior, authentication, existing automated tests and the recorded TDD exceptions do not change. OBS-024 is complete under these criteria. OBS-023 tasks 3.4 (written support answers) and 3.5 (physical iOS) remain separate open work.

## Why

After `add-notes-vault-connections` (OBS-023), Ratatoskr can read a connected Obsidian vault, but it
cannot change one. The owner chose a full editor: Ratatoskr, the web client and, later, a site in
owner mode must create, edit, rename, move and delete notes, and the change must reach the vault on
every device. A vault is edited on several devices at the same time, so a write that does not know
which revision it changes will destroy text in silence. This change adds the write path with an
explicit base revision, pending writes that become current only when the vault confirms them,
conflicts that the owner resolves, and link rewriting that keeps the vault consistent after a
rename.

## What Changes

- Add the command `cmd.notes.file.write_requested.v1` (contract `notes/write-request.v1`). Edge is
  its only producer. It carries `origin` (`platform` or `site:<site id>`) and one operation:
  `create`, `update`, `rename`, `move`, `delete`, `set_property` or `resolve_conflict`. Every
  operation except `create` and `resolve_conflict` names a required `base_hash`. Every command carries an idempotency key.
- Write content never travels in a command. The caller uploads it first to
  `/v1/notes/connections/{id}/blobs`, and the command names a `BlobRef` and its hash. No byte of a
  note enters Edge's outbox or JetStream.
- An accepted write is **pending**. `ratatoskr-notes` serialises the writes of one file and checks
  the `base_hash` when a write reaches the head of the file's queue. The revision becomes current,
  and `evt.notes.file.changed.v1` is published, only after the connection's channel acknowledges the
  write. A refused delivery leaves the previous revision current. No consumer sees a phantom
  revision.
- A stale base raises a conflict with a three-way merge proposal for text and publishes
  `evt.notes.conflict.raised.v1` (contract `notes/conflict.v1`). A resolution publishes
  `evt.notes.conflict.resolved.v1`. Notes never overwrites a revision that the writer did not see.
- Each write is a Platform operation of kind `notes.file.write`; notes reports it with the existing
  `evt.platform.operation.reported.v1`.
- Notes delivers a checked write through the connection's one channel:
  - `sync`: an atomic write into the working tree under a per-file lock. The connection's write mode
    sets the Headless client to `bidirectional` (on) or `pull-only` (off).
  - `plugin`: an ordered queue that the device pulls through Edge and applies through the Obsidian
    vault API, after its own base check.
  - `cli`: `ratatoskr-export-agent` applies the operation with the Obsidian CLI.
- Echo suppression: an inbound change with the path and hash of a pending write is that write's
  acknowledgement, not a new change.
- A rename or a move rewrites every link that pointed to the old path, with the rules of Obsidian's
  "Automatically update internal links". Golden fixtures that the real Obsidian app produces are the
  test oracle.
- Edge gains `POST /v1/notes/connections/{id}/writes`, `POST /v1/notes/conflicts/{id}/resolution`
  and `PUT /v1/notes/connections/{id}/write-mode` (all class `control`). Every connection starts with
  write mode off. The web client gains an editor and a conflict view.
- The bus gains the durables `ratatoskr_notes_write_requests` (NOTES) and
  `platform_notes_conflict_projection` (EDGE), and NOTES may publish the two conflict events.

No item is **BREAKING**: nothing of the notes domain has shipped.

## Capabilities

### New Capabilities

- `notes-write-command`: the write command at the boundary: its one producer, the origin, the
  operations, the base revision, the upload-first content, pending writes per file, the outcomes,
  the conflict events, the operation report, and the routes that accept a write, a resolution and a
  write-mode change.
- `notes-write-delivery`: how a checked write reaches the vault through each channel kind, how a
  channel acknowledges or refuses it, and how an echo of Ratatoskr's own write is told apart from a
  new change.
- `notes-link-rewrite`: which links a rename or a move rewrites, how a write group becomes current,
  and the golden fixtures from the real Obsidian app against which the rewrite is tested.

### Modified Capabilities

Both deltas are written against the text that `xr-021-fleet-round-5` and then
`add-notes-vault-connections` (OBS-023) leave after archive, so both must be archived first, in that
order.

- `fleet-bus-topology`: the durable table gains `ratatoskr_notes_write_requests` (25 → 26 service
  durables); Edge's own consumers create `platform_notes_conflict_projection`; the durable-name
  agreement counts twenty-six service-owned durables and checks the projection by name; a new requirement lets NOTES publish the two
  conflict events and no command.
- `notes-device-channels`: two added requirements. Edge forwards a primary-session upload on the
  blob route with a session-kind claim, and notes accepts it from the owner, because write content is
  uploaded before the command. The change and manifest routes stay device-only. No existing
  requirement changes.

## Repositories, in merge order

1. `ratatoskr-contracts`: `notes/write-request.v1` and `notes/conflict.v1`, their fixtures, the
   generated types and the registry rows. It merges first, because every other repository builds
   against these types.
2. `ratatoskr-notes`: the write consumer, pending writes, conflicts, the merge, the write mode, link
   rewriting, delivery for `sync`, the device queue and echo suppression. It verifies its durable,
   which Edge creates in step 3, so it ships with write mode off and the consumer stays not ready
   until step 3 is deployed.
3. `ratatoskr-platform`: the Edge routes, the operation kinds and their authority rows, the two
   durables and the NATS ACL lines.
4. `ratatoskr-obsidian-plugin`: pull, apply and report for the `plugin` channel.
5. `ratatoskr-export-agent`: apply and report for the `cli` channel.
6. `ratatoskr-web`: the editor, the write-mode switch and the conflict view.
7. `ratatoskr-workspace`: the harness checks, the pins, the integration profile and the
   documentation.

Items 4, 5 and 6 depend only on 1 to 3 and can merge in any order among themselves.

## Outside this change

- Collaborative real-time editing (operational transform or CRDT).
- Merging of binary files. A conflict on an attachment, a `.canvas` or a `.base` file offers
  `keep_current`, `keep_writer` or `custom`, never a merge.
- Editing from a site. `add-site-owner-editing-and-live` (SITE-027) uses this command through Edge
  with `origin` `site:<site id>`.
- Running the Obsidian desktop app on the host. The link rewrite is implemented in notes and tested
  against fixtures.
- The `.obsidian/` configuration folder. Ratatoskr never writes it.

## Rollback

Nothing has shipped, so there is nothing to roll back on a host. Each repository change is reverted
with a normal `git revert`. When write-back must stop while the rest stays, the owner turns the
connection's write mode off. A `sync` connection then returns to `pull-only`, writes that were not
delivered fail with `notes.write.disabled`, and the read path of OBS-023 continues unchanged.

## Impact

- New contracts: `notes/write-request.v1`, `notes/conflict.v1`.
- New subjects: `cmd.notes.file.write_requested.v1`, `evt.notes.conflict.raised.v1`,
  `evt.notes.conflict.resolved.v1`.
- New durables: `ratatoskr_notes_write_requests`, `platform_notes_conflict_projection`.
- New operation kinds: `notes.file.write`, `notes.connection.write_mode`.
- New tables in the schema `notes` (edited in place; there are no migrations): write queue, conflicts,
  device operation queue, idempotency records.
- New Edge routes under `/v1/notes`.
- The `sync` channel needs write access to its working tree and changes the Headless client mode.
- New test corpus: golden link-rewrite fixtures produced by the real Obsidian app, stored in
  `ratatoskr-notes`.
