# Obsidian vaults and independent sites

> Status: Proposed  
> Last reviewed: 2026-10-13  
> Decisions: [ADR-0010](adr/0010-notes-and-obsidian-vault-connections.md),
> [ADR-0011](adr/0011-independent-sites-on-the-single-host.md)  
> Changes: `add-notes-vault-connections` (OBS-023), `add-notes-write-back` (OBS-024),
> `add-site-publications` (SITE-025), `add-site-gateway-hosting` (SITE-026),
> `add-site-owner-editing-and-live` (SITE-027)

This document is the target architecture for two features:

1. Connect Obsidian vaults to Ratatoskr, both vaults that use Obsidian Sync and vaults that exist
   only on a device, and manage their content from Ratatoskr.
2. Deploy independent sites. Each site has its own UI and its own repository. A site shows content
   from the vaults, lets the owner edit it, receives live updates, and reads other data from the
   system.

Nothing in this document is implemented. It describes the plan. The OpenSpec changes above hold the
requirements and the tasks. This document holds the shared vocabulary that all five changes use, so
that the changes stay consistent with one another.

## 1. Current state

On 2026-10-13 no repository in the fleet mentions Obsidian, in code, documents or Git history. No
service writes Markdown notes to a folder or to a Git repository. The nearest feature is the
`portable-export` operator command of `ratatoskr-chatgpt` and `ratatoskr-claude`. It writes a ZIP
with one Markdown file per conversation, without frontmatter and without links.

The word "vault" already has a meaning in the fleet: `ratatoskr-vault` is the Git backup service.
This document therefore calls the new domain **notes**, and calls a connected Obsidian vault a
**vault connection**. Do not use the bare word "vault" for an Obsidian vault in code or contracts.

## 2. External facts this plan depends on

These facts were read on 2026-10-13. The spike in `add-notes-vault-connections` must confirm them on
the target host before a design depends on them.

- **Obsidian Headless** (`npm install -g obsidian-headless`, command `ob`) is the official client
  for Obsidian Sync and Obsidian Publish without the desktop app. It needs Node.js 22 or later and an
  active Sync subscription. Its status is open beta. The repository declares no license.
- `ob login` accepts `--email`, `--password` and `--mfa`. `ob sync-setup` accepts `--vault`,
  `--path`, `--password` (the end-to-end encryption password), `--device-name` and `--config-dir`.
- `ob sync --continuous` watches the folder and syncs continuously. `ob sync-config` sets `--mode`
  (`bidirectional`, `pull-only`, `mirror-remote`), `--conflict-strategy` (`merge`, `conflict`),
  `--file-types`, `--configs` and `--excluded-folders`. Most commands accept `--json`.
- Obsidian warns against running desktop Sync and Headless Sync on the same device.
- **Obsidian CLI** (`obsidian`, installer 1.12.7 or later) controls a *running* desktop app. It has
  `read`, `create`, `append`, `move` and `rename` (both update internal links when the vault setting
  is on), `delete`, `links`, `backlinks`, `properties`, `property:set`, `search`, `sync:history` and
  more. Several commands accept `format=json`.

Spike results so far (2026-10-13; evidence in `openspec/changes/add-notes-vault-connections/spike/`):

- `obsidian-headless` 0.0.14 is `UNLICENSED` (proprietary). It reads the account password and the
  end-to-end password from standard input, and `ob sync` never needs them again. It keeps its token
  and the derived key in plaintext files (mode 0600) under `$XDG_CONFIG_HOME/obsidian-headless`. An
  expired login does not stop `ob sync`, which retries for ever.
- Obsidian's documentation names server and agent use of Headless Sync. The Terms of Service are
  silent, so a confirmation from Obsidian support is still open.
- The engine of Obsidian 1.14.4 indexes links inside `%% comments %%`, prefers a file in the linking
  file's own folder over the shortest path, and never resolves an alias. On desktop,
  `app.secretStorage` keeps a plugin secret outside the vault.
- Not run yet: the 24-hour run and the conflict test with a real Sync account (3.1, 3.3), and iOS.

## 3. Components

```
 Obsidian app + plugin ──► Edge /v1/notes ─┐      ob sync --continuous (one unit per connection)
 export-agent + Obsidian CLI ──► Edge ─────┤              ▲ working tree on NVMe
                                           ▼              │
                      ┌──────────────────────────────────────────────┐
                      │ ratatoskr-notes                              │
                      │ schema `notes`, blob root, Sync supervisor    │
                      └──────┬───────────────────────────────▲────────┘
                  evt.notes.*│                               │cmd.notes.*
              ┌──────────────┼───────────────┐               │
              ▼              ▼               ▼               │
         knowledge     ratatoskr-sites   platform (operations, Edge)
                       schema `sites`, release builder,
                       delivery API, sites gateway
                             │
              cloudflared ── site-a.example ── static bundle + /_r/* → Edge
```

| Repository (planned) | Path | Stack | Role |
|---|---|---|---|
| `ratatoskr-notes` | `repos/notes` | Rust | Vault connections, file index, revisions, write-back, conflicts, Sync supervisor |
| `ratatoskr-sites` | `repos/sites` | Rust | Site registry, publications, release builder, delivery API, sites gateway |
| `ratatoskr-obsidian-plugin` | `repos/clients/obsidian-plugin` | TypeScript | Obsidian community plugin: the `plugin` channel |
| `ratatoskr-site-sdk` | `repos/clients/site-sdk` | TypeScript | `@ratatoskr/site-sdk` and the starter site template |

Existing repositories that change: `ratatoskr-contracts`, `ratatoskr-platform`,
`ratatoskr-knowledge`, `ratatoskr-export-agent`, `ratatoskr-web` and this workspace.

A site itself is **not** a fleet repository. It is the owner's own repository that depends on
`@ratatoskr/site-sdk` and on the published contracts only.

## 4. Vault connections

A vault connection has exactly one **channel**. The channel is the only path through which the
vault and Ratatoskr exchange file changes.

| Channel | Runs where | Online | Use for |
|---|---|---|---|
| `sync` | On the host: `ob sync --continuous`, one systemd unit per connection | Always | Every vault that uses Obsidian Sync, also a "local" vault that uses Sync |
| `plugin` | Inside Obsidian on the owner's device (desktop or mobile) | While the app is open | A vault without Sync |
| `cli` | `ratatoskr-export-agent` on macOS, through the Obsidian CLI and a file watcher | While the app is open | A vault without Sync, when the owner does not install the plugin |

Rules:

- One connection has one channel. A second channel on the same vault is refused, because it would
  deliver every change twice and cause echo loops.
- A plugin that runs in a vault connected through `sync` works only as UI. It does not send changes.
- A `plugin` or `cli` connection has exactly one device. A second device that presents the same
  vault id is refused with `notes.channel_mismatch`, and the message points the owner to Sync.
- The plugin keeps its device credential outside the vault folder, never in `data.json`, because
  anything in the vault can be copied by Sync, iCloud, Git or a backup.
- The host is a Sync device of its own. Its device name in the Sync history is
  `ratatoskr-<connection id>`.
- Edge mints a device-kind claim. The notes service checks the owner (a foreign connection answers
  404) and the channel (`notes.channel_mismatch`), because Edge holds no notes data.
- The connect call carries the Obsidian password, the MFA code and the end-to-end password. Edge
  proxies it to notes and mints only the operation id. Edge never persists or logs the body. The
  login and the cleanup run as oneshot units (`ratatoskr-notes-login@<id>`,
  `ratatoskr-notes-cleanup@<id>`) that receive the secrets as systemd credentials.

## 5. Content model in `ratatoskr-notes`

- **File.** A path inside the vault, normalised to Unicode NFC, with a case-folded key that detects
  collisions. The `.obsidian/` folder and the folders the owner excludes are not indexed.
- **Revision.** The SHA-256 of the file bytes. Bytes go to the blob root. Every inbound or outbound
  change makes a new revision. The **revision hash** is the `base_hash` of the next write.
- **Index.** For Markdown files: frontmatter, tags, headings, block ids, aliases, outgoing links
  and embeds, each resolved with Obsidian's rules (`[[name]]`, `[[name|alias]]`, `[[name#heading]]`,
  `[[name#^block]]`, `![[embed]]`). `.canvas` and `.base` files are stored and indexed as files
  only.
- **Write.** Every write names a `base_hash`. A write whose `base_hash` is not the current revision
  makes a **conflict** with a three-way merge proposal. It never overwrites in silence. The write
  operations are `create`, `update`, `rename`, `move`, `delete` (to the trash), `set_property` and
  `resolve_conflict`. Each write records its `origin`: `platform` or `site:<site id>`.
- **No content in commands.** The client first uploads the new content to notes over the `transfer`
  route. The write command carries only a `BlobRef` and hashes. Private file bytes never enter
  Edge's outbox or JetStream.
- **Pending writes.** An accepted write is pending. Writes to one file wait in one queue, and the
  `base_hash` of a write is checked when the write reaches the head of the queue. A revision becomes
  current, and `evt.notes.file.changed.v1` is published, only after the channel acknowledges the
  write. Knowledge and the sites never see a revision that the vault did not receive.
- **Echo suppression.** An inbound change whose hash equals a revision that Ratatoskr itself wrote
  through that channel is recorded as an acknowledgement, not as a new change.
- **Rename.** A rename through Ratatoskr rewrites the links in every file that points to the old
  path, with the same rules as Obsidian's "Automatically update internal links". Golden fixtures
  that the real Obsidian app produces are the test oracle for this.

## 6. Sites

- **Publication.** A filter over one vault connection: included and excluded folders, tags, and the
  frontmatter key `publish`. The selection rules are:
  - An excluded folder always wins, and `publish: false` always excludes.
  - `publish: true` selects a file only inside the publication's included folders, or anywhere when
    the publication includes the whole vault.
  - `publish: [<site id>, ...]` selects the file only for the named sites.

  With these rules, two publications on one connection do not leak notes into each other.
- **Release mode.** A publication is `automatic` (the default) or `manual`. In `automatic` mode, a
  change to a selected file starts a build inside the sites service, and the builds are coalesced.
  In `manual` mode, only the owner's release request starts a build. The **first** release of every
  publication is always an explicit request. This protects a vault whose notes already carry
  Obsidian Publish flags.
- **Full rebuilds.** Every build renders every selected page. A later change can add page reuse only
  together with tests that prove that an unselected target and a stale backlink cannot survive.
- **Release.** An immutable snapshot that the release builder makes from a publication. Each page
  has a slug, a title, the allowlisted frontmatter fields, a body as a Markdown AST and as sanitised
  HTML, resolved outgoing links, backlinks inside the publication, and assets as public URLs.
- **Privacy rules for a release.** These are requirements with tests in `add-site-publications`:
  - Only files that the publication selects are published.
  - A link to a note that is not published becomes plain text, and it renders exactly like an
    unresolved link. The text that the author wrote in the published note stays. Nothing that is
    read from the target (its title, aliases, headings or path) is added to the release.
  - `%% comments %%` are removed. Frontmatter fields that are not on the allowlist are removed.
  - An attachment is published only when a published page embeds or links it.
- **Site manifest.** `ratatoskr-site.toml` in the site repository. It names the site id, the
  hostname, the publications that the site reads, and the capabilities that it asks for.
- **Approval.** The only approval store is Platform's `identity.site_approvals`, bound to the
  manifest digest. The owner approves or withdraws through Edge-owned routes. Platform publishes
  `evt.platform.site_approval.changed.v1`, and the sites service keeps only a read projection of it.
  The **effective capability set** is the capabilities of the last approved manifest that the active
  manifest still declares. A new capability, hostname or publication takes effect only after a new
  approval.
- **Answers for capabilities.** A public capability that the site did not request, an unapproved
  site and a withdrawn site all answer 404 `sites.site_not_found`, so the answer does not show
  whether a site exists. An owner-only capability that the session lacks answers 403
  `edge.capability_not_granted`.
- **Route classes under `/v1/sites/{site}/`.**
  - *Management*: a primary Platform session with the live `platform.owner` grant, and no site
    capability. This covers the manifest, approval, publications and sign-in codes.
  - *Deploy*: a primary session with `platform.owner`, or a `site_deployer` device paired for that
    site. This covers deploys and their activation, and nothing else.
  - *Release*: `POST .../releases`, see below.
  - *Site origin*: checked against the effective capability set, for an anonymous caller or a
    `site_owner` session. This covers content, events, drafts, edits, conflicts, library and
    knowledge search.
  - *Sign-in*: `POST .../sessions`, anonymous, authenticated only by the PKCE code.

  `POST .../releases` accepts either a primary session with `platform.owner` or a `site_owner`
  session with `notes.edit`. Edge refuses to start when a route has no class. The sites service
  refuses an anonymous claim on every route except content.
- **Capabilities.**

| Capability | Who can use it | What it allows |
|---|---|---|
| `pages.read` | Anyone | Read pages and the navigation of the current release |
| `assets.read` | Anyone | Read the assets of the current release |
| `search.publication` | Anyone | Full-text search over the current release only |
| `live.release` | Anyone | Receive `release.published` events over SSE |
| `draft.read` | Owner session | Read unpublished changes of the site's publications |
| `notes.edit` | Owner session | Write the source notes of the site's publications |
| `library.read` | Owner session | Read the owner's knowledge library |
| `knowledge.search` | Owner session | Search across the owner's knowledge, not only the publication |

- **Owner session.** A Platform session of the kind `site_owner`, whose audience is `site:<site id>`.
  The owner gets it through an authorization code with PKCE: the owner's primary session approves
  the sign-in in `ratatoskr-web`, and the site's SDK callback page `/.ratatoskr/sign-in` redeems the
  code. The cookie `__Host-ratatoskr-site` is HttpOnly, Secure, SameSite=Strict and bound to the site
  hostname. The session carries only the effective capability set.
- **Hosting.** A site is a static bundle that the site repository's CI builds. The sites gateway on
  the host serves the bundle by hostname behind `cloudflared`. Under `/_r/` the gateway forwards
  requests to Edge, so the site and the API share one origin. Content changes do not rebuild a
  site. The site reads content at runtime and receives updates over SSE.
  - `/.ratatoskr/` is reserved for SDK pages such as `/.ratatoskr/sign-in`. The gateway serves them
    with `no-store` and with no fallback to the entry page.
  - The gateway removes any inbound `X-Ratatoskr-Client-IP` and sets it from `CF-Connecting-IP`.
    Edge trusts that header only from the gateway's loopback peer, and uses it for the per-client
    limits.
  - Anonymous SSE has a limit per client (default 4) under a limit per site (default 64).
  - `ratatoskr-site deploy` authenticates as a registered device of the kind `site_deployer`.

## 7. Shared names

### NATS subjects

| Subject | Producer | Consumers | Change |
|---|---|---|---|
| `evt.notes.vault.connected.v1` | notes | knowledge, sites | OBS-023 |
| `evt.notes.vault.disconnected.v1` | notes | knowledge, sites | OBS-023 |
| `evt.notes.file.changed.v1` | notes | knowledge, sites | OBS-023 |
| `cmd.notes.file.write_requested.v1` | platform (Edge) | notes | OBS-024 |
| `evt.notes.conflict.raised.v1` | notes | platform | OBS-024 |
| `evt.notes.conflict.resolved.v1` | notes | platform | OBS-024 |
| `evt.platform.site_approval.changed.v1` | platform | sites | SITE-025 |
| `cmd.sites.release.build_requested.v1` | platform (Edge) | sites | SITE-025 |
| `evt.sites.release.published.v1` | sites | platform (SSE) | SITE-025 |
| `evt.sites.draft.changed.v1` | sites | platform (SSE) | SITE-027 |

Only Edge publishes commands (`fleet-bus-topology`). For an edit from a site, Edge resolves the
page's `source_ref` to a connection id and a path through a loopback query to the sites service,
and then publishes the write command with `origin: "site:<site id>"`. An automatic rebuild is not a
command: the sites service queues it internally. The sites gateway uses no NATS. It reads a
projection on disk that the sites service rewrites on every deploy, approval, withdrawal and
hostname change.

Every service also reports progress with the existing `evt.platform.operation.reported.v1`.

### Durables

| Durable | Owner | Filter |
|---|---|---|
| `ratatoskr_knowledge_notes_files` | knowledge | `evt.notes.file.changed.v1` |
| `ratatoskr_knowledge_notes_vaults` | knowledge | `evt.notes.vault.>` |
| `ratatoskr_sites_release_builds` | sites | `cmd.sites.release.build_requested.v1` |
| `ratatoskr_sites_note_changes` | sites | `evt.notes.file.changed.v1` |
| `ratatoskr_sites_vault_disconnections` | sites | `evt.notes.vault.disconnected.v1` |
| `ratatoskr_notes_write_requests` | notes | `cmd.notes.file.write_requested.v1` |
| `platform_notes_conflict_projection` | platform (Edge) | `evt.notes.conflict.>` |
| `ratatoskr_sites_approvals` | sites | `evt.platform.site_approval.changed.v1` |
| `platform_site_events` | platform (Edge) | `evt.sites.release.published.v1`, `evt.sites.draft.changed.v1` |

OBS-023 adds the two Knowledge durables, and OBS-024 adds `ratatoskr_notes_write_requests` and
`platform_notes_conflict_projection`. SITE-025 adds the four `ratatoskr_sites_*` durables, and
SITE-027 adds `platform_site_events`.

### Contracts in `ratatoskr-contracts`

- Crates `crates/notes-contracts` and `crates/sites-contracts`.
- Events and commands are registered by type, as the repository does for every message:
  `notes.vault.connected.v1`, `notes.vault.disconnected.v1`, `notes.file.changed.v1`,
  `notes.file.write_requested.v1`, `notes.conflict.raised.v1`, `notes.conflict.resolved.v1`,
  `platform.site_approval.changed.v1`, `sites.release.build_requested.v1`,
  `sites.release.published.v1`, `sites.draft.changed.v1`.
- `notes/write-request.v1` carries `origin` and a `BlobRef` for the content, never the content.
- Documents: `sites/site-manifest.v1`, `sites/release.v1`, `sites/page.v1` (an mdast-compatible
  tree with the node types `callout`, `wikiLink` and `embed`, plus sanitised HTML; not Document IR),
  `sites/site-event.v1` and `sites/bundle-manifest.v1`.
- Site events: `release.published`, `draft.changed`, `edit.completed`, `edit.conflicted` and
  `resync`. Only `release.published` reaches anonymous clients, and it carries no list of slugs.
- Operation kinds: `notes.connection.connect`, `notes.connection.write_mode`, `notes.file.write`
  and `sites.release.build`.
- Error codes named so far: `notes.channel_mismatch`, `notes.write.conflict`,
  `notes.write.disabled`, `notes.write.transformed` (a warning), `notes.write.partially_applied`,
  `notes.connection.not_found`, `sites.site_not_found`, `sites.page_not_found`,
  `sites.asset_not_found`, `sites.slug_collision`, `sites.publication_suspended`,
  `platform.manifest_digest_stale`, `platform.site_hostname_taken` and
  `edge.capability_not_granted`.
- Registered device kinds: `obsidian_plugin` and `site_deployer`.

### Edge routes

| Prefix | Owner | Route class (ADR-0015 of Platform) |
|---|---|---|
| `/v1/notes/connections`, `.../{id}/changes` | notes | `control`; the connect body is never persisted at Edge |
| `/v1/notes/connections/{id}/blobs` | notes | `transfer` |
| `/v1/notes/connections/{id}/writes` | Edge publishes the write command | `control` |
| `/v1/notes/connections/{id}/write-mode` | notes | `control` |
| `/v1/notes/connections/{id}/device-operations` | notes | `control` (the device queue of OBS-024) |
| `/v1/notes/conflicts/{id}`, `.../resolution` | notes | `control` |
| `/v1/sites`, `/v1/sites/{site}/manifest`, `.../publications` | sites | `control`, management |
| `/v1/sites/{site}/manifest/approval` (`POST`, `DELETE`) | platform (Edge) | `control`, management |
| `/v1/sites/{site}/releases` | Edge publishes the build command | `control`, release (two guards) |
| `/v1/sites/{site}/deploys` | sites | `transfer`, deploy; `.../deploys/{commit}/activate` is `control`, deploy |
| `/v1/sites/{site}/sign-in-codes` | platform (Edge) | `control`, management |
| `/v1/sites/{site}/sessions` | platform (Edge) | `control`, sign-in (PKCE) |
| `/v1/sites/{site}/content` | sites | new class `public` (anonymous, cacheable), Platform ADR-0017 |
| `/v1/sites/{site}/events` | platform (SSE) | `stream`, site origin |
| `/v1/sites/{site}/drafts`, `.../edits`, `.../conflicts` | sites, Edge | `control`, site origin, owner session |
| `/v1/sites/{site}/drafts/sources/{source_ref}/blobs` | notes (upload before an edit) | `transfer`, site origin, `notes.edit` |
| `/v1/sites/{site}/library`, `.../knowledge/search` | platform → knowledge | `control`, site origin, owner session |

### Ports (proposed; each change that adds a listener allocates its port in `DEPLOYMENT_TARGET.md`)

| Port | Owner | Reachability |
|---|---|---|
| 8099 | `ratatoskr-notes` domain API (`/v1/notes`) | loopback; reached only through Edge |
| 8100 | `ratatoskr-sites` domain API (`/v1/sites`) | loopback; reached only through Edge |
| 8183 | `ratatoskr-sites-gateway` public listener | `cloudflared` tunnel |
| 9471 | `ratatoskr-notes` operator listener | host only |
| 9472 | `ratatoskr-sites` operator listener | host only |
| 9473 | `ratatoskr-sites-gateway` operator listener | host only |

### Storage

| What | Where |
|---|---|
| Notes database | schema `notes`, role `ratatoskr_notes`, database `ratatoskr` |
| Sites database | schema `sites`, role `ratatoskr_sites`, database `ratatoskr` |
| Note file bytes | `/mnt/nvme/ratatoskr/blobs/ratatoskr-notes/sha256/<2 hex>/<rest>` |
| Sync working tree | `/mnt/nvme/ratatoskr/notes/connections/<id>/tree` |
| Headless client state | `/mnt/nvme/ratatoskr/notes/connections/<id>/ob-home`, mode 0700, owner `ratatoskr-notes-sync` |
| Obsidian secrets key | `/etc/ratatoskr/notes-secrets.key`; secrets are stored encrypted in `notes` |
| Read access to note bytes | group `ratatoskr-notes-blobs`, setgid root, umask 0027. OBS-023 creates it with Knowledge as a member; SITE-025 adds sites. Only notes writes. |
| Release assets | `/mnt/nvme/ratatoskr/blobs/ratatoskr-sites/sha256/<2 hex>/<rest>` |
| Site bundles | `/mnt/nvme/ratatoskr/sites/<site id>/bundles/<commit>`, group `ratatoskr-sites-bundles` |
| Gateway projection | `/mnt/nvme/ratatoskr/sites/<site id>/site.json` and the links `current` and `previous` |
| Site owner approvals | `identity.site_approvals` in Platform, bound to the manifest digest |

A site bundle is the OCI artifact type `application/vnd.ratatoskr.site-bundle.v1`. The site
repository's CI builds and attests it. The owner deploys it with `ratatoskr-site deploy`, which
verifies it on the controller and uploads it through Edge.

## 8. Order of the changes

```
 OBS-023 add-notes-vault-connections      read path, spike first
    └─► OBS-024 add-notes-write-back      full editor
          └─► SITE-025 add-site-publications            content, approval, delivery API
                └─► SITE-026 add-site-gateway-hosting   sites on the host
                      └─► SITE-027 add-site-owner-editing-and-live
```

**Archive order is strict:** `xr-021-fleet-round-5`, then OBS-023, OBS-024, SITE-025, SITE-026,
SITE-027. XR-021 is an earlier change that is still active. It rewrites the durable table of
`fleet-bus-topology`, so it must be archived before OBS-023. Several changes modify the same shared
specs (`fleet-bus-topology`, `workspace-fleet-membership`, `postgres-provisioning`,
`site-route-classes` and `notes-device-channels`). Each change writes its delta against the text
that the changes before it leave after archive. A full-text MODIFIED block replaces the whole
requirement, and `openspec validate` does not detect a lost table row, so a delta that skips this
rule loses the rows of an earlier change without an error.

**DPL-022 comes first for the deploy tasks.** The tasks in OBS-023, SITE-025 and SITE-026 that use
the Ansible tree, Molecule, the freeze guard, `services.json` or `deploy_inventory.rs` wait until
`add-deployment-automation` (DPL-022) is merged and archived. Their changesets name that
dependency. Each such delta file names the change that must be archived first. Until that
archive happens, `openspec validate` reports for a later change that "archive would refuse" its
delta. That message is expected.

Implementation can overlap where the code allows it. For example, the sites service can start
against the read path of OBS-023 before OBS-024 is archived. The archive order does not change.

If the OBS-023 spike shows that the `sync` channel cannot run, the change is revised with
`openspec update` before any later group starts. The sync groups then move to a new change, so that
no task stays unticked and blocks the archive.

## 9. Rules that these changes touch

The repository owner said that the rules can change for this work. These points need an explicit
decision. They are not changed in silence:

- **The fleet grows from 17 to 21 product repositories.** `workspace.toml`, `.gitmodules`, `fleet.yml`,
  `drift.yml`, the NATS ACL and the port table all change. ADR-0010 and ADR-0011 record why.
- **Edge gets anonymous public traffic.** Today Edge serves sessions and ingest serves webhooks.
  Platform's README excludes "a public multi-tenant SaaS control plane". ADR-0011 adds one narrow
  public route class for site content. It does not add multi-tenancy.
- **The host gets a Node.js runtime and a proprietary beta client.** ADR-0010 records the risk and
  the exit path.
- **Development status is unchanged.** One version, no migrations, and the product name is
  Ratatoskr. All new contracts are `v1`.
