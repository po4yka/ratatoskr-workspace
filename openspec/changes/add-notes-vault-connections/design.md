# Design

> **Owner acceptance decision, 2026-10-21.** The owner removed real Obsidian Sync acceptance from the completion criteria on 2026-10-21. This includes the MFA test environment, live propagation and race checks, recorded-session replay, and the resource, login, token and directory-mode checks that require that environment. Affected tasks close by this scope decision. These checks were not run. Product behavior, authentication, existing automated tests and the recorded TDD exceptions do not change. OBS-024 is complete under these criteria. The owner also removed physical iOS checks and written support answers from acceptance. Those iOS checks were not run and the replies were not received. Tasks 3.4 and 3.5 close by this decision, and OBS-023 is complete.

## Context

See proposal.md for the motivation. `docs/NOTES_AND_SITES.md` holds the shared names: repositories,
subjects, routes, ports and storage paths. ADR-0010 records the decision to create a notes bounded
context and to use Obsidian's own clients.

The constraints that shape this design:

- One host, a Raspberry Pi 5 with four cores and 15 GiB shared with other tenants
  (`docs/DEPLOYMENT_TARGET.md`). Every new process must justify its memory.
- Each service owns one schema in the database `ratatoskr`, its own blob root, and its own NATS
  identity (`postgres-provisioning`, `blob-references`, `fleet-bus-topology`).
- Public clients talk only to Edge. Edge authenticates and mints claims for the domain service
  (Platform ADR-0015). Devices pair through Platform ADR-0016.
- The fleet has no Node.js runtime on the host today. Obsidian Headless needs Node.js 22.

## Goals / Non-Goals

**Goals:**

- Every connected vault has a complete, current copy in Ratatoskr: bytes, revisions and an index.
- The three channels give the same events and the same index for the same vault content.
- Obsidian secrets stay inside `ratatoskr-notes` and the one process that needs them.
- Knowledge can search and analyse notes with the intake pattern it already has.

**Non-Goals:**

- Writing into a vault. The data model keeps `base_hash` from the start so that OBS-024 adds the
  write path without a schema redesign, but no write route exists in this change.
- Real-time collaboration inside one note.
- A Ratatoskr UI inside Obsidian beyond pairing and status.

## Decisions

### D1. A new bounded context, `ratatoskr-notes`

Notes are owner-authored content with their own lifecycle: connections, revisions, conflicts later,
and publications later. Knowledge analyses content that other services own and must not become the
owner of user-authored files. `ratatoskr-vault` backs up Git repositories and shares only the word.

Alternatives:
- Put notes in Knowledge. Rejected: Knowledge would own source bytes and the Obsidian secrets, and
  every other producer keeps its source outside Knowledge.
- Put notes in `ratatoskr-vault`. Rejected: a different domain, and the name collision would grow.

### D2. One connection, one channel

A connection records `channel` as one of `sync`, `plugin` or `cli`, and a **vault key** that
identifies the vault. For `sync` the key is the remote vault id that `ob sync-list-remote` reports.
For `plugin` and `cli` it is a random id that the device writes into
`.obsidian/plugins/ratatoskr/vault-id` or into the export-agent settings on the first pairing.
`ratatoskr-notes` refuses a second active connection with the same owner and vault key, whatever its
channel.

A plugin that finds that its vault already has a `sync` connection switches to status-only mode: it
shows the connection and sends nothing. Two channels on one vault would deliver each change twice,
and in OBS-024 they would also echo each write.

Alternative: allow several channels and deduplicate by hash. Rejected: deduplication cannot order
two different edits that arrive through two channels, so the result would depend on timing.

### D3. The `sync` channel runs Obsidian Headless under systemd

Each `sync` connection gets one unit instance, `ratatoskr-notes-sync@<connection id>.service`. The
unit runs `ob sync --continuous --path /mnt/nvme/ratatoskr/notes/trees/<id>` as the system user
`ratatoskr-notes-sync`, with `HOME=/mnt/nvme/ratatoskr/notes/clients/<id>` (the client state, mode
0700). Owner decision B of 2026-10-14 put the trees and the client states under two roots: the
trees root is setgid with the group `ratatoskr-notes-trees`, whose only member is
`ratatoskr-notes`, and the sync and login units run with `UMask=0027`, so a tree is 2750 with files
0640 and the notes service reads it through the group. The clients root is 0700.
`ratatoskr-notes` starts, stops and inspects the instances through the systemd D-Bus API with one
polkit rule. The rule allows only three template units: `ratatoskr-notes-sync@*.service`
(the continuous sync), `ratatoskr-notes-login@*.service` (a oneshot unit that runs `ob login` and
`ob sync-setup`, D4) and `ratatoskr-notes-cleanup@*.service` (a oneshot unit that runs
`ob sync-unlink` and deletes the working tree and the client state of a removed connection). In this
change the
connection is configured with `ob sync-config --mode pull-only --configs "" --excluded-folders
<owner list>`, and `--device-name ratatoskr-<connection id>`.

OBS-024 (`add-notes-write-back`, design D5 and decision 7.11) changes this decision at the notes pin
`f394346`: the one sync unit is replaced by two fixed units, `ratatoskr-notes-sync-pull@*.service`
(write mode off) and `ratatoskr-notes-sync-bidi@*.service` (write mode on), each with its mode as a
literal argument, so the polkit rule allows four template units. `ratatoskr-notes-sync` joins the
group `ratatoskr-notes-trees`, the trees root is 2770, and the sync and login units run with
`UMask=0007`, so a tree is 2770 with files 0660.

`ratatoskr-notes` takes file changes only from the working tree, never from the output of `ob`. It
watches the tree with inotify, with a full rescan at start and every 15 minutes, and turns each
settled file state into a revision. A file is settled when its size and modification time have not
changed for 2 seconds.

Spike 3.2 (`spike/3.2-obsidian-headless.md`, `obsidian-headless` 0.0.14) found that `ob` keeps its
state under `${XDG_CONFIG_HOME:-$HOME/.config}/obsidian-headless` on Linux. The unit therefore sets
`XDG_CONFIG_HOME` to the connection's client state directory. The client state is plaintext:
`auth_token` and `sync/<vault id>/config.json`, which holds the derived end-to-end key, both mode
0600. The 0700 client state directory and its owner `ratatoskr-notes-sync` are the only protection,
so no other service user may share that owner.

The spike also found that an expired or revoked login does not stop `ob sync --continuous`. It logs
`Failed to authenticate:` and tries again for ever. It waits 5 seconds after the first failure, and
the wait grows up to 5 minutes. `ob sync` has no `--json` output. Therefore the supervisor reads one
thing from the unit's journal: the authentication failure line. The sync unit logs to its own
journal namespace, `ratatoskr-notes-sync` (`LogNamespace=`, owner decision A of 2026-10-14). The
service follows that namespace with one `journalctl` process and sends each line to its connection
by the trusted field `_SYSTEMD_UNIT`. An ACL from the deploy role gives the group `ratatoskr-notes`
read access to that namespace only; when the service cannot read it, it logs
`notes.sync.journal_unreadable` at its start. After the line repeats for 5 minutes, the supervisor
stops the unit and marks the connection `login_expired` (`notes.sync.login_expired`). The line and
the 5-minute rule are PROVISIONAL: they come from the code of `ob` 0.0.14, and the wait of up to 5
minutes can make the line appear only once in 5 minutes. Spike 3.3 checks both against a real
recording. The owner must then connect again. The supervisor
reads no other line, and it never takes file content from the log. The version of
`obsidian-headless` is pinned, because a release can change these lines.

Alternatives:
- Spawn `ob` as child processes of `ratatoskr-notes`. Rejected: a crash of the service would stop
  every sync, and systemd already gives restart, resource limits and journal capture.
- Implement the Sync protocol in Rust. Rejected: the protocol is not documented and it uses
  end-to-end encryption whose details Obsidian can change.
- Run the Obsidian desktop app under Xvfb. Rejected: Electron as a server dependency, more memory,
  and a GUI upgrade path.

### D4. Secret custody

The connect flow on the web client sends the Obsidian email, password, MFA code and end-to-end
password to Edge. Edge proxies the request to `ratatoskr-notes` over loopback with the minted claims
and the operation id that it mints. Edge keeps no part of the body: not in its database, its outbox,
its idempotency or audit records, or its logs. The Platform test
`connect_body_is_not_persisted_or_logged` proves it. `ratatoskr-notes` then:

1. encrypts the account password and the end-to-end password with XChaCha20-Poly1305 under the key
   in `/etc/ratatoskr/notes-secrets.key` (mode 0400, owner `ratatoskr-notes`), and stores the
   ciphertext in `notes.connection_secrets`. The MFA code is never stored.
2. writes each secret that the login needs to a file under
   `/run/ratatoskr-notes/credentials/<connection id>/` (tmpfs, mode 0700, owner `ratatoskr-notes`),
   and starts `ratatoskr-notes-login@<connection id>.service`. The unit reads the files with
   `LoadCredential=`, so systemd gives them to the unit in `$CREDENTIALS_DIRECTORY` and no other
   user can read them. `ratatoskr-notes` deletes the files when the unit stops, whatever its result.
3. the login unit gives the secrets to `ob` on standard input. Spike 3.2 confirmed that when stdin
   is not a terminal, `ob login` reads the whole of stdin as the account password, and
   `ob sync-setup` without `--json` reads it as the end-to-end password. Each command reads one
   value, so the unit runs them as two steps:
   `ob login --email <email> --mfa <code> < $CREDENTIALS_DIRECTORY/password`, then
   `ob sync-setup --vault <id> --path <tree> --device-name ratatoskr-<id> < $CREDENTIALS_DIRECTORY/e2e`.
   The email and the MFA code are in argv. The email is not a secret. The MFA code is a short-lived
   one-time code and is never stored. No password is ever in argv, so the
   `hidepid=invisible` fallback is not needed, and the login unit runs as `ratatoskr-notes-sync`,
   the owner of the client state and the working tree, which it must write.
4. after the setup succeeds, keeps only the client state that `ob` writes in
   `/mnt/nvme/ratatoskr/notes/clients/<id>`. The
   continuous unit needs no password.

Secrets never appear in an event, an operation report, a log line or an error message. A failed
login reports one of the stable codes `notes.sync.login_failed`, `notes.sync.mfa_required`,
`notes.sync.e2e_password_wrong` or `notes.sync.vault_not_found`. The marker tests are split by
repository: `marker_secrets_appear_nowhere_in_notes` in `ratatoskr-notes` (its tables, its outbox,
its journal and that of its units, and its events) and `connect_body_is_not_persisted_or_logged` in
`ratatoskr-platform`.

A private PID namespace for the login (`PrivatePIDs=`) is not used: it needs systemd 257, and the
host runs Debian 12 with systemd 252.

Alternative: keep no ciphertext and ask the owner again when the client state expires. Spike 3.2
showed that `ob sync` never needs the password again after setup, so this alternative is now
possible. The choice waits for spike 3.1, which measures how long a login token lives: if the token
does not expire in normal use, step 1 stores nothing, and a `login_expired` connection asks the
owner to connect again. Until 3.1 runs, the ciphertext path stays the plan.

Spike 3.2 also found the undocumented variable `OBSIDIAN_AUTH_TOKEN`, which replaces the token
file. It is not used, because it is undocumented and could be removed in a later release.

### D5. The `plugin` channel

The plugin pairs through Platform's pairing flow (ADR-0016) as a registered device of the new kind
`obsidian_plugin`. It keeps the device credential outside the vault folder, in storage that the
operating system protects. On desktop, spike 3.5 found `app.secretStorage` in Obsidian 1.14.4
(`setSecret`, `getSecret`, `deleteSecret`, `isEncryptionAvailable`). It encrypts with Electron
`safeStorage`, the macOS Keychain format `v10`, into the app profile's Local Storage outside the
vault, scoped to the vault id. On an older app, the fallback is `remote.safeStorage`, with the
ciphertext kept through `saveLocalStorage`. `saveData` writes `data.json` inside the vault and is
never used for the credential. Mobile storage has no physical iOS measurement. The owner removed that part of 3.5
from acceptance on 2026-10-21. It never writes the credential into `data.json` or any other file in the
vault, because the vault itself syncs to other devices and services. If a platform has no protected
storage, the plugin keeps the credential in memory only, and the owner pairs again after a restart.

Edge authenticates the device and forwards each request with a minted claim that names the owner, the
device id and the device kind. Edge does not decide which connection a device may use.
`ratatoskr-notes` enforces it: a connection of another owner answers `404`, and a device whose kind
does not match the channel answers `notes.channel_mismatch`. A `plugin` or `cli` connection records
the device that created it and accepts changes only from that device. A second device that presents
the same vault id, for example because the vault folder was copied or synced by another tool, is
refused with `notes.channel_mismatch` and a message that points the owner to Obsidian Sync.

The plugin then talks only to Edge:

- `POST /v1/notes/connections` with `channel = plugin` and its vault key creates the connection.
- `POST /v1/notes/connections/{id}/changes` sends a batch of up to 256 changes. Each change names
  the path, the kind (`created`, `updated`, `renamed` with the old path, `deleted`), the SHA-256 of
  the new bytes, the byte length, and the device's monotonic change sequence.
- Bytes that Ratatoskr does not already hold go through the shared chunked, resumable transfer
  contract on the `transfer` route class (`/v1/notes/connections/{id}/blobs`), before the batch that
  names them.
- The response names the highest sequence that `ratatoskr-notes` committed. The plugin resends from
  there after a restart or after it was offline.
- At pairing, and whenever the plugin cannot prove that it saw every change (for example after an
  edit while the plugin was disabled), it sends a manifest of every path and hash.
  `ratatoskr-notes` answers with the paths whose bytes it needs, and turns the difference into
  changes.

The plugin uses the vault API events `create`, `modify`, `rename` and `delete`. Spike 3.5 measured
them on desktop (`spike/obsidian-1.14.4/events.jsonl`):

- A rename inside Obsidian gives one `rename` event with the old path. A folder rename gives one
  `rename` for the folder and then one `rename` per file inside it. The plugin skips the folder
  event and sends the file events, so each file moves once.
- After a rename, Obsidian may rewrite links in other notes. Those arrive as `modify` events and
  become ordinary `updated` changes.
- A rename made outside Obsidian, for example in Finder, arrives as `create` for the new path and,
  about one second later, `delete` for the old path. The plugin pairs the two by content hash
  within a 3-second window and sends one `renamed` change. Unpaired events are sent as they are.
- Event paths are NFC, even when the name on disk is NFD. A file that Obsidian creates gets an NFC
  name on disk, while a file created outside keeps its NFD name. The plugin sends the NFC path, and
  `ratatoskr-notes` keys files by the NFC path, as in D7.
- A move to the trash (`vault.trash`) gives the same events as a delete.

### D6. The `cli` channel

`ratatoskr-export-agent` gains a vault mode for macOS. It watches the vault folder with FSEvents,
reads files from disk, and uses the Obsidian CLI only to confirm renames and to read the vault id
(`obsidian vault=<name> vault`) when the app is running. It uses the same routes and the same batch
format as the plugin, with device kind `export_agent`. When the app is not running, the agent still
reports changes from the file system, and marks a delete plus create with equal hash as a rename.

### D7. Paths, revisions and exclusions

- A path is stored and published in Unicode NFC. Its **path key** is the NFC path folded with Unicode
  default case folding. Two files whose path keys are equal make the second one a collision: it is
  recorded, it gets no revision, and the connection reports `notes.file.path_collision`.
- `.obsidian/`, `.trash/`, the owner's excluded folders, and files larger than 64 MiB are not
  indexed. The size limit is a configuration value with that default.
- A revision is the SHA-256 of the bytes. A change whose hash equals the current revision of that
  path creates no new revision and publishes no event.
- Each connection has a gapless `connection_sequence`. Each `evt.notes.file.changed.v1` carries it,
  so that a consumer can detect a gap after a redelivery.

### D8. The index and link resolution

The index parses Markdown with a CommonMark parser plus the Obsidian extensions: wikilinks,
embeds, block ids, tags in text and in frontmatter, callouts, and `%% comments %%`. Spike 3.6
(`spike/obsidian-1.14.4/`) measured these rules on Obsidian 1.14.4:

- Resolution: an exact path wins, then a file of that name in the linking file's own folder, then a
  unique name, then the shortest path among equal names. Matching ignores case, `[[Name.md]]`
  resolves, and partial paths such as `[[2024/Alpha]]` resolve. Markdown links resolve relative to
  the source, or from the vault root when they start with `/`, and `%20` is decoded.
- Aliases from the `aliases` key are recorded but never resolve a target.
- Links and tags inside `%% comments %%` are indexed. Code (inline, fenced, tilde, indented), HTML
  comments and `$$` math are not. The site release builder still removes comments and the links in
  them (SITE-025), so this rule does not publish a comment.
- Paths and link text are NFC. Tags are not normalised: `#café` in NFC and in NFD are two tags.
- Tags: `#123` is not a tag, `#1a` and `#日本語` are. Only the frontmatter key `tags` counts, and a
  comma string such as `tags: "a, b"` gives no tags.

The test oracle is a set of golden fixtures from the real engine. The official Obsidian CLI needs
installer 1.12.7 or later, and the spike machine had installer 1.8.10 with app 1.14.4. So the spike
took the same data from the engine's metadata cache through a throwaway plugin: `metadata.json`
holds per file the cache, `resolvedLinks`, `unresolvedLinks`, backlinks and tags. Task 7.1 commits
the vault and that file to `ratatoskr-notes` under
`crates/notes-index/tests/fixtures/obsidian-<version>/`. A new Obsidian version adds a new directory
and does not overwrite the old one. A capture through the CLI may replace the plugin later. It must
then produce the same data.

### D9. Knowledge intake

Knowledge follows `social-analysis-intake`: the event is itself the analysis request. A run is keyed
by `(file_id, revision)`. Knowledge reads the bytes from the notes blob root read-only, as
`blob-references` allows. A `deleted` change, or `evt.notes.vault.disconnected.v1`, removes the
derived analyses, embeddings and search entries for those files. Knowledge gets two durables:
`ratatoskr_knowledge_notes_files` (filter `evt.notes.file.changed.v1`) and
`ratatoskr_knowledge_notes_vaults` (filter `evt.notes.vault.>`), both 120 s and unlimited
delivery, like its other ingest durables.

### D10. The connect operation

Edge proxies `POST /v1/notes/connections` to `ratatoskr-notes`, mints only the operation id, and
returns `202` with the operation of kind `notes.connection.connect`, lane `ratatoskr-notes`. `ratatoskr-notes` reports progress (`login`, `setup`, `first_sync`,
`indexing`) through `evt.platform.operation.reported.v1` and completes the operation when the first
full scan is indexed. This makes `ratatoskr-notes` the sixth producer of the shared report subject,
so the residual risk that `fleet-bus-topology` states extends to it.

### D11. Storage and ports

As `docs/NOTES_AND_SITES.md` section 7 lists them: schema `notes`, role `ratatoskr_notes`, blob root
`/mnt/nvme/ratatoskr/blobs/ratatoskr-notes`, working trees under
`/mnt/nvme/ratatoskr/notes/trees/<id>` (group `ratatoskr-notes-trees`, 2750), client state under
`/mnt/nvme/ratatoskr/notes/clients/<id>` (0700), the journal namespace `ratatoskr-notes-sync`,
domain API 8099 behind Edge, operator listener 9471.
A working tree holds a second copy of the current vault, beside the revisions in the blob root. That
is the cost of running Obsidian's own client.

### D12. The read group of the blob root

Knowledge reads note bytes read-only from the notes blob root (`blob-references`). This change
creates the system group `ratatoskr-notes-blobs`, makes the blob root and every directory in it
setgid with that group (mode 2750), and runs `ratatoskr-notes` with `UMask=0027`, so that a blob is
mode 0640 and its group is `ratatoskr-notes-blobs`. The Knowledge service user is a member from this
change. A later consumer, such as `ratatoskr-sites`, only joins the group in its own change. The
deploy role creates the group, the membership and the root; the notes test
`new_blob_is_group_readable_and_not_world_readable` and the Molecule verify case
`notes_blob_read_group` check them.

Alternative: one ACL entry per consumer. Rejected: ACLs are not inherited by the hard-link and
rename steps of the blob store as reliably as a setgid group, and the other blob roots of the fleet
already use plain modes.

## Risks / Trade-offs

- [A stale scenario title in `fleet-bus-topology`] → The scenario "The reviewed file holds exactly the
  thirteen identities" keeps its title, because a MODIFIED block cannot rename a scenario. The title
  is historical. The body governs: it names `platform_conf_has_exactly_the_fourteen_identities` and
  fourteen names.
- [An earlier change rewrites the same bus requirements] → The `fleet-bus-topology` delta is written
  against the text that `xr-021-fleet-round-5` leaves after archive, with its 23 service durables,
  its five deletion-acknowledgement durables and its stream-API rule. That change must be archived
  first, and the delta's first line says so.
- [Obsidian Headless is an open beta with no declared license] → The earlier public-source terms investigation
  remains in ADR-0010. The owner removed written support replies from acceptance on 2026-10-21. The `plugin` and `cli` channels
  do not depend on it, so a vault that uses Sync can still connect through the plugin if `ob` must
  be dropped. The version is pinned and upgraded only through a reviewed change.
- [Node.js and one `ob` process per connection on the Pi] → The unit keeps its provisional
  `MemoryMax=`; no real continuous Sync measurement is claimed. The owner removed that
  measurement from acceptance on 2026-10-21. `DEPLOYMENT_TARGET.md` records the per-connection budget.
- [Secrets in argv] → D4 steps 2 and 3. Spike 3.2 chose standard input, so only the one-time MFA
  code is in argv. The notes test
  `no_secret_in_any_cmdline` asserts that no process of another user can read a secret from
  `/proc/<pid>/cmdline`, and `login_unit_gets_secrets_only_as_credentials` asserts the
  `LoadCredential=` path.
- [The plugin credential leaks through a synced vault] → D5: the credential never enters the vault
  folder, and the plugin test `credential_never_written_to_data_json` checks every file.
- [The server can read the whole vault, including an end-to-end encrypted one] → This is inherent
  in "manage content". The connect flow states it to the owner before it asks for the end-to-end
  password, and `THREAT_MODEL.md` records it.
- [A file changes while `ob` writes it] → The settle window of D3 and the rescan. The spike checks
  the behaviour of `ob` with a concurrent local edit and records a pull-only session as a fixture.
  The notes test `pull_only_connection_never_pushes_a_local_edit` replays that fixture through a
  stub `ob` and asserts that a local edit makes no upload.
- [Link resolution drifts from Obsidian] → The golden fixtures of D8, versioned per Obsidian release.
- [The plugin is offline for a long time] → The manifest reconciliation of D5. No change is lost,
  but intermediate revisions made while offline are not seen, only the latest state.

## Migration Plan

Nothing exists, so there is no migration. The order of the repositories is in proposal.md. On a
test host: allocate the ports, create the role, reload NATS with the `NOTES` identity, start Edge
so that it provisions the two Knowledge durables, then start `ratatoskr-notes`, then Knowledge.
Rollback is the reverse, and the disconnect command removes each connection's unit, tree and client
state.

## Open Questions

- Whether Obsidian Sync's selective sync settings in `ob sync-config --file-types` should follow the
  owner's settings on their devices or a fixed server setting. The connection stores the value
  either way, so the answer does not change the specs.
