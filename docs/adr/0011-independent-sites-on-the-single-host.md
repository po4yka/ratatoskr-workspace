# ADR-0011: Independent sites read releases through a public API and run on the host

> Status: Proposed  
> Date: 2026-10-13  
> Changes: `openspec/changes/add-site-publications` (SITE-025),
> `openspec/changes/add-site-gateway-hosting` (SITE-026),
> `openspec/changes/add-site-owner-editing-and-live` (SITE-027)  
> Target architecture: [`docs/NOTES_AND_SITES.md`](../NOTES_AND_SITES.md)

## Context

The repository owner asked for individual sites that show content from the connected vaults and
have a fully independent UI. Each site communicates with the system in both directions. The owner
chose three kinds of communication: the owner edits notes from the site, the site receives live
updates, and the site shows other data from the system. The owner chose to host the sites on the
Raspberry Pi behind `cloudflared`.

Today Edge serves only session-authenticated traffic, and ingest serves webhooks. Platform's README
excludes "a public multi-tenant SaaS control plane". A vault is private by default.

Obsidian Publish exists, and `ob publish` can drive it. Its UI belongs to Obsidian, and it has no
channel from the site back to the system.

## Decision drivers

- The UI of each site is the owner's own code, in any stack, in its own repository.
- A vault is private. A site must not leak an unpublished note, its title, or its attachments.
- The Pi has little CPU to spare. Public traffic must be cheap to serve and easy to cache.
- Edge is the one place that authenticates. Every other listener trusts only claims that Edge
  mints (Platform ADR-0015).

## Considered options

### Content model

1. **Ratatoskr as a headless CMS.** A publication selects notes. A release builder makes an
   immutable release. A site reads the release through a public API.
2. **A site reads the notes API directly.** Every site would have to apply the privacy rules
   itself, and one mistake leaks the vault.
3. **Obsidian Publish.** It is hosted by Obsidian, its UI is fixed, and it cannot send data back.

### Rendering and hosting

1. **A static bundle that reads content at runtime.** The site repository's CI builds the bundle.
   A content change needs no rebuild, and SSE delivers updates.
2. **A static site rebuilt on every content change.** One note edit would cost a build on the Pi.
3. **A server-rendered process per site.** It costs one process and its memory per site on the Pi.
4. **External static hosting.** The owner chose the Pi.

## Decision

- **Content option 1 and hosting option 1.**
- A new repository `ratatoskr-sites` (path `repos/sites`, Rust) owns the site registry,
  publications, the release builder, the Content Delivery API and the sites gateway.
- A new repository `ratatoskr-site-sdk` (path `repos/clients/site-sdk`, TypeScript) publishes
  `@ratatoskr/site-sdk` and a starter template. A site is the owner's own repository and is not a
  fleet member.
- **The site manifest** (`ratatoskr-site.toml`) names the hostname, the publications and the
  capabilities. The owner approves it before the site serves.
- **One approval store, in Platform** (`identity.site_approvals`, bound to the manifest digest).
  Edge enforces from it, and the sites service keeps only a read projection, which
  `evt.platform.site_approval.changed.v1` keeps current. Two stores would let a withdrawal reach one
  side and not the other.
- **Every route under `/v1/sites/{site}/` has one class**: management (primary session with
  `platform.owner`), deploy (the owner or the site's `site_deployer` device), release (the owner,
  or a site session with `notes.edit`), site origin (checked against the approved capabilities), or
  sign-in (PKCE). Edge refuses to start when a route has no class.
- **One new Edge route class, `public`.** It is anonymous, cacheable and rate-limited, and it serves
  only the current release of an approved site. It does not make Ratatoskr multi-tenant: a site
  serves one owner's published content.
- **The sites gateway** (`ratatoskr-sites-gateway`, public port 8183) serves each bundle by
  hostname. It forwards `/_r/*` to Edge, so a site and its API share one origin.
- **Owner editing** uses a Platform session whose audience is `site:<site id>`, with only the
  capabilities that the manifest grants. Edits go through the notes write path of OBS-024.

## Consequences

- The fleet grows by two repositories, `ratatoskr-sites` and `ratatoskr-site-sdk`.
- Platform gets a `public` route class, a `site:<id>` session audience, a capability check for site
  routes and a site SSE stream. Each of these needs a Platform ADR in the Platform repository.
- `cloudflared` gets one ingress rule per site hostname.
- Cloudflare caching of public content is a requirement, not an option, because the Pi cannot serve
  much uncached public traffic.

## Security and privacy

- The release builder enforces the privacy rules in `docs/NOTES_AND_SITES.md` section 6. The specs
  of SITE-025 make each rule a test.
- An excluded folder always wins over `publish: true`, and `publish: [<site id>, ...]` limits a note
  to named sites. Two sites on one vault therefore do not publish each other's notes.
- The first release of a publication is always an explicit request, and every build renders every
  page. No page from an earlier release is reused, so a note that becomes private cannot survive in
  a stale link or backlink.
- Anonymous visitors get only `pages.read`, `assets.read`, `search.publication` and `live.release`.
  Owner-only capabilities need a `site:<id>` session.
- The gateway trusts no inbound identity header. The owner session cookie is HttpOnly, Secure,
  SameSite=Strict and bound to the site hostname.
- `docs/THREAT_MODEL.md` gets a section for public sites in SITE-027.

## Compatibility and migration

Additive. No existing route changes behaviour. All new contracts are `v1`.

## Validation

The scenarios in the specs of SITE-025, SITE-026 and SITE-027. The privacy rules are tested with a
fixture vault that holds private notes, private titles, comments and private attachments. A release
built from it must contain none of them.

## Follow-up

- Accept this ADR after the Platform ADRs for the `public` route class and the `site:<id>`
  audience are accepted.
- Prerendering of the current release for search engines is left for later. It is not needed for
  the first site.
