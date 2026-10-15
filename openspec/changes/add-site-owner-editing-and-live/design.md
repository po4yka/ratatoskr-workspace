# Design

## Context

See `proposal.md` for the motivation, and `docs/NOTES_AND_SITES.md` for the shared names: the
capability table, the subjects and the routes.

These facts shape the design:

- `identity.sessions` separates `kind` and `audience`. Each kind has its own lifetime, rotation and
  revocation (ARCHITECTURE S6.2). `audience` names the listener at which a session may be presented,
  and `session::authenticate` requires it to match (Platform ADR-0012, amendment).
- Pairing (ADR-0016) is the model for a single-use, digest-only, short-lived code approved by a
  primary session. A primary session is one that an already paired device did not open.
- Edge authenticates once, then mints claims for the owning service. Bodies and SSE stream through
  without buffering (ADR-0015). The existing operation stream sends a keep-alive every 15 seconds and
  resumes from `Last-Event-ID` (`crates/public-api/src/stream.rs`).
- SITE-025 owns the manifest, its approval in `identity.site_approvals`, the approve and withdraw
  routes, `evt.platform.site_approval.changed.v1` and the effective-set rule (`site-manifest`). It
  also owns the release route and the release modes.
- SITE-026 owns the sites gateway. Under `/_r/` the gateway forwards to Edge, so the site and the API
  share one origin. The gateway sets `X-Ratatoskr-Client-IP` from `CF-Connecting-IP` and serves
  `/.ratatoskr/*` with `no-store` and no entry fallback.
- OBS-024 owns the write path: `cmd.notes.file.write_requested.v1` with `origin`, content as a
  `BlobRef` uploaded first, pending writes that become current only after the channel acknowledges
  them, and the Edge durable `platform_notes_conflict_projection`.

## Goals / Non-Goals

**Goals:**

- A credential on the site origin that can do nothing outside that one site.
- One place, Edge, that enforces the effective capability set that SITE-025 defines.
- Live updates that cost the Pi a bounded amount, whatever the number of open pages.
- Edits that always pass through the OBS-024 write path, with its `base_hash` and its conflicts.

**Non-Goals:**

- A general OAuth or OpenID provider for third-party applications.
- Per-visitor identity. Anonymous callers stay anonymous.
- A second approval store or a second definition of the effective set.
- Changing how `/v1/library/search` or `/v1/operations/{id}/events` behave for the existing clients.

## Decisions

### D1. Sign-in is an authorization code with PKCE, approved by the primary session

The flow:

```
 site (owner clicks "Sign in")
   │ 1. SDK makes verifier V, challenge C = S256(V); keeps V in sessionStorage on the site origin
   │ 2. top-level navigation to web: /sites/<site>/sign-in?challenge=C&return=<path>
   ▼
 ratatoskr-web (owner's primary session with platform.owner)
   │ 3. shows site name, hostname and approved capabilities; owner confirms
   │ 4. POST /v1/sites/<site>/sign-in-codes {challenge, return}    (management class)
   │    → Edge stores digest of code K, bound to site, user, C, return path, approved hostname;
   │      TTL 60 s; single use
   │ 5. redirect to the SDK callback page https://<hostname>/.ratatoskr/sign-in/?code=K
   ▼
 site origin → gateway → Edge
   │ 6. callback page posts {code: K, verifier: V} to /_r/v1/sites/<site>/sessions   (sign-in class)
   │ 7. Edge: digest(K) live and unused, site matches, S256(V) = C, Origin = approved hostname
   │    → session kind `site_owner`, audience `site:<site>`; Set-Cookie __Host-ratatoskr-site
   │ 8. the callback page navigates to the return path; the code is not in the final URL
```

`/.ratatoskr/` is reserved for SDK pages. Every bundle built from the SDK template ships
`.ratatoskr/sign-in/index.html`, and the gateway serves `/.ratatoskr/*` with `no-store` and no entry
fallback (SITE-026 owns the gateway rule). The callback page reads the code from the URL, removes it
with `history.replaceState`, and makes the POST of step 6. The redirect of step 5 carries
`Referrer-Policy: no-referrer`.

Alternatives:

- **A relay row claimed by a service, as in ADR-0012.** That record carries a code to a *service*.
  Here the receiver is a browser on another origin, so a service-claimed relay does not apply. The
  digest-only, single-use, short-lived storage of ADR-0016 is reused instead.
- **Device pairing (ADR-0016).** The owner would copy a code by hand into the site for every
  sign-in, and the result would be a `device` session with a root secret, which a browser page must
  not hold. Rejected.
- **Give the site the owner's primary bearer.** Any script on the site could then use the whole
  account. Rejected.
- **A code without PKCE.** A code that leaks from the URL (history, a log, an extension) could be
  redeemed by anyone. With PKCE the code is useless without the verifier, which never leaves the
  site origin. Chosen with PKCE.

### D2. A new session kind `site_owner`, audience `site:<site id>`

`site_owner` joins the closed list in `sessions_kind_is_known`. Its rules:

- Absolute lifetime 12 hours. Idle timeout 1 hour, measured with `last_seen_at`. No refresh token:
  when it ends, the owner signs in again, which is one confirmation while the primary session lives.
- Each sign-in makes a new session. Signing in again does not extend an old one.
- `session::authenticate` accepts a `site_owner` session only on a site-origin route or the release
  route whose `{site}` equals the audience suffix. It accepts it from the cookie
  `__Host-ratatoskr-site` only, and reads that cookie on no other route.
- The owner's session list (ADR-0016 settings surface) shows `site_owner` sessions with the site id
  and the hostname. The owner can revoke one, or all the sessions of one site.
- The SITE-025 withdraw route (`DELETE /v1/sites/{site}/manifest/approval`) revokes every
  `site_owner` session of that site in the same transaction. This change adds that effect to the
  route; it does not add a route.

Alternative: kind `browser` with a site audience. Rejected, because the lifetime and the route rule
are different from a browser session, and ARCHITECTURE S6.2 gives each different set of rules its own
kind.

### D3. Route classes, and enforcement of the SITE-025 effective set

`site-route-classes` (SITE-025, extended by SITE-026) already holds five classes: `management`,
`site-origin`, `sign-in`, `release` and `deploy`, and Edge refuses to start when a route under
`/v1/sites/{site}/` has none. This change adds no class. It adds its routes to that spec:

| Route | Class |
|---|---|
| `POST .../sign-in-codes` | management |
| `POST .../sessions` | sign-in |
| `GET .../events`, `GET .../drafts/*`, `POST .../drafts/sources/{source_ref}/blobs`, `POST .../edits`, `GET .../conflicts/*`, `GET .../library`, `GET .../knowledge/search` | site-origin |

The rows go in as ADDED requirements, as SITE-026 did for its deploy routes, because one more row in
the existing table would push that requirement past 500 characters. The `release` class gains its
second guard, a `site_owner` session of the site with `notes.edit`.

The rule "one capability per route" applies to the site-origin class only. Edge checks the
capability against the effective set that SITE-025 `site-manifest` defines (capabilities of the last
approved manifest ∩ capabilities that the active manifest declares). This change does not restate
that rule and does not store approvals.

Refusals (decision A of the coordination record):

- unapproved or withdrawn site, or a public capability the site did not request: 404
  `sites.site_not_found`, the same answer as an unknown site;
- an owner-only capability that the `site_owner` session's site lacks: 403
  `edge.capability_not_granted`;
- an owner-only route called anonymously or with a session of another site: the unauthenticated
  error, whatever the manifest says.

When Edge cannot determine the effective set, owner-only capabilities and the site-session guard of
the release route fail closed with the retryable unavailable error. The sites service also refuses
an anonymous claim on every route outside `content/*`, so a mistake in the Edge table does not expose
drafts.

Alternative: the sites service enforces the capabilities. Rejected, because the library and
knowledge routes do not pass through the sites service, and two enforcement points can disagree.

### D4. CSRF defence in three layers

- The cookie is `SameSite=Strict` and host-only (`__Host-` prefix).
- Every unsafe method on a site-origin route and on the release route needs the header
  `X-Ratatoskr-Site-Request: 1`. A cross-origin page cannot send it without a CORS preflight, and
  Edge answers no CORS preflight on any route under `/v1/sites/{site}/`.
- Edge compares `Origin` on every unsafe method with the approved hostname of the site.

### D5. The event stream is one fan-out in Edge with a bounded buffer

Edge has one durable, `platform_site_events`, with the filters `evt.sites.release.published.v1` and
`evt.sites.draft.changed.v1`. Conflict events reach Edge through the OBS-024 durable
`platform_notes_conflict_projection`, and edit completion through the operation projection that
already exists. Edge keeps, per site, a ring buffer of the last 256 events or the last 24 hours,
whichever is smaller. Each SSE connection reads from that buffer. The event id is opaque and
increases within a site.

- `Last-Event-ID` inside the buffer: the stream replays the events after it, then follows.
- `Last-Event-ID` outside the buffer, or unknown: the stream starts with a `resync` event, and the
  client fetches the current state again.
- Keep-alive every 15 seconds, the same as the operation stream.
- Anonymous connections have two bounds: per client (default 4) and per site (default 64). The
  client key is `X-Ratatoskr-Client-IP`, which Edge trusts only from the gateway's loopback peer.
  Above either bound, Edge answers with the stable retryable unavailable error. Owner connections
  count against neither.
- The gateway flushes per event (SITE-026).

| Event type | Source | Who receives it | Payload |
|---|---|---|---|
| `release.published` | `evt.sites.release.published.v1` | any caller with `live.release` | release id, publication time |
| `draft.changed` | `evt.sites.draft.changed.v1` | owner session of the site | source ref, revision hash, slug when the note is published |
| `edit.completed` | operation success of an edit with origin `site:<id>` | owner session of the site | operation id, source ref, new revision hash |
| `edit.conflicted` | `evt.notes.conflict.raised.v1` for an edit with origin `site:<id>` | owner session of the site | operation id, conflict id, source ref |
| `resync` | Edge | any caller | none |

`release.published` carries no page list: a site refetches the navigation. A list of changed slugs
would tell an anonymous watcher which pages changed and when, and the navigation fetch is cached.

`sites.draft.changed.v1` is a new message type that this change registers in contracts. The sites
service is its only producer and Edge its only consumer.

Alternative: one NATS consumer per SSE connection, which gives exact replay from the stream
sequence. Rejected for the Pi: the cost grows with every open page.

### D6. Owner editing goes through Edge to the notes write path

- `GET /v1/sites/{site}/drafts/pages/{slug}` and `GET /v1/sites/{site}/drafts/sources/{source_ref}`
  (`draft.read`) return the Markdown source, the opaque `source_ref` and the current revision hash.
  The sites service answers; a public page never carries a `source_ref` or a vault path.
- `POST /v1/sites/{site}/drafts/sources/{source_ref}/blobs` (`notes.edit`, budget class `transfer`)
  resolves the `source_ref` through the sites scope query and streams the body to the notes transfer
  route `/v1/notes/connections/{id}/blobs`. It returns the `BlobRef` and the content hash. Edge does
  not keep the bytes. The claim that Edge mints for the upload names the session kind `site_owner`
  and the origin `site:<site id>`; Edge never presents the session as primary. OBS-024 lets
  `ratatoskr-notes` accept uploads only from a primary session, so this change adds a rule to
  `notes-device-channels`: a `site_owner` claim may register a blob and do nothing else (no change
  batch, no manifest, no revision).
- `POST /v1/sites/{site}/edits` (`notes.edit`) carries `source_ref`, `base_hash`, the `BlobRef`, the
  content hash and an idempotency key. Edge resolves the `source_ref` through the sites scope query,
  which returns the connection id and the path, opens an operation, and publishes
  `cmd.notes.file.write_requested.v1` through its outbox with `origin: "site:<site id>"`. Edge is the
  only producer of that command. No file bytes enter the outbox or JetStream.
- The write is pending until the channel acknowledges it (OBS-024). `edit.completed` is sent when
  the operation succeeds, so the site never shows a revision that the vault does not have.
- A conflict comes back as `evt.notes.conflict.raised.v1`. Edge sends `edit.conflicted`.
  `GET /v1/sites/{site}/conflicts/{conflict_id}` returns the three versions and the merge proposal,
  for a file in scope only. The owner resolves it with a new edit whose `base_hash` is the current
  revision.
- An edit can only change content. Rename, move and delete from a site are outside this change.

### D7. A release after an edit follows the publication's release mode

SITE-025 gives each publication a release mode, `automatic` (the default) or `manual`, and makes the
first release of every publication explicit. This change adds no trigger of its own:

- `automatic`, after the first release: an edit changes a selected file, and that file change starts
  a coalesced build inside the sites service. The SITE-025 requirement "A build starts only from the
  owner or from a selected file change" owns the rule. Edge publishes no command for the edit.
- `manual`: an edit starts nothing. The site shows unpublished edits through `draft.read`, and
  anonymous callers see the previous release until a release is requested.
- `POST /v1/sites/{site}/releases` works in both modes. This change adds its second guard, a
  `site_owner` session with `notes.edit`. It publishes `cmd.sites.release.build_requested.v1`, and
  Edge is the only producer of that command.

Why `manual` exists: releasing after every edit publishes text that the owner has not reviewed on
the public page, and it makes a release build on the Pi for every save. A publication where that
matters, for example one that the owner edits in many small steps from the site, uses `manual`.

### D8. System data reuses the existing Knowledge surfaces

`GET /v1/sites/{site}/library` (`library.read`) and `GET /v1/sites/{site}/knowledge/search`
(`knowledge.search`) call the same Knowledge surfaces as `/v1/library/search`, with the session's
user as the only tenant authority and the same bounds. Any tenant selector is refused, as in
`library-search-read-state`. Knowledge does not learn that the caller is a site.

## Risks / Trade-offs

- [A bug or a malicious dependency in the site code runs with the owner session] → The session can
  use only the effective capabilities of that site, for 12 hours at most, and the owner can revoke
  it from the session list or withdraw the approval. The threat model records the site origin as a
  trust boundary.
- [The sign-in code is in a URL] → PKCE, single use, 60 seconds, `no-referrer`, `no-store` on the
  callback page, and the SDK removes the code from history before it posts it.
- [The ring buffer loses events after a restart of Edge] → The client gets `resync` and fetches the
  current state. No event carries state that a fetch cannot give again.
- [Many anonymous viewers on the Pi] → The per-client and per-site bounds and the keep-alive interval
  bound the cost. Cloudflare does not cache SSE, so the bounds are the protection.
- [Clients behind one address share the per-client bound] → Accepted; the per-site bound is the real
  protection, and the per-client bound only stops one client from taking it all.

Known limits that the review of Platform groups 5 to 8 accepted (Platform `da2242b`):

- [Edge reads the upload of a site edit into memory] → Up to 16 MiB per request (one chunk of the
  notes transfer contract). The per-site and per-client bounds limit how many such reads run at once.
- [The owner shares the public rate bucket of the site] → An owner request from a site, an owner
  stream included, takes a token of the public bucket of that site, so heavy anonymous traffic can
  slow the owner. Accepted: a separate bucket would need a second key per site.
- [`content_blob` is not checked to be the blob of this upload] → Edge checks the `BlobRef` and its
  digest, not that the same request uploaded it. The same digest means the same bytes, so the write
  is the same.
- [The manifest is read on every content request] → Edge has no manifest cache, so each content
  request of a site costs one read of the sites service (an owner decision: a cache could serve a
  withdrawn manifest).
- [A late event never reaches a live stream] → An event older than 24 hours when Edge settles it is
  not appended to the buffer of a live stream. A client sees it through `resync` or a new read.
- [An open stream is not session activity] → An owner stream does not keep its session alive: the
  stream ends at the earlier of the session expiry and 1 hour after the last use of the session.

## Migration Plan

There is no migration. The Platform schema definition is edited in place. Deploy order follows the
merge order in `proposal.md`. Until `ratatoskr-web` ships the consent page, no owner session can be
made, so a partial deploy exposes nothing.

## Open Questions

- The defaults of 4 anonymous SSE connections per client and 64 per site are starting values.
  Measure them on the host during the integration run and adjust them in configuration; no spec
  depends on the numbers.
