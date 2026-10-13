# Design

## Context

See `proposal.md` for the motivation, ADR-0011 for the decision to build sites as a headless CMS
on the host, and `docs/NOTES_AND_SITES.md` for the shared names. The constraints that shape this
change:

- **One host.** A Raspberry Pi 5 with four cores and 15 GiB of RAM, shared with other tenants. Public
  traffic must be cheap to serve and must be cached in front of the host.
- **Edge is the only public path** for API traffic (Platform ADR-0015). Edge authenticates once and
  mints claims. Today every Edge route class (`control`, `stream`, `transfer`) needs a session.
- **The control plane owns no content** (`blob-references`). Platform cannot store a release.
- **Each service owns its bytes** and may read another service's blob root read-only through a read
  group (`blob-references`).
- **After OBS-023**, `ratatoskr-notes` holds the file index, the revisions and the resolved links of
  each vault connection, and publishes `evt.notes.file.changed.v1` and
  `evt.notes.vault.disconnected.v1`.
- **Only Edge publishes commands** (`fleet-bus-topology`). A service can publish only the commands
  that its identity is explicitly allowed.

## Goals / Non-Goals

**Goals:**

- One place selects public content, filters it and renders it, so that a site can only receive
  what passed the privacy rules.
- A site with any UI stack can read a release with a typed client and no knowledge of vault paths.
- Anonymous public traffic never reaches a private route and costs the host as little as possible.

**Non-Goals:**

- Hosting the bundle of a site (SITE-026).
- Any request that carries an identity on a site: owner session, draft reads, edits, owner-only
  data, live events (SITE-027).
- Redirects after a slug changes. A changed slug is a new page.
- Prerendering for search engines.

## Decisions

### D1. A new repository, `ratatoskr-sites`

The sites service owns the site registry, the submitted manifests, a read projection of the
approvals that Platform holds (D9), the publications, the release builder, the releases and their search index, and the Content Delivery API. SITE-026 adds
the gateway binary to the same repository.

Alternatives:
- **Inside `ratatoskr-notes`.** Notes owns private content and its write path. Putting the public
  copy and the public API in the same service mixes the one thing that must stay private with the
  one thing that must be public, and one bug crosses the line. Rejected.
- **Inside Platform.** The control plane owns no content (`blob-references`). Rejected.
- **Inside Knowledge.** Knowledge holds analyses of everything the owner captured. A public index
  next to it invites a query that reaches private data. Rejected for the same reason as notes.

### D2. The page body is a Markdown AST plus sanitised HTML, not Document IR

`sites/page.v1` carries the body twice, both made from the same filtered tree:

- `ast`: an mdast-compatible JSON tree, with three Obsidian node types added (`callout`,
  `wikiLink` with a resolved slug, `embed` with a resolved page or asset), so that a site can render
  the structure in its own way;
- `html`: the same tree rendered to HTML and passed through a closed element and attribute
  allowlist, for a site that only wants to insert markup.

Alternatives:
- **Document IR.** It is the shared shape between extraction and analysis, and the `document-ir`
  spec says it carries only what both sides read. Callouts, resolved wikilinks, embeds, backlinks
  and slugs are read only by the sites service and the site SDK. Adding them to Document IR breaks
  that rule, and leaving them out makes the page lossy. Rejected. Reading a note as Document IR for
  Knowledge stays possible in OBS-023 and is not affected.
- **HTML only.** An independent UI could not restyle a callout or replace a link component without
  parsing HTML again. Rejected.
- **Raw Markdown.** Each site would resolve links and filter privacy itself, which is the risk this
  change removes. Rejected.

### D3. The sites service reads notes through the notes resolver, not its own

Link resolution in Obsidian has many rules (shortest path, aliases, headings, blocks, embeds). Two
implementations would drift, and a drift here decides whether a link points to a published page. So
the sites service uses the resolution that `ratatoskr-notes` makes:

- it consumes `evt.notes.file.changed.v1` to learn which file changed;
- it reads the connection's file index (revision, frontmatter, tags, headings, block ids and
  resolved outgoing links and embeds) from `GET /internal/connections/{connection}/files` on the
  notes domain listener (8099). The route is under `/internal/`, as Knowledge's `/internal/search`
  is. Notes refuses it to a non-loopback peer, and Edge's `/v1/notes` row cannot reach it;
- it reads note bytes read-only from the notes blob root through the read group
  `ratatoskr-notes-blobs`, and verifies every `BlobRef` as `blob-references` requires.

OBS-023 creates the read group, the setgid root and the umask, and makes Knowledge a member. This
change adds the internal route to `ratatoskr-notes` (tasks group 4) and only adds the user
`ratatoskr-sites` to the group, in the sites repository's `sysusers.d` file. The resolution itself
stays the one that OBS-023 computes.

### D4. A release is a canonical document named by its digest

The release builder writes each page and each asset to the sites blob root
(`/mnt/nvme/ratatoskr/blobs/ratatoskr-sites/sha256/<2 hex>/<rest>`), then writes the release document:
the navigation and, per page, its slug, title and page blob digest. The document is serialised as
canonical JSON (RFC 8785) and its SHA-256 is the release id. `sites.current_releases` holds one row
per site, and one `UPDATE` in the same transaction as the outbox row makes a release current. A
build whose release id equals the current one stops there, so a rebuild without changes is free of
events.

Every build parses, filters and renders every selected page. There is no page reuse in this
version: a page depends on the selection state of every note it links to and of every note that
links to it, and a reuse key that misses one of those leaks a title or a backlink. Reuse is a later
optimisation, and it must keep `target_unselected_after_release_rerenders_linking_page` and
`backlink_from_unselected_page_is_dropped_on_rebuild` passing. A full build of a few hundred notes
is seconds of CPU on the Pi, and builds are coalesced (D6).

### D5. Privacy is one filter pass on the tree, before any renderer

The builder parses each selected Markdown file into a tree, then runs one filter pass that:
drops comments; replaces links to unselected notes with the text that the author wrote, as a plain
text node identical to an unresolved link; removes embeds of unselected notes and unpublished
attachments; drops frontmatter fields outside the allowlist. Only the filtered tree goes to the AST
serialiser, the HTML renderer, the search indexer and the asset collector. No renderer receives the
index of the vault, only the set of selected slugs and published asset digests.

The test strategy follows from this. A fixture vault holds unselected files, each with unique
canary strings in every place a leak could come from. The test builds a release and searches every
byte of it for every canary. This finds a leak that no one predicted, which a list of single
assertions would not.

### D6. Builds start from Edge or from an internal coalescing queue

A build request (`POST /v1/sites/{site}/releases`, class `release` with the two guards of D11) goes through Edge,
which mints an operation of the kind `sites.release.build` with the lane `ratatoskr-sites` and
publishes `cmd.sites.release.build_requested.v1` from its outbox, as for every other command. For a publication in `automatic` mode, a file change
does not become a command: the sites service records it in `sites.build_requests` and a single
worker per site coalesces all requests that arrive while a build runs into one follow-up build. This
keeps to the rule that only Edge publishes commands, and it bounds the number of builds that a burst
of Sync changes can cause. The default release mode is `automatic`, because SITE-027's live updates
depend on it. The owner can switch a publication to `manual`.

The first release that contains a publication is always explicit, whatever its mode. A vault that
was used with Obsidian Publish already carries `publish: true` on many notes; without this rule, the
first Sync change after the owner creates a publication would publish them before the owner has
looked at a release.

### D6a. Selection precedence

An excluded folder always wins, and `publish: false` always excludes. `publish: true` selects only
inside the publication's included folders (or anywhere, when the publication names none), so a flag
that was set for Obsidian Publish cannot pull a note out of a private folder into a site. A note can
name sites, `publish: [<site id>, ...]`, when one connection feeds several sites. A publication is in
the mode `flagged` (only flagged or tagged notes) or `all` (every note in its folders).

### D7. The `public` route class in Edge

Platform's ADR-0017 adds a fourth route class to ADR-0015:

- `GET` and `HEAD` only; a body is refused;
- no credential is read, no cookie is read or set, and Edge mints for the sites service an
  anonymous claim with only a correlation id;
- a token bucket per client keyed on `X-Ratatoskr-Client-IP`, which the sites gateway sets and Edge
  trusts only under the rule SITE-026 owns, and a total budget per site, both checked before the
  proxy;
- response headers from the sites service pass through, so that the sites service owns
  `Cache-Control` and `ETag`.

A site id that is unknown, unapproved or withdrawn is answered by the sites service from an
in-memory set of servable site ids that it refreshes on every approval event, every manifest
submission and every release.
Every kind of absence takes the same code path and the same time.

Alternatives:
- **A separate public listener in the sites service, reached directly through `cloudflared`.** It
  would put a second public path on the host and a second place that must refuse identities. ADR-0015
  rejected per-service public listeners. Rejected.
- **The `control` class with a guest session.** A session for every visitor costs a database row
  per visitor and makes caching per session. Rejected.

### D8. Search is a per-release index in the sites schema

The builder writes one `tsvector` row per page into `sites.release_search`, keyed by release id, and
search reads only the rows of the current release id. Old rows are removed with the old release.
Knowledge is not used, because Knowledge indexes private content, and a public route that queries it
would depend on a filter for its privacy.

### D9. The manifest is stored by sites and approved in Platform

The site repository holds `ratatoskr-site.toml`. The owner submits it through the web client
(`PUT /v1/sites/{site}/manifest`, a management route proxied to sites), and the sites service stores
the bytes by digest. The last valid submission is the active manifest.

The approval is an authorisation decision, so it lives where every other grant lives: Platform's
`identity.site_approvals`, one row per site, bound to the approved digest. Edge serves `POST` and
`DELETE /v1/sites/{site}/manifest/approval` itself. To approve, Edge reads the active manifest
(digest, capabilities, hostname, publications) from the sites loopback route
`GET /internal/sites/{site}/manifest`, refuses a digest that is not the active one, checks the
hostname against the unique index of approved rows, and writes the row and
`evt.platform.site_approval.changed.v1` in one transaction. The event carries the hostname, so the
sites service can rewrite the gateway projection `site.json` (SITE-026) from the event alone. The sites service consumes the event
through `ratatoskr_sites_approvals` into a read projection and has no approval route.

The effective set is approved ∩ active (`site-manifest`). It lets the owner narrow a site at once by
submitting a smaller manifest, and it makes every widening wait for an approval. SITE-026 routes by
the effective hostname; SITE-027 grants owner sessions from the effective capabilities.

Alternatives:
- **Approval in the sites service** (the first draft). Two services would then decide what a site may
  do, and SITE-027's owner session, which Edge issues, would depend on a store that Edge does not own.
  Rejected.
- **The last submitted manifest is in force.** Any process that can submit could widen a site.
  Rejected.

### D10. The SDK is generated, and the template has no framework

`@ratatoskr/site-sdk` generates its types with `openapi-typescript` from the Content Delivery API
description that `ratatoskr-contracts` publishes, as the web client does today. The starter template
is Vite and TypeScript with no UI framework, because the point of a site is that its owner picks the
framework. A `generated-drift` check regenerates the client against the pinned contracts and fails
on any difference.

### D11. Every site route has a class

Routes under `/v1/sites/{site}/` carry three kinds of caller: the owner managing the site from the
web client, the site itself (anonymous visitors now, `site_owner` sessions in SITE-027), and the
sign-in exchange of SITE-027. Edge's route table gives each route one class (`management`,
`site-origin`, `sign-in`, `release`) and refuses to start when one has none, so a new route cannot ship
without a decision about its caller. `POST .../releases` has its own class, `release`, with two guards: the
primary owner session, or a `site_owner` session with `notes.edit`. As a second line, the sites
service refuses Edge's anonymous claim on every route outside `content/`.

### Storage

| What | Where |
|---|---|
| Tables | schema `sites`: `sites`, `site_manifests` (by digest), `approval_projection` (read only, from Platform's event), `publications`, `build_requests`, `releases`, `release_pages`, `release_assets`, `release_search`, `current_releases`, `outbox`, `inbox` |
| Role | `ratatoskr_sites`, in the database `ratatoskr`; `schema.sql` applied at startup under an advisory lock |
| Pages and assets | `/mnt/nvme/ratatoskr/blobs/ratatoskr-sites` |
| Note bytes | read-only, `/mnt/nvme/ratatoskr/blobs/ratatoskr-notes` through the group `ratatoskr-notes-blobs` |
| Ports | 8100 domain API (loopback), 9472 operator (host only) |
| Approvals | Platform `identity.site_approvals`, the only authority |
| Sites user | `ratatoskr-sites`, member of `ratatoskr-notes-blobs` through `deploy/sysusers.d/ratatoskr-sites.conf` |

## Risks / Trade-offs

- **[Risk]** A shared cache keeps withdrawn content.
  → Mitigation: the bounds in `site-content-delivery` (60 s for pages, 3600 s for assets), and the
  owner documentation states them. A Cloudflare purge with an API token is a possible follow-up.
- **[Risk]** The notes resolver and the release builder disagree about which file a link points to.
  → Mitigation: D3, one resolver. The release builder only maps a resolved path to a slug.
- **[Risk]** A burst of public traffic overloads the Pi.
  → Mitigation: the rate limits in D7, the cache rules, and an in-memory set of servable sites so
  that a request for an unknown site costs no database query.
- **[Risk]** A test that searches for canaries misses a leak through a channel that the fixture does
  not have.
  → Mitigation: the fixture is a contract fixture in `ratatoskr-sites`, and every new filter rule
  adds a canary location to it.
- **[Trade-off]** The modified `fleet-bus-topology` and `workspace-fleet-membership` texts require
  OBS-023 to be archived first.
- **[Trade-off]** A slug change breaks inbound links from outside. Redirects are left out.

## Migration Plan

1. Contracts: `crates/sites-contracts`, schemas, fixtures and message registrations.
2. Notes: the internal index route.
3. `ratatoskr-sites`: created by the owner on GitHub, then the service, `schema.sql`, its unit, its
   config example, `role.sql` and its NATS stanza.
4. Platform: ADR-0017, the `public` class, the site route classes, `identity.site_approvals` and
   its routes, the build route and its operation kind, the `SITES` identity and the four durables.
5. `ratatoskr-site-sdk`: created by the owner, then the generated client and the template.
6. Web: the registry, approval, publication editor and release history.
7. Workspace: membership, ports, deploy enrolment, harness expectations, documentation.

Nothing is deployed while the host is frozen (`DEPLOYMENT_TARGET.md`).

**Rollback:** revert each repository's commit. Reverting Platform's route rows removes the public
surface at once. Releases in the sites blob root harm nothing and are removed with the schema.

## Open Questions

- Whether the sites service should purge Cloudflare's cache on withdrawal. It needs an API token
  with purge rights and can be added later without a change to the specs.
