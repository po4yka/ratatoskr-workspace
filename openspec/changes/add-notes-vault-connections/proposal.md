# Proposal

## Why

Ratatoskr cannot read the owner's Obsidian vaults. On 2026-10-13 no repository mentions Obsidian,
and no service reads or writes a Markdown notes folder. The owner keeps their notes in Obsidian:
some vaults sync through Obsidian Sync, and some exist only on a device. Search, analysis and the
planned sites (`docs/NOTES_AND_SITES.md`) all need those notes as a source.

Obsidian released two official tools in 2026 that make a connection practical: Obsidian Headless
(`ob`), which syncs a vault through Obsidian Sync without the desktop app, and the Obsidian CLI
(`obsidian`), which controls a running desktop app. This change uses them and adds a plugin for the
vaults that do not use Sync.

This change is the read path only. Ratatoskr receives the vault content, indexes it, and gives it to
Knowledge. Writing back into a vault is `add-notes-write-back` (OBS-024).

## What Changes

- A spike runs first and keeps no code. It checks Obsidian Headless on the linux/arm64 host: login
  with MFA, end-to-end encryption, whether secrets can be given without argv (answered: they go on
  standard input), memory and uptime of
  `ob sync --continuous`, pull-only mode, and what happens when a file changes during a sync. It
  also checks the Obsidian terms of use for server automation, builds a plugin prototype, and
  captures golden link fixtures from the real Obsidian engine (spike 3.6 used a recording plugin,
  because the Obsidian CLI needs a newer installer).
- A new repository, `ratatoskr-notes` (Rust), owns vault connections, the file index, file
  revisions and their bytes. It joins the fleet at `repos/notes`.
- A vault connection has exactly one channel: `sync`, `plugin` or `cli`. Ratatoskr refuses a second
  channel for the same vault.
  - `sync`: the host runs `ob sync --continuous` for the connection, under a systemd template unit,
    in pull-only mode for this change.
  - `plugin`: a new Obsidian community plugin, `ratatoskr-obsidian-plugin`, pairs as a registered
    device and sends file changes through Edge. It keeps its credential outside the vault folder.
  - `cli`: `ratatoskr-export-agent` on macOS watches the vault folder and reads it through the
    Obsidian CLI.
- A `plugin` or `cli` connection has exactly one device. A second device with the same vault id is
  refused with `notes.channel_mismatch`, and the owner is pointed to Obsidian Sync.
- Edge authenticates devices and mints a claim that names the device kind. `ratatoskr-notes`
  enforces the owner and the channel of each connection.
- The Obsidian account password and the end-to-end encryption password are encrypted at rest in
  `ratatoskr-notes`, and the MFA code is never stored. The Obsidian login and the cleanup of a
  connection run as oneshot template units, and secrets reach the login unit only through systemd
  `LoadCredential=`. No secret appears in argv, logs, events or operation records.
- Connecting a vault is a Platform operation. Edge proxies the connect request, mints only the
  operation id, and keeps no part of the body. Only `ratatoskr-notes` reports on the operation.
- The notes blob root belongs to a new read group, `ratatoskr-notes-blobs`, with setgid directories
  and the umask 0027. Knowledge is a member, so it can read note bytes and no other service can.
- `ratatoskr-notes` publishes `evt.notes.vault.connected.v1`, `evt.notes.vault.disconnected.v1`
  and `evt.notes.file.changed.v1`. A file change carries the NFC path, the change kind, the revision
  hash and a `BlobRef` to the bytes.
- `ratatoskr-notes` indexes each Markdown file: frontmatter, tags, headings, block ids, aliases,
  links and embeds, resolved with Obsidian's rules. Golden fixtures from the real Obsidian engine are
  the test oracle.
- Knowledge consumes note changes the same way it consumes social sources: one analysis run per
  file revision, and derived data removed when a file is deleted or its connection is removed.
- Edge routes `/v1/notes` to `ratatoskr-notes`. The web client lists connections, connects a
  vault, and browses its files read-only.
- The host gains Node.js 22 and the `obsidian-headless` package, a new NATS identity `NOTES`, a new
  database role `ratatoskr_notes`, and the ports 8099 and 9471.

No item is **BREAKING**: nothing of this exists yet, and every existing requirement that changes
only gains a new member.

## Capabilities

### New Capabilities

- `notes-vault-connections`: how a vault is connected and disconnected, the one-channel rule, the
  custody of Obsidian secrets, the connect operation, and the connection events.
- `notes-device-channels`: how the `plugin` and `cli` channels exchange file changes with Ratatoskr
  through Edge: device pairing, change batches, file bytes, and catch-up after the device was
  offline.
- `notes-file-changes`: the `evt.notes.file.changed.v1` contract and the rules for paths,
  revisions, exclusions and ordering that every consumer can rely on.
- `notes-file-index`: what the index of a Markdown file holds, how links resolve with Obsidian's
  rules, and the read API that clients and later the sites use.
- `notes-analysis-intake`: how Knowledge turns note changes into analysis and removes derived data.

### Modified Capabilities

- `workspace-fleet-membership`: the snapshot pins nineteen product repositories, adding `notes`
  and `obsidian-plugin`.
- `postgres-provisioning`: the role list adds `ratatoskr_notes`.
- `fleet-bus-topology`: a fourteenth NATS identity `NOTES`, two Knowledge durables for note events,
  `ratatoskr-notes` as a sixth producer of `evt.platform.operation.reported.v1`, the notes upstream
  on 8099, the notes seed variable, and the notes inbox prefix.

## Repositories, in merge order

1. `ratatoskr-contracts`: the three event schemas and the operation kind. It merges first, because
   every other repository builds against them.
2. `ratatoskr-notes` (new): the service. It is created, and then it joins the fleet in the
   workspace item 9.
3. `ratatoskr-platform`: the Edge route, the two Knowledge durables, the `NOTES` identity, the
   device kind `obsidian_plugin`, and the operation authority row.
4. `ratatoskr-knowledge`: the note intake.
5. `ratatoskr-obsidian-plugin` (new): the `plugin` channel.
6. `ratatoskr-export-agent`: the `cli` channel.
7. `ratatoskr-web`: connections and read-only browse.
8. `ratatoskr-workspace`: the fleet membership of the two new repositories, the deploy roles for
   Node.js, `ob` and the template unit, the port and storage rows of `DEPLOYMENT_TARGET.md`, the
   harness checks, and the pins. It merges last, because it pins the merges above.

The order is the order of `AGENTS.md`: contracts, consumers, producers, clients, integration, pins.

This change depends on two other changes:

- `xr-021-fleet-round-5` must be archived first, because the `fleet-bus-topology` delta is written
  against the text it leaves (23 service durables, now 25).
- `add-deployment-automation` (DPL-022) must be merged and archived before tasks 14.6 and 14.7,
  because they extend its Ansible tree, Molecule scenario, freeze guard, `services.json` and
  `deploy_inventory.rs`.
Knowledge merges after Platform because its durables must exist before it can become ready.

## Outside this change

- Any write from Ratatoskr into a vault. That is OBS-024. The `sync` channel runs in pull-only
  mode until then, and the plugin and the CLI agent only send.
- Sites, publications and releases. Those are SITE-025 to SITE-027.
- Obsidian Publish. Ratatoskr does not use it.
- Running the Obsidian desktop app on the host.
- Running the deployment on the real host. The host is frozen until the owner edits
  `DEPLOYMENT_TARGET.md`.
- Indexing `.canvas` and `.base` content. They are stored and listed as files only.

## Rollback

Nothing has shipped, so there is nothing to roll back on a host. Each repository change is reverted
with `git revert`. A connection that exists on a test host is removed with its disconnect command,
which also stops its unit and deletes its working tree and its client state. The two new
repositories can be removed from the fleet by reverting the workspace item.

## Impact

- New repositories: `ratatoskr-notes` and `ratatoskr-obsidian-plugin`.
- New contracts: `notes.vault.connected.v1`, `notes.vault.disconnected.v1` and
  `notes.file.changed.v1`, and the operation kind `notes.connection.connect`.
- New on the host: Node.js 22, the `obsidian-headless` npm package at a pinned version, the system
  user `ratatoskr-notes-sync`, the template units `ratatoskr-notes-sync@.service`,
  `ratatoskr-notes-login@.service` and `ratatoskr-notes-cleanup@.service` with one polkit rule, the
  group `ratatoskr-notes-blobs`, the database role
  `ratatoskr_notes`, the NATS identity `NOTES`, and the paths under
  `/mnt/nvme/ratatoskr/notes/` and `/mnt/nvme/ratatoskr/blobs/ratatoskr-notes/`.
- A new external dependency: Obsidian Headless is an open beta with no declared license. The
  design records the exit path if it changes or goes away. Spike 3.2 found that `ob` reads both
  passwords from standard input, so no password enters argv.
