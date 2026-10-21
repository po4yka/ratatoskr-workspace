# ADR-0010: A notes service connects Obsidian vaults through one channel each

> Status: Proposed  
> Date: 2026-10-13  
> Changes: `openspec/changes/add-notes-vault-connections` (OBS-023),
> `openspec/changes/add-notes-write-back` (OBS-024)  
> Target architecture: [`docs/NOTES_AND_SITES.md`](../NOTES_AND_SITES.md)

## Context

The repository owner asked for two things: connect Obsidian vaults to Ratatoskr, and manage their
content from Ratatoskr. A vault can live in Obsidian Sync (the owner calls it "Obsidian Cloud"), or
it can exist only on a device. The owner chose full editing: Ratatoskr creates, changes, renames and
deletes files in a vault, and the vault receives the change.

On 2026-10-13 nothing in the fleet connects to Obsidian. The name `vault` already belongs to
`ratatoskr-vault`, the Git backup service.

Two official Obsidian tools exist. **Obsidian Headless** (`ob`) runs Obsidian Sync and Obsidian
Publish without the desktop app. **Obsidian CLI** (`obsidian`) controls a running desktop app and can
move and rename files with link updates. Obsidian publishes no other API for Sync, and Sync encrypts
end to end.

## Decision drivers

- Sync is end-to-end encrypted and has no public API. The only supported server-side path is `ob`.
- A vault without Sync is reachable only from a device on which the owner runs Obsidian.
- Full editing needs a write path with concurrency control. A rename must not break links.
- One host, a Raspberry Pi 5, with four cores and 15 GiB shared with other tenants.
- Each domain owns its data. Platform owns identity and Edge. Knowledge owns analysis and search.

## Considered options

### Where the domain lives

1. **A new service, `ratatoskr-notes`.** It owns connections, the file index, revisions,
   write-back and conflicts. Knowledge consumes its events.
2. **Inside `ratatoskr-knowledge`.** Knowledge would own files that the owner edits. Knowledge
   analyses content. It does not own content that another system holds as the source of truth.
3. **Inside `ratatoskr-vault`.** Vault backs up Git repositories. Its model is mirrors, bundles and
   restore drills. The name also suggests this option, and the name is a coincidence.

### How a vault without Sync connects

1. **An Obsidian community plugin.** It runs on desktop and mobile. It receives real rename events
   from the vault API, and it applies changes with `fileManager.renameFile`, which updates links. It
   syncs only while the app is open.
2. **`ratatoskr-export-agent` with the Obsidian CLI and a file watcher.** It needs no plugin
   install. It works only on macOS, and it must infer a rename from a delete and a create.
3. **A Git remote** that the owner pushes with the obsidian-git plugin. Write-back needs a pull on
   the device, and mobile support is weak.
4. **Sync only.** The owner must buy Sync for every vault.

## Decision

- **Option 1 for the domain.** A new repository `ratatoskr-notes` (path `repos/notes`, Rust) owns the
  domain. The entity is a **vault connection**. Do not use the bare word "vault" for an Obsidian
  vault in code or contracts.
- **Three channels, exactly one per connection.**
  - `sync`: `ob sync --continuous` on the host, one systemd unit per connection. This also covers a
    "local" vault that uses Sync.
  - `plugin`: a new repository `ratatoskr-obsidian-plugin` (path `repos/clients/obsidian-plugin`,
    TypeScript), paired as a registered device through Platform's ADR-0016 pairing.
  - `cli`: `ratatoskr-export-agent` on macOS, through the Obsidian CLI.

  The owner chose all three. A second channel on one connection is refused, because it delivers
  every change twice.
- **The notes service checks ownership.** Edge mints only a device-kind claim. The notes service
  checks the owner and the channel, because Edge holds no notes data. A `plugin` or `cli`
  connection has exactly one device.
- **Read access to note bytes** goes through the group `ratatoskr-notes-blobs` (setgid root, umask
  0027). Knowledge is a member from the start. Only the notes service writes.
- **Revisions and `base_hash`.** Every file version is a SHA-256 blob. Every write names the revision
  it changes. A mismatch makes a conflict with a three-way merge proposal. It never overwrites in
  silence.
- **Link rewrite on the server.** A rename through Ratatoskr rewrites links with Obsidian's rules.
  Golden fixtures that the real Obsidian app produces are the test oracle.
- **The read path comes first** (OBS-023, `ob` in `pull-only` mode). The write path follows in
  OBS-024.

## Consequences

- The fleet grows by two repositories, `ratatoskr-notes` and `ratatoskr-obsidian-plugin`.
  `workspace.toml`, `.gitmodules`, `fleet.yml`, `drift.yml`, the NATS ACL and the port table change
  with them.
- The host gets a Node.js 22 runtime and the `obsidian-headless` package for the `sync` channel. The
  rest of the fleet stays Rust.
- Knowledge gets a new intake, `evt.notes.file.changed.v1`, in the same way as social and AI-archive
  sources.
- The plugin must pass Obsidian's community plugin review before owners outside development can
  install it from the catalogue. Until then it installs by hand.

## Security and privacy

- To manage content, the server must read it. For a Sync vault with end-to-end encryption, the host
  holds the encryption password. This is the price of the feature, and the owner accepts it per
  connection.
- The Obsidian account password, the MFA code and the encryption password are stored encrypted in
  the `notes` schema. They never enter logs, events, commands or task context. Edge proxies the
  connect call to notes and never persists or logs its body.
- Login and cleanup run as oneshot template units (`ratatoskr-notes-login@<id>`,
  `ratatoskr-notes-cleanup@<id>`), which receive the secrets as systemd credentials. The OBS-023
  spike 3.2 found that `ob` reads both passwords from standard input, so no password enters argv.
  Only the one-time MFA code is in argv. `PrivatePIDs=` is not used, because the host runs systemd
  252.
- `ob` keeps its login token and the derived end-to-end key in plaintext files (mode 0600) in its
  state directory. The 0700 client state `/mnt/nvme/ratatoskr/notes/clients/<id>` of each
  connection, owned by `ratatoskr-notes-sync`, is their only protection.
- The client state of each `ob` process lives in its own directory, mode 0700, owned by the
  `ratatoskr-notes-sync` user, under the 0700 clients root. The working tree is in a separate root,
  `/mnt/nvme/ratatoskr/notes/trees/<id>`, setgid with the group `ratatoskr-notes-trees`, whose only
  member is `ratatoskr-notes` (owner decision B of 2026-10-14).
- The sync units log to the journal namespace `ratatoskr-notes-sync`. The notes service reads only
  that namespace, through an ACL for the group `ratatoskr-notes`, and is not in the group
  `systemd-journal` (owner decision A of 2026-10-14).
- The plugin authenticates as a registered device. Its credential is kept outside the vault folder,
  never in the plugin's `data.json`, because Sync, iCloud, Git or a backup can copy anything in the
  vault. Revocation in Platform stops the device.
- File bytes never travel in a command. A client uploads the content to notes first, and the write
  command carries only a `BlobRef`.

## Compatibility and migration

Additive. No contract or route that exists today changes. All new contracts are `v1`, and the
Development status rules apply: no migrations, one version.

## Validation

- Owner decision, 2026-10-21: the real Sync/MFA environment, live propagation and race checks,
  and their recorded-session and live resource/authentication follow-ups are not acceptance gates.
  These checks were not run; dependent tasks close by scope decision. Runtime rules do not change.
- The golden-fixture corpus from the real Obsidian app, run against the server-side link rewrite.
- The scenarios in the specs of OBS-023 and OBS-024.

## Terms of use (historical spike 3.4; acceptance closed by owner)

Obsidian's Terms of Service have no clause about automation or servers. Obsidian's own
documentation names this use: Headless Sync is "useful for CI pipelines, agents, and automated
workflows", and Obsidian Headless lists "Give agentic tools access to a vault". The conditions that
follow from the Terms and from Obsidian staff are:

- the use stays personal: no service for others, and no access by third parties;
- the client is installed from npm on the host and is never redistributed in a published image;
- the client logs in once and backs off on errors. The supervisor never repeats a login by itself:
  a `login_expired` connection waits for the owner.

No commercial licence is needed, and a Sync subscription is. Five points were left without written
support replies in the investigation of 2026-10-13. The owner removed those replies and physical iOS checks from
acceptance on 2026-10-21 and closed OBS-023. No support confirmation or physical iOS run is
claimed. One retained question is whether note text may go to the LLM provider that Knowledge
uses. The evidence and a draft email are in
`openspec/changes/add-notes-vault-connections/spike/3.4-obsidian-terms.md`.

The Sync plan limits apply to the host as to any device. Sync Standard allows one vault, 5 MB per
file and 1 GB of storage, and stored versions count toward that storage. Frequent automated writes
therefore cost storage.

## Exit path

`obsidian-headless` is a beta whose licence is `UNLICENSED` (proprietary). If Obsidian withdraws it, or its terms of use
forbid this use, the `sync` channel stops and the `plugin` and `cli` channels remain. The data in
`notes` and in the blob root stays complete, because every revision is stored in Ratatoskr.

## Follow-up

- OBS-023 is complete under the owner criteria of 2026-10-21. Physical iOS checks and written
  support answers are not prerequisites for that completion; their evidence limits remain recorded.
- Decide whether `ratatoskr-vault` backs up the notes blob root as one more target.
