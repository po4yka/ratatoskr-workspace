# Design

## Context

See `proposal.md` for the motivation, and `docs/NOTES_AND_SITES.md` for the shared names. The
constraints that shape the approach:

- **The read path exists first.** `add-notes-vault-connections` (OBS-023) gives every connection one
  channel (`sync`, `plugin` or `cli`), a file index, revisions keyed by SHA-256, the device change
  and blob routes, and `evt.notes.file.changed.v1`. A `sync` connection runs the Headless client in
  `pull-only` mode.
- **A vault has many writers.** The owner's laptop, phone and Obsidian Sync can all change a file
  while Ratatoskr changes it. Obsidian Sync merges text by its own rules, which Ratatoskr cannot see
  in advance.
- **Only Edge publishes commands** (`fleet-bus-topology`). `cmd.>` is the privilege boundary.
- **Platform owns operations** (`operation-progress`, `operation-report-authority`). A domain service
  reports with `evt.platform.operation.reported.v1`, and each minted kind needs an authority row.
- **Edge is the only public listener** (Platform ADR-0015). It reverse-proxies `/v1/notes` to the
  notes domain API on loopback port 8099.
- **The broker carries 8 MiB at most**, and Edge's outbox stores every command it publishes.
- **One host.** A Raspberry Pi 5 with 15 GiB RAM. No Obsidian desktop app runs on it.

## Goals / Non-Goals

**Goals:**

- No write ever replaces a revision that its writer did not see.
- No consumer of note events ever sees a revision that the vault does not hold.
- No byte of a private note passes through Edge's outbox or the bus.
- A write reaches every device of the owner through the connection's existing channel.
- A rename through Ratatoskr leaves the vault with the same links that Obsidian would leave.

**Non-Goals:**

- Real-time co-editing of one file by two people.
- Merging binary, `.canvas` or `.base` files.
- Writing `.obsidian/`.

## Decisions

### D1. Pending writes, serialised per file, checked at the head of the queue

An accepted write is pending. Notes keeps one queue per file. A write reaches the head only after
the write before it was acknowledged or failed, and only then is its `base_hash` compared with the
current revision. A match delivers the write; a mismatch raises a conflict.

```text
 accepted ─► queued ─► head of file queue ─► base = current? ─ no ─► conflict (operation failed)
                                                 │ yes
                                                 ▼
                                            delivering ─► channel ack ─► current + file.changed
                                                 │
                                                 └─► channel refuses ─► previous stays current
```

Checking at the head, not at acceptance, makes chained edits work: an editor that saves twice sends
the second write on the hash that the first will produce, and that hash is current by the time the
second write reaches the head.

The revision becomes current only on the acknowledgement. Until then the write's bytes are a blob
named by the write, not a revision. Knowledge and automatic site publications therefore never index
content that the vault refused.

Alternatives:
- **Last writer wins:** simple, and it loses text in silence each time a phone edits offline.
  Rejected.
- **Current on acceptance, roll back on refusal:** publishes `file.changed` for content that may
  never exist in the vault, and every consumer must then undo it. Rejected.
- **A lock per file that a writer takes first:** needs every device online to take or release a
  lock, which the `plugin` and `cli` channels are not. Rejected.
- **A CRDT per file:** Obsidian Sync and the Obsidian app do not speak it, so every edit made in
  Obsidian would still arrive as a whole-file change. Rejected for now.

### D2. The conflict is a first-class record with a three-way merge proposal

Notes stores the base, the current revision and the writer's content, and computes a line-based
three-way merge (diff3) for Markdown and plain text when the base is still stored. The event carries
hashes, not content. The client reads the three sides and the proposal through
`GET /v1/notes/conflicts/{conflict_id}`. A resolution is one more write, `resolve_conflict`, so it
gets the same queue, base check, idempotency and operation report as every other write.

Alternative: let Obsidian Sync's own merge decide (`--conflict-strategy merge`). It covers only the
`sync` channel, and the owner cannot see or undo it from Ratatoskr. Rejected as the main mechanism.

### D3. Edge is the only producer; origin and ownership

The write route follows `content-capture-command`: Edge validates the body, reserves the idempotency
key, creates the operation `notes.file.write` and enqueues the command in one transaction, with
`origin` `platform`. A site edit (SITE-027) reaches the same Edge code path; Edge resolves the site's
`source_ref` to a connection and a path and sets `origin` `site:<site id>`. `ratatoskr-sites` never
publishes a command, so the `cmd.>` boundary of `fleet-bus-topology` stays as it is.

Edge holds no notes data, so it cannot know who owns a connection. Notes checks the tenant and fails
a foreign or missing connection with one code, `notes.connection.not_found`.

### D4. Content is uploaded first, never inline

The caller uploads the bytes to `/v1/notes/connections/{id}/blobs` with the shared chunked transfer
contract, which Edge streams to notes without buffering (`transfer` route class). The command then
names the notes-owned `BlobRef` and its SHA-256. A command is a few hundred bytes, the 8 MiB broker
limit is never near, and Edge's outbox and JetStream never hold a note. OBS-023 allowed the blob
route only for the connection's device; this change also allows the owner's primary session, and
only a write that the channel acknowledges turns an uploaded blob into a revision.

### D5. Delivery per channel

```text
 checked write
   ├─ sync:   lock(path) → tree hash = base? → tmp + rename → ob pushes
   │          ack = next observation of the path with the expected hash
   ├─ plugin: connection queue ─► device pulls ─► local hash = base?
   │          → vault.modify / fileManager.renameFile ─► result(hash)
   └─ cli:    connection queue ─► export-agent ─► obsidian move|rename|create|delete|
              property:set, or atomic write for update ─► result(hash)
```

- **`sync`.** Write mode on sets the Headless client to `bidirectional` with the conflict strategy
  `conflict`, so a race inside Obsidian Sync leaves a conflict file that notes indexes as a new
  file, instead of a merge that nobody reviewed. Write mode off sets `pull-only`. Each mode has its
  own fixed systemd unit: `ratatoskr-notes-sync-pull@<id>.service` while the write mode is off, and
  `ratatoskr-notes-sync-bidi@<id>.service` while it is on. Each unit names its mode and
  `--conflict-strategy conflict` as literal arguments and reads no environment file, so no file that
  the notes service writes can set the mode, `PATH`, `NODE_OPTIONS` or `LD_PRELOAD` of `ob`. The
  supervisor stops the unit of the other mode before it starts one, and does not start it when that
  stop fails; a disconnect and an expired login stop both (tasks 7.32 and 7.33). An earlier form, one
  unit that read its mode from a file that the notes service wrote, is refused by the workspace
  policy `release_artifact_callers.rs::every_template_unit_starts_only_an_allowed_program`. The
  notes service writes into the working tree as a member of `ratatoskr-notes-trees`, the group that
  `ratatoskr-notes-sync` is in too; the trees root is 2770 and the sync and login units run with
  `UMask=0007` (decision 7.11).
- **`plugin`.** The device pulls, because a phone cannot keep a connection open. The queue is
  ordered per connection, so a `rename` and a later `update` of the new path arrive in order.
  Renames use `app.fileManager.renameFile`, which updates links on the device by Obsidian's rules.
- **`cli`.** The export agent already holds a device credential and a journal. It reads the same
  queue. The Obsidian CLI needs a running app, so the agent waits for one and never launches
  Obsidian for a write.

### D6. The echo is the acknowledgement

For `sync`, the acknowledgement is the Headless client reporting the path with the expected hash.
For the device channels, the result endpoint carries it, and the matching change in the next batch
is then recognised as the same write. In both cases one write gives one revision and one
`file.changed`. When the vault reports another hash (a plugin reformatted the file on save), those
bytes become current and the expected revision never does; the operation carries the warning
`notes.write.transformed`.

### D7. Link rewrite in notes, tested against the real Obsidian

The `sync` channel has no Obsidian app on the host, so notes rewrites links itself. A rename and its
rewrites form one write group, which waits until it is at the head of every queue it touches; any
stale base stops the whole group. On the `plugin` and `cli` channels Obsidian rewrites the links on
the device, and notes' own result is the expected result that the acknowledgement must match.

The oracle is a fixture corpus recorded with the real app: a recorder copies a "before" vault,
calls `fileManager.renameFile` (the call behind `obsidian move` and `obsidian rename`), and stores
the "after" vault with the Obsidian version, the vault settings and a checksum list. Recording runs
on the owner's Mac, because it needs the desktop app; CI only replays the fixtures. The recorder is
the Obsidian CLI where the installer is 1.12.7 or later, or a recording plugin in an isolated
profile, as in OBS-023 spike 3.6.

Spike 3.6 recorded five seed cases with Obsidian 1.14.4
(`add-notes-vault-connections/spike/obsidian-1.14.4/rename-goldens/`, `alwaysUpdateLinks: true`,
`newLinkFormat: shortest`). They show three rules that the rewrite must copy:

- a relative Markdown link to the renamed file is rewritten to a bare name (`../X.md` becomes
  `X%20Renamed.md`);
- a path wikilink is shortened when the new name is unique (`[[Dir/Aliased|A]]` becomes
  `[[Aliased Renamed|A]]`);
- a move into a name collision writes the full path (`[[Collide]]` becomes
  `[[RenameTargets/Other/Epsilon]]`).

Subpaths, block references and display aliases are kept.

Alternative: run the Obsidian desktop app under Xvfb on the host and send every rename to it.
Electron on the Pi as a server dependency, upgraded by Obsidian's release schedule, is fragile.
Rejected.

### D8. Write mode is per connection and starts off

`PUT /v1/notes/connections/{id}/write-mode` is proxied to notes. Edge mints the operation
`notes.connection.write_mode` and notes reports it, because a `sync` connection must reconfigure the
Headless client before the mode is true. Turning it off fails every write that was not delivered
yet; a write already delivered finishes, because the vault may already hold it.

## Risks / Trade-offs

- [The Headless client changes a file between notes' hash check and its rename] → The window is a few
  milliseconds under the per-file lock. The conflict strategy `conflict` turns a lost race into a
  conflict file that notes indexes. The OBS-023 spike measures the client's behaviour.
- [Pending writes wait behind an offline device] → The operation shows the stage `awaiting_device`
  or `awaiting_obsidian` (decision 7.9), so the owner sees why. The queue is bounded per
  connection; when it is full, new writes fail with the retryable `notes.write.queue_full`.
- [Obsidian changes its link-update rules in a new version] → Fixtures record the Obsidian version.
  A new version is recorded again, and a diff in the fixtures is a visible change in review.
- [A device applies only part of a rename group] → The applied files become current, the operation
  fails with `notes.write.partially_applied`, and a conflict names the rest.
- [Three-way merge by lines can join two edits into a wrong sentence] → A merge is only a proposal;
  notes never applies one on its own.

## Migration Plan

There is nothing to migrate: the notes schema is edited in place, and nothing has shipped.

1. Contracts publishes `notes/write-request.v1` and `notes/conflict.v1`.
2. Notes ships the consumer with write mode off for every connection.
3. Platform ships the routes, the operation kinds, the two durables and the ACL lines. The notes
   consumer becomes ready once Edge has created its durable.
4. The plugin, the export agent and the web client ship in any order.
5. The owner turns write mode on per connection.

Rollback: turn write mode off. A `sync` connection returns to `pull-only`, undelivered writes fail,
and the read path continues.

## Open Questions

- The bound of the device queue (proposed: 10 000 operations per connection). It changes only a
  configuration value.
- How long the base revision of an open conflict is kept when retention would otherwise prune it
  (proposed: until the conflict is resolved).
