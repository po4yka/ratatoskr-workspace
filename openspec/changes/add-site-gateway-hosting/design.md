# Design

## Context

See `proposal.md` for the motivation. The constraints that shape the approach:

- **One host.** A Raspberry Pi 5 with four cores and 15 GiB of RAM, shared with other tenants
  (`docs/DEPLOYMENT_TARGET.md`, ADR-0009). Systemd units, one per role (Platform ADR-0013).
- **`cloudflared` is the only public path**, and it terminates TLS. A public listener may trust no
  inbound header that it did not mint itself. Edge authenticates and mints the identity claims for
  every proxied call (Platform ADR-0015).
- **The Pi has no access to GHCR and no `gh`.** DPL-022 verifies artifacts on the controller and
  copies only verified files to the host (`add-deployment-automation`, design D4).
- **SITE-025** owns the `sites` schema, the site manifest with its hostname and the delivery API
  under `/v1/sites/{site}/content`. Approval lives in Platform only (`identity.site_approvals`).
  Edge owns `POST` and `DELETE /v1/sites/{site}/manifest/approval`, publishes
  `evt.platform.site_approval.changed.v1`, and the sites service consumes it through the durable
  `ratatoskr_sites_approvals` and keeps a read projection. This change adds nothing to the manifest
  and no durable. It adds the rewrite of the gateway projection on every such event.
- **Route classes under `/v1/sites/{site}/`** come from SITE-025: `management`, `site-origin`,
  `sign-in` and `release`. `management` is primary owner session only. This change adds a fifth
  class, `deploy`, for the deploy and activate routes (a MODIFIED delta to `site-route-classes`).
- **The host is frozen.** Nothing in this change runs against it.

## Goals / Non-Goals

**Goals:**

- A site whose manifest is approved is served on its hostname from a bundle that CI built,
  attested, and both the controller and the host verified.
- A site deploy and a rollback are owner actions that need no SSH and no fleet pin advance.
- One hostname can never receive another site's bytes or reach another site's API.

**Non-Goals:**

- Server-side rendering, edge functions or any per-site process.
- Zero-cost scaling. The design relies on Cloudflare's cache for public static traffic and only
  bounds what reaches the Pi.
- A site-specific Content Security Policy.

## Decisions

### D1. A separate gateway binary in `ratatoskr-sites`

`ratatoskr-sites-gateway` is a second binary in the sites repository, beside the domain service
from SITE-025. It binds `127.0.0.1:8183` for public traffic and `9473` for its operator listener.

Alternatives:
- **A static route on Edge.** Edge would gain a file server, hostname routing and per-site cache
  policy, and its public listener would carry anonymous site traffic beside session traffic. Edge
  is the identity boundary of the fleet, and that is a reason to keep it small. Rejected.
- **nginx or Caddy on the host.** A second web server with its own configuration language, that no
  repository tests, and that needs its own hardening. Hostname approval would have to be rendered
  into its config. Rejected.
- **`cloudflared` rules straight to a file server per site.** The router would move into tunnel
  configuration, which Platform ADR-0015 option (c) already rejected for the same reason: it is
  invisible to tests.
- **External static hosting.** The owner chose the Pi.

### D2. The routing table is a projection on disk, not a database read

The sites service is the only writer of `/mnt/nvme/ratatoskr/sites/`. For each site it writes:

```text
/mnt/nvme/ratatoskr/sites/<site id>/
├── site.json                 hostnames, approval state, retention; replaced by rename(2)
├── bundles/<commit>/         one verified deploy; read-only after it is written
├── current  -> bundles/<c2>  symbolic link, replaced by rename(2)
└── previous -> bundles/<c1>  symbolic link, replaced by rename(2)
```

The sites service rewrites `site.json` of a site whenever it consumes
`evt.platform.site_approval.changed.v1` for that site: an approval, a withdrawal through
`DELETE /v1/sites/{site}/manifest/approval`, or a new hostname in a new approval. A withdrawn site's
`site.json` lists no hostname. The test `services/sites/tests/gateway_projection.rs` owns this
rewrite. Deploy activation rewrites only the `current` and `previous` links.

The gateway reads this tree read-only through the group `ratatoskr-sites-bundles`. It rebuilds its
hostname table when inotify reports a change under the root, and also every two seconds, so a lost
event delays a change but never loses it. A request resolves `current` once and serves from that
resolved directory, so one response never mixes two deploys.

Alternatives:
- **The gateway reads the `sites` schema.** That needs a second database role, which changes
  `postgres-provisioning`, and makes every public request depend on PostgreSQL. Rejected.
- **The gateway asks the sites domain API.** Every cache miss would cross a loopback hop to a
  process that can be restarting. Rejected.

### D3. Deploy: the owner verifies on the controller and uploads through Edge

The flow:

```text
site repo CI ── reusable-site-bundle.yml ──► ghcr.io/<owner>/<site repo>:sha-<commit> + attestation
controller:  ratatoskr-site deploy --site <id> --commit <sha>
               oras pull → gh attestation verify --repo <owner>/<site repo> → sha256 check
               POST /v1/sites/<id>/deploys   (Edge, class deploy, transfer body budget;
                                             site_deployer device or primary owner session)
host:        ratatoskr-sites receipt: re-check every digest and path rule, write bundles/<commit>,
               then POST /v1/sites/<id>/deploys/<commit>/activate switches current and previous
```

Both deploy routes have the new class `deploy`. Edge accepts a primary session with the live
`platform.owner` grant, or a registered device of the new kind `site_deployer` that was paired for
that site. A new class keeps `management` primary session only; widening `management` to devices
would let a deployer device reach every management route of every site. The upload body streams
under the `transfer` budget of Platform ADR-0015, which is
a body budget and not an authorisation class.

The deploy command authenticates as a `site_deployer` device. The owner creates a pairing code from
a primary session with the expected kind `site_deployer` and one site id (Platform ADR-0016), and
runs `ratatoskr-site login --pairing-code` once on the controller. The command stores the device's
refresh secret in the operating system's credential store, never in the site repository. Edge
mints a claim that names the device kind and the site, and accepts it only on the deploy and
activate routes of that site. The owner lists and revokes the device with the existing device
lifecycle routes. Platform's `identity.registered_devices` kind check gains `site_deployer`, and
the device row records its one site. The schema definition is edited in place.

The host checks the manifest and the digests again, because it is the component that stores the
bytes (Platform ADR-0015, "Uploads traverse edge to per-service receipts"). The attestation is
checked on the controller only, the same split as DPL-022. Activation is a separate call, so the
owner can upload ahead and switch later. The deploy command activates by default.

Alternatives:
- **The Ansible playbook installs bundles, like binaries.** Each site release would need SSH and a
  full playbook run, and site repositories are not in `workspace.lock`, so the pins could not
  describe them. Rejected. The playbook still provisions the gateway itself.
- **The sites service pulls from GHCR and verifies on the Pi.** The Pi would need network access to
  GHCR and a Sigstore trust root, which DPL-022 keeps off the host on purpose. Rejected.
- **The site's CI pushes to Edge with a deploy token.** A long-lived credential would sit in the
  site repository's CI secrets, and a compromise of that CI would publish to the public host.
  Rejected for version 1.
- **The owner's own primary session in the command.** The command would hold a full owner session,
  which reaches every route of the fleet. The `site_deployer` device reaches two routes of one site.
  A primary owner session is still accepted, for a deploy from the web client later.

### D4. The bundle format and the hashed flag

A bundle is an uncompressed tar archive with `ratatoskr-bundle.json` at its root. The reusable
workflow computes the manifest from the build output. It marks a file as content-hashed when it
matches the workflow input `hashed-globs`, whose default is `assets/**`, the output folder of Vite
and Astro. The flag drives two behaviours only: the `immutable` cache header (D6) and the fallback
to the previous deploy (D5). A wrong flag therefore affects caching and never exposes data.

The artifact media type is `application/vnd.ratatoskr.site-bundle.v1`. The default size limit is
64 MiB per bundle, and it is configuration.

### D5. Old clients keep their assets for one switch

A browser that loaded the entry document of commit `a` asks for `a`'s hashed assets after the
switch to `b`. The gateway looks a missing path up in `previous` only when the previous manifest
marks it as hashed. Entry documents and unhashed files are never served from `previous`, so a
rollback is exact and an old page cannot reappear.

### D6. Headers

- Hashed files: `public, max-age=31536000, immutable`. Every other file: `public, max-age=60,
  must-revalidate`. `ETag` is the SHA-256 from the manifest, so the gateway never hashes on request.
- Fixed security headers on every static response: the Content Security Policy in the
  `site-gateway` spec, `X-Content-Type-Options: nosniff`, `Referrer-Policy:
  strict-origin-when-cross-origin` and `X-Frame-Options: DENY`.
- HSTS is set in the Cloudflare zone, because TLS ends at Cloudflare, not at the gateway. The
  runbook step names the setting.
- Responses forwarded from Edge keep Edge's own headers. Edge marks owner responses
  `private, no-store`, so Cloudflare never caches them (SITE-027 tests this).

### D7. Forwarding under `/_r/`

The gateway forwards only `/_r/v1/sites/<site id>/…` for the site that the hostname selects, after
it removes the `/_r` prefix and every `x-ratatoskr-*` header. It streams both directions and
flushes server-sent events per event. It adds no identity header: Edge authenticates the cookie or
treats the request as anonymous, and checks the audience `site:<site id>` itself (SITE-027). The
allowlist is a constant list in the gateway, so SITE-027 extends it with a reviewed code change.

Same-origin forwarding means the site needs no CORS policy, and the owner's session cookie stays
bound to the site hostname.

For `text/event-stream` responses the gateway writes each event to the client as soon as it
arrives, never compresses the stream, passes `Last-Event-ID` through, and uses an idle-read budget
longer than Edge's fifteen-second keep-alive. SITE-027's live updates depend on this.

`/.ratatoskr/` is reserved for SDK pages: every bundle built from the SDK template ships
`.ratatoskr/sign-in/index.html`, which SITE-027 uses as the sign-in callback. The gateway serves
`/.ratatoskr/*` with `no-store` and no entry fallback, so a missing callback fails visibly instead
of loading the site's home page. Unlike `_r/`, this reserved path is allowed inside a bundle,
because the bundle is where the SDK pages come from.

The gateway removes any inbound `X-Ratatoskr-Client-IP` and sets it from `CF-Connecting-IP`. It
opens its connections to Edge from a configured loopback source address, `127.0.0.83` by default,
and Edge trusts the header only on a connection from that address. `cloudflared` and every other
local process connect from another address, so a client that reaches Edge directly cannot choose
its own rate-limit bucket. Edge's per-client `public` bucket (SITE-025) uses this value. A local
process that binds `127.0.0.83` on purpose can still forge it; the host is the trust boundary
(Platform ADR-0015), and the header only selects a bucket.

### D8. Limits

- The client key is `CF-Connecting-IP`. Cloudflare overwrites it at its edge, and the listener binds
  `127.0.0.1`, so only `cloudflared` reaches it. The key is used only for rate limiting, never as an
  identity. A request without the header shares one bucket with every other such request.
- A token bucket per key. The defaults are 20 requests per second with a burst of 60, and both are
  configuration. Over the budget, the response is 429 with `Retry-After`.
- Static paths accept `GET` and `HEAD` only. `/_r/` bodies are capped at 1 MiB at the gateway,
  before Edge's own route-class budget.
- The unit sets `MemoryMax=128M` and `CPUQuota=100%`. These are starting values to measure, not
  results.

### D9. Tunnel ingress is a marked block that the playbook owns

A new task in the Ansible `host` role renders a block between `# BEGIN ratatoskr-sites` and
`# END ratatoskr-sites` in the `cloudflared` configuration, from the list `sites.json` in
`group_vars/all/`. It then runs `systemctl reload-or-restart cloudflared.service`. The standard upstream unit has no
`ExecReload`, so that unit restarts and briefly reconnects the tunnel. A unit that supports reload
uses its reload action. Rules outside the block are not touched. Creating
the DNS record (`cloudflared tunnel route dns`) changes the owner's Cloudflare account, so it stays
a runbook step and no task runs it.

Alternative: one wildcard rule such as `*.sites.<zone>`. It needs no edit per site, but every
subdomain would reach the Pi and custom domains would still need their own rule. The explicit list
is stricter, and a wildcard can be added later without a change to the gateway.

## Risks / Trade-offs

- **[Risk]** Public traffic reaches a small machine. → Mitigation: Cloudflare caches every static
  response that is `public`, the token bucket bounds what is left, and hashed files are cached for a
  year.
- **[Risk]** A forged `CF-Connecting-IP` from a local process. → Mitigation: the listener binds
  `127.0.0.1`, and the header only selects a bucket. A forged value can only spend its own budget.
- **[Risk]** The `cloudflared` configuration is host state that a reflash resets
  (`DEPLOYMENT_TARGET.md`, "What the reflash resets"). → Mitigation: the playbook renders the block
  again on each run.
- **[Risk]** Bundles fill the NVMe. → Mitigation: the size limit per bundle and the retention count
  per site. The current and previous deploys are never removed.
- **[Risk]** A stolen `site_deployer` refresh secret lets an attacker publish to one site. →
  Mitigation: the device reaches only the deploy and activate routes of that site, the controller
  keeps the secret in the operating system's credential store, the owner revokes it with the
  existing device routes, and activating the previous deploy undoes a bad publish.
- **[Trade-off]** The fixed Content Security Policy refuses third-party scripts and fonts. A site
  that needs them waits for a later change. This keeps every site under one reviewed policy.
- **[Trade-off]** A new hostname needs a playbook run for the ingress rule and an owner approval in
  the sites service. Two steps, and both are deliberate.

## Migration Plan

1. `ratatoskr-contracts`: publish `sites/bundle-manifest.v1` and the deploy shapes.
2. `ratatoskr-sites`: the deploy receipt and store, then the gateway binary and its unit.
3. `ratatoskr-platform`: the `site_deployer` device kind and its pairing, the `deploy` class and its rows for
   the deploy routes, and the trust rule for `X-Ratatoskr-Client-IP`.
4. `ratatoskr-site-sdk`: the reusable workflow and the deploy command.
5. `ratatoskr-workspace`: pins, enrolment, the ingress block, the port and storage rows, harness
   checks and documentation.
6. The real host: nothing, until the owner lifts the freeze. Then the runbook adds the DNS record and
   the HSTS setting for each hostname.

**Rollback:** revert each repository's commit. After the host is live, removing a hostname from
`sites.json` and running the playbook removes its ingress rule, and activating the previous deploy
rolls a site back.

## Open Questions

- The exact defaults for the rate limit, the bundle size limit and the retention count. They are
  configuration and can be tuned after the first measurements, without changing the specs.
- Whether the gateway later serves the web client's bundle. That stays an open decision in
  `DEPLOYMENT_TARGET.md` and does not change this design.
- At the original implementation, no repository bound a deploy bundle to a site. The site manifest
  and its approval hold no repository, so Platform and the sites service cannot check that a bundle
  of a `site_deployer` device comes from the repository of that site; the device is bound to the
  site only. A field for it needs a contract change and a Platform change, and this change adds
  none.

## Owner decision, 2026-10-16

The owner chose server-side verification of signed bundle origin, bound to one approved GitHub
repository per site. The current raw-tar server path does not enforce that decision. The separate
change `bind-site-bundles-to-github` (SITE-028) plans the approval contract, server verification,
SDK request, activation policy and fleet rollout. Runtime dependencies still require the explicit
owner decision recorded there. This amendment records the decision; it does not claim implementation.
