# Proposal

## Why

After `add-site-publications` (SITE-025) and `add-site-gateway-hosting` (SITE-026), a site can show
the current release of its publications to anyone. It cannot do the three other things that the
owner asked for: let the signed-in owner edit the source notes from the site's own UI, push changes
to the site while it is open, and show data from the rest of the system. All three need an owner
identity on the site's own origin, and that identity must not be the owner's main Platform session:
a site is code the owner wrote, served from another hostname, and a bug in it must not expose the
whole account.

`add-notes-write-back` (OBS-024) gives the write path with `base_hash` and conflicts, so the owner
editing in this change only has to reach it.

## What Changes

- A new **owner session for a site**: a Platform session of the new kind `site_owner` whose
  audience is `site:<site id>`. The owner gets it through a one-time sign-in code that the owner's
  primary session approves in `ratatoskr-web`. The code is bound to the site, the approved hostname
  and a PKCE challenge. The site redeems it through the gateway at `/_r/`, and Edge sets a
  host-only, `HttpOnly`, `Secure`, `SameSite=Strict` cookie on the site hostname.
- The owner session authenticates **only** on `/v1/sites/<its site id>/...`. It is refused on every
  other route, and on the routes of every other site. The owner's primary session is never sent to
  the site origin.
- **Route classes and capability enforcement.** The routes of this change join the existing
  `site-route-classes` spec: `sign-in-codes` is `management`, `sessions` is `sign-in`, and the events,
  draft, draft upload, edit, conflict, library and knowledge routes are `site-origin`. The `release`
  class gains its second guard, a `site_owner` session with `notes.edit`. Each site-origin route needs
  one capability, which Edge checks
  against the effective set that SITE-025 `site-manifest` defines. This change stores no approval:
  SITE-025 owns `identity.site_approvals` and the approve and withdraw routes. An owner-only
  capability that the site lacks answers 403 `edge.capability_not_granted`; a public capability that
  the site did not request answers 404 `sites.site_not_found`. Owner-only capabilities (`draft.read`,
  `notes.edit`, `library.read`, `knowledge.search`) are refused to anonymous callers in all cases.
- **Live events** at `GET /v1/sites/{site}/events` (route class `stream`): `release.published` to
  any caller with `live.release`; `draft.changed`, `edit.completed` and `edit.conflicted` to the
  site's owner session only. `Last-Event-ID` resumes the stream, and an id older than the retained
  window starts the stream with a `resync` event. `release.published` carries only the release id
  and time, no page list. Anonymous streams are bounded per client (4) and per site (64).
- **Owner editing**: the owner reads the Markdown source of a page through `draft.read`, uploads
  the new content as a blob through `POST /v1/sites/{site}/drafts/sources/{source_ref}/blobs`, and
  posts the edit with the `BlobRef` to `POST /v1/sites/{site}/edits`. Edge resolves the `source_ref`
  through the sites scope query (connection id and path), opens an operation, and publishes
  `cmd.notes.file.write_requested.v1` with the `base_hash` and `origin: "site:<site id>"`. Edge is the
  only producer of that command, and no file bytes enter its outbox or JetStream. The upload keeps the
  session kind `site_owner` in the claim that Edge mints, and `ratatoskr-notes` accepts such a claim
  for blob registration only. A conflict from
  OBS-024 reaches the site as `edit.conflicted`.
- **Releases follow the publication's release mode** from SITE-025. In a `manual` publication an
  edit starts nothing, and the owner requests a release with `POST /v1/sites/{site}/releases`, which
  publishes `cmd.sites.release.build_requested.v1`. In an `automatic` publication the edit's file
  change starts the build, as SITE-025 defines. The release route works in both modes; this change
  adds its second guard, a `site_owner` session with `notes.edit`.
- **Data from the system**: `GET /v1/sites/{site}/library` and `GET /v1/sites/{site}/knowledge/search`
  reuse the Knowledge surfaces that `/v1/library/search` uses, with the owner session's user as the
  only tenant authority.
- `@ratatoskr/site-sdk` gains owner sign-in, an SSE client with resume, editing helpers and the
  conflict types, and the template ships the reserved `.ratatoskr/sign-in/index.html`.
  `ratatoskr-web` gains the sign-in consent page and `site_owner` sessions in the session list. The
  manifest approval view is SITE-025's.
- New contracts: `sites/site-event.v1`, the registered message type `sites.draft.changed.v1`, and the
  request and response schemas of the routes above.

No item is **BREAKING**. Nothing in this change has shipped, and every route is new.

## Capabilities

### New Capabilities

- `site-owner-session`: how the owner of a site gets, uses, lists and loses a session that is valid
  only for that site.
- `site-capability-enforcement`: how Edge checks the capability of a site-origin request against
  the effective capability set that `site-manifest` defines.
- `site-live-events`: what the site event stream sends, to whom, and how a client resumes it.
- `site-owner-editing`: how an edit made on a site reaches the source note, how a conflict comes
  back, and how the owner publishes the result.
- `site-system-data-access`: how a site reads the owner's library and knowledge search, and the
  limits on that access.

### Modified Capabilities

- `site-route-classes`: the routes of this change get their classes (ADDED requirements, as SITE-026
  did for its deploy routes), the `release` class gains its `site_owner` guard, and the anonymous-claim
  rule gains a scenario for the draft routes.
- `notes-device-channels`: `ratatoskr-notes` accepts a blob upload whose claim names the session kind
  `site_owner` and the origin `site:<id>`, for blob registration only, and Edge does not relabel such a
  session as primary.
- `fleet-bus-topology`: Edge provisions and consumes the new events-stream durable
  `platform_site_events` (filters `evt.sites.release.published.v1` and `evt.sites.draft.changed.v1`),
  the durable-name scan lists it beside the other Edge projections, and the SITES identity may also
  publish `evt.sites.draft.changed.v1`. The identity count (fifteen) and the service durable count
  (thirty) do not change. The delta is written against the text that SITE-026 leaves
  after archive.

`library-search-read-state` stays as it is: the site routes reuse its Knowledge surfaces with
the same single-tenant authority and do not change `/v1/library/search`. `operation-progress` stays
as it is: an edit is an ordinary operation, and the notes service reports it as any producer does.

## Repositories, in merge order

1. `ratatoskr-contracts`: `sites/site-event.v1`, the `sites.draft.changed.v1` registration and the
   route schemas. It merges first, because every
   other repository below builds against them.
2. `ratatoskr-notes`: accepts a blob upload with a `site_owner` claim for registration only. It
   merges before Platform, because Platform starts forwarding site uploads to it.
3. `ratatoskr-platform`: the `site_owner` session kind, the sign-in code, the route classes and the
   capability check, the session revocation on withdrawal, the site event stream, and the blob,
   edit, conflict, release-guard, library and knowledge routes. It
   merges before the sites service, because the sites service only answers loopback questions from
   Edge and publishes `evt.sites.draft.changed.v1`, which nothing reads until Edge does.
4. `ratatoskr-sites`: the loopback scope query (returns the connection id and the path of a
   `source_ref` in this site's publications), the draft source read, the refusal of anonymous claims
   outside `content/*`, and `evt.sites.draft.changed.v1`.
5. `ratatoskr-knowledge`: no code change is expected. Its item closes when the integration test of
   group 12 proves that the site routes see only the owner's data. If the test fails, the fix lands
   here.
6. `ratatoskr-site-sdk`: sign-in, the SSE client, editing helpers and conflict types.
7. `ratatoskr-web`: the consent page and the session list.
8. `ratatoskr-workspace`: the composed integration profile, the threat model update and the pins.

## Outside this change

- Visitor accounts, comments, forms and any write by an anonymous caller. Only the owner writes.
- Editing a note outside the site's publications from the site, even when the owner owns it.
- Collaborative editing in real time (cursors, CRDT). An edit is a whole-file write with a
  `base_hash`.
- The release modes themselves and the coalesced build in `automatic` mode. SITE-025 owns them.
- The gateway itself, hostname routing and bundle deployment (SITE-026), and the release model and
  its privacy rules (SITE-025).

## Rollback

Nothing has shipped, so there is nothing to roll back on a host. Each repository change is reverted
with `git revert`. On a running host, revoking every session of kind `site_owner` disables owner
editing, drafts and system data at once, and leaves the public content of SITE-025 unchanged.

## Impact

- A new Platform table in `identity` for sign-in codes, and a new session kind.
  The schema definition is edited in place; there is no migration.
- New Edge routes under `/v1/sites/{site}/`, all through the route table of Platform ADR-0015.
- A new Edge durable `platform_site_events` for `evt.sites.release.published.v1` and
  `evt.sites.draft.changed.v1`, and a sites publish permission for `evt.sites.draft.changed.v1`.
  Conflicts reach Edge through the OBS-024 durable `platform_notes_conflict_projection`. Edge already
  produces `cmd.notes.file.write_requested.v1` (OBS-024) and `cmd.sites.release.build_requested.v1`
  (SITE-025); this change adds the `site:<id>` origin and the site-session guard.
- `docs/THREAT_MODEL.md` gains the site origin as a trust boundary.
