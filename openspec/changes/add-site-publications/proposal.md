# Proposal

## Why

The repository owner wants individual sites that show content from the connected Obsidian vaults,
each with its own UI in its own repository (ADR-0011, `docs/NOTES_AND_SITES.md`). After OBS-023 the
notes of a vault are in Ratatoskr, but nothing selects which of them are public, nothing makes a
safe public copy of them, and no route serves anything to a visitor who has no session.

A vault is private by default. If each site read the notes API and filtered the notes itself, one
mistake in one site would leak the vault. So the selection, the privacy filter and the public read
path must be in one place that the fleet owns and tests.

## What Changes

- Add a new repository, `ratatoskr-sites` (path `repos/sites`, Rust). It owns the site registry,
  the publications, the release builder and the Content Delivery API. The sites gateway also lives
  in this repository, but SITE-026 adds it.
- A **publication** belongs to one site and is a filter over one vault connection: folders, tags,
  and the frontmatter key `publish`. An excluded folder always wins, `publish: true` works only
  inside the included folders, and `publish: [<site id>, ...]` limits a note to the named sites.
- The **release builder** makes an immutable **release** from a publication. A release holds pages
  (`sites/page.v1`), assets and navigation, and is named by the digest of its content. Every build
  renders every selected page; a rebuild whose content is unchanged makes no new release. The first
  release of a publication is always requested explicitly; the mode `automatic` applies after it.
- The release builder applies the **privacy rules** as one pass before it renders anything: only
  selected files, no data taken from an unpublished note, no `%% comments %%`, only allowlisted
  frontmatter fields, and only attachments that a published page uses.
- A **site manifest**, `ratatoskr-site.toml` (`sites/site-manifest.v1`), names the site id, the
  hostname, the publications and the requested capabilities. The sites service stores it by digest.
  The owner approves it in **Platform** (`identity.site_approvals`, Edge routes
  `POST`/`DELETE /v1/sites/{site}/manifest/approval`), which announces
  `evt.platform.site_approval.changed.v1`; the sites service keeps only a projection. The effective
  set of a site is the approved manifest intersected with the active one. This change delivers the four public capabilities except `live.release`,
  which the manifest can name and SITE-027 delivers.
- A **Content Delivery API** under `/v1/sites/{site}/content`, behind a new Edge route class
  `public`: anonymous, read-only, cacheable and rate-limited. It serves only the current release of
  a site with an approved manifest. `search.publication` searches only that release.
- Every route under `/v1/sites/{site}/` has one class at Edge: `management`, `site-origin`,
  `sign-in` or `release`. `POST .../releases` is the `release` class, with two guards. SITE-026 adds
  a `deploy` class and SITE-027 modifies the same spec. The sites service refuses an anonymous claim on
  every route outside `content/`.
- New bus messages: `cmd.sites.release.build_requested.v1`, `evt.sites.release.published.v1` and
  `evt.platform.site_approval.changed.v1`. The sites service consumes the two notes events
  `evt.notes.file.changed.v1` and `evt.notes.vault.disconnected.v1`, and the approval event. A build
  is an operation of the new kind `sites.release.build`, reported only by `ratatoskr-sites`.
- Add a new repository, `ratatoskr-site-sdk` (path `repos/clients/site-sdk`, TypeScript). It
  publishes `@ratatoskr/site-sdk`, a typed client generated from the contracts, and a starter site
  template.
- The web client gets the site registry, manifest approval and withdrawal, the publication editor and the release
  history.
- Platform records the `public` route class and the site route classes in its own ADR-0017.

No item is **BREAKING**. Nothing of this has shipped, and no existing route changes behaviour.

## Capabilities

### New Capabilities

- `site-publications`: how a publication selects files from one vault connection, how a release is
  built, named, made current and announced, and what happens when the connection goes away.
- `site-release-privacy`: what a release must never contain that comes from an unpublished file,
  and how links, embeds, comments, frontmatter and attachments are filtered.
- `site-manifest`: the shape of `ratatoskr-site.toml`, the closed capability set, the approval that
  Platform holds, the read projection in sites, and the one rule for the effective set.
- `site-route-classes`: the class of every route under `/v1/sites/{site}/`, the guard each class
  applies, the two guards of the `release` class, and the anonymous-claim check in the sites service.
- `site-content-delivery`: the anonymous Content Delivery API, the `public` route class, the cache
  and rate rules, search over the current release, and the SDK that is generated from the contract.

### Modified Capabilities

- `fleet-bus-topology`: a new NATS identity `SITES`, the four durables that Edge provisions for the
  sites service, the operation-report authority with the kind `sites.release.build`, and the counts
  and lists that grow with it (durable names, Edge upstreams, seed variables, integration profiles,
  inbox prefixes).
- `workspace-fleet-membership`: the snapshot also pins `sites` and `site-sdk`.
- `postgres-provisioning`: the role `ratatoskr_sites`, created by `deploy/postgres/role.sql` of
  `ratatoskr-sites`.

Each modified delta requires OBS-024 (`add-notes-write-back`) to be archived first.

## Repositories, in merge order

1. `ratatoskr-contracts`: the crate `crates/sites-contracts` with the schemas
   `sites/site-manifest.v1`, `sites/release.v1` and `sites/page.v1`, and the registration of the two
   bus messages. It merges first, because every other repository builds against these types.
2. `ratatoskr-notes`: a loopback-only internal index route (revision, frontmatter, tags, headings,
   block ids, and resolved links and embeds per file). It merges before the sites service, which
   reads it. OBS-023 already creates the read group `ratatoskr-notes-blobs`.
3. `ratatoskr-sites` (new): the service, its `schema.sql`, its deploy files (with the membership of
   `ratatoskr-sites` in `ratatoskr-notes-blobs`) and its NATS stanza.
4. `ratatoskr-platform`: ADR-0017, the `public` route class and the site route classes,
   `identity.site_approvals` with its two Edge routes and its event, the build route with the
   operation kind `sites.release.build` and its authority row, the `SITES` identity, the four new
   durables, and a gateway test that no public path reaches the notes internal route.
5. `ratatoskr-site-sdk` (new): the generated client and the starter template. It needs the deployed
   contract shape from 1 and a running delivery API from 3 and 4 for its end-to-end test.
6. `ratatoskr-web`: the site registry, manifest approval, publication editor and release history.
7. `ratatoskr-workspace`: fleet membership, the port table rows 8100 and 9472, the deploy
   enrolment, the harness expectations and the documentation. It merges last, because it pins the
   merged commits of 1 to 6.

This change needs the read path of OBS-023 (`add-notes-vault-connections`) in `ratatoskr-notes`, and
its spec deltas require OBS-023 to be archived first. It does not need OBS-024.

## Outside this change

- Hosting a site on the host: the sites gateway, `cloudflared` ingress and bundle deployment
  (SITE-026, `add-site-gateway-hosting`).
- The owner session (`site:<id>` audience), editing from a site, the SSE stream, draft reads and the
  owner-only data capabilities (SITE-027, `add-site-owner-editing-and-live`). The manifest can name
  those capabilities, but they grant nothing until SITE-027.
- Prerendering a release for search engines.
- Custom per-site themes or templates on the server. A site's UI is its own code.
- Obsidian Publish. The owner can still use it from Obsidian; Ratatoskr does not drive it.

## Rollback

Nothing has shipped, so there is nothing to roll back on a host. Each repository change is reverted
with a normal `git revert`. A revert of the Platform route rows removes the public surface at once,
because Edge then answers every `/v1/sites/*/content` request with its normal not-found envelope.

## Impact

- New repositories: `ratatoskr-sites`, `ratatoskr-site-sdk`. The fleet grows from the count that
  OBS-023 leaves (nineteen) to twenty-one.
- New database schema `sites`, role `ratatoskr_sites`, in the database `ratatoskr`, and a new table
  `identity.site_approvals` in Platform's schema.
- New blob root `/mnt/nvme/ratatoskr/blobs/ratatoskr-sites`. The sites service reads note bytes
  read-only from the notes blob root as a member of the read group `ratatoskr-notes-blobs`, which
  OBS-023 creates
  (`blob-references`).
- New internal route in `ratatoskr-notes`: `GET /internal/connections/{connection}/files` on its
  loopback domain listener, refused to any non-loopback peer and unreachable through Edge.
- New ports 8100 (domain API, loopback, reached only through Edge) and 9472 (operator, host only).
- New public surface: anonymous `GET` routes under `/v1/sites/{site}/content` through
  `cloudflared` and Edge.
- New npm package: `@ratatoskr/site-sdk`.
