# Proposal

## Why

`add-site-publications` (SITE-025) gives a site its content through the delivery API, but nothing
serves the site itself. A site is the owner's own repository with its own UI, and the owner chose to
host sites on the Raspberry Pi behind `cloudflared` (`docs/NOTES_AND_SITES.md` section 6). Today the
host has no listener that serves static files, the port table has no row for one, and
`DEPLOYMENT_TARGET.md` says that a static bundle has no place to go (the web client has the same
open question).

This change adds that place: one gateway that serves each approved site by hostname, and one
verified path from a site repository's commit to a running bundle on the host.

## What Changes

- Add the binary `ratatoskr-sites-gateway` to `ratatoskr-sites`. It binds `127.0.0.1:8183` as the
  public listener that `cloudflared` reaches, and `9473` as its operator listener. It serves the
  static bundle of each site by the `Host` header, and only for a hostname that an approved site
  names. An unknown hostname gets a 404 contract envelope and never another site's bytes.
- The sites service rewrites the gateway's projection of a site (`site.json`) on every
  `evt.platform.site_approval.changed.v1` that it consumes through `ratatoskr_sites_approvals`
  (SITE-025): an approval, a withdrawal through Edge's `DELETE /v1/sites/{site}/manifest/approval`
  (SITE-025), or a hostname change. The gateway applies the new projection within five seconds.
- The gateway forwards `/_r/v1/sites/<site id>/…` to Edge on `127.0.0.1:8080`, for the site of the
  request hostname only, so a site and the Ratatoskr API share one origin. It strips every inbound
  `x-ratatoskr-*` header, streams bodies without buffering, flushes each server-sent event at once,
  and adds no identity. It sets `X-Ratatoskr-Client-IP` from `CF-Connecting-IP`, and Edge trusts that
  header only from the gateway's loopback source address. Edge stays the only component that
  authenticates and mints claims (Platform ADR-0015).
- `/.ratatoskr/` is reserved for SDK pages: every bundle built from the SDK template ships
  `.ratatoskr/sign-in/index.html`, and the gateway serves `/.ratatoskr/*` with `no-store` and no entry
  fallback.
- The gateway sets fixed security headers (a default Content Security Policy, `nosniff`, a referrer
  policy and frame denial), and cache headers: `immutable` for files the bundle marks as
  content-hashed, and a short TTL for the entry document. HSTS is a Cloudflare zone setting.
- The gateway enforces its own limits before any work: a per-client token bucket keyed on
  `CF-Connecting-IP`, `GET` and `HEAD` only for static paths, and a body cap on `/_r/`.
- Add the **site bundle**: a tar archive of static files with a `ratatoskr-bundle.json` manifest
  (schema `sites/bundle-manifest.v1`: site id, repository, commit, entry document, and every file
  with its SHA-256 and size). A reusable workflow in `ratatoskr-site-sdk` builds it in the site
  repository's CI, pushes it as an OCI artifact tagged `sha-<commit>`, and attests it.
- Add the deploy path. The owner runs `ratatoskr-site deploy` from `@ratatoskr/site-sdk` on the
  controller. It pulls the artifact, verifies the attestation and the checksums there, and uploads
  the bundle through Edge to `POST /v1/sites/{site}/deploys`, a route of the new class `deploy`. The command
  authenticates as a registered device of the new kind `site_deployer`, which the owner pairs for
  one site through Platform ADR-0016 pairing; a primary session with `platform.owner` is also
  accepted. `ratatoskr-sites` verifies every file against the manifest again, stores
  the bundle under `/mnt/nvme/ratatoskr/sites/<site id>/bundles/<commit>`, and switches the site's
  current deploy atomically. Activating an earlier deploy is the rollback, and it needs no download.
- `ratatoskr-workspace` enrols the gateway unit in the Ansible inventory, creates the directories and
  the `ratatoskr-sites-bundles` group, manages a marked block of `cloudflared` ingress rules for site
  hostnames, and records ports 8183 and 9473 and the storage rows in `DEPLOYMENT_TARGET.md`. The
  freeze guard of ADR-0009 applies unchanged.

No item is **BREAKING**. Nothing in this change has shipped, and no existing route, port or unit
changes.

## Capabilities

### New Capabilities

- `site-bundles`: the bundle format, how a site repository builds and attests it, how a deploy is
  verified, stored and activated, how a deploy is rolled back, and how the owner pairs a
  `site_deployer` device for one site.
- `site-gateway`: how the gateway maps a hostname to a site, what it serves, which headers it sets,
  what it forwards to Edge, and which limits it enforces.
- `single-host-sites-deployment`: the port, storage, group, unit and `cloudflared` facts that the
  gateway needs on the one host, and the rule that recording them does not change the frozen host.

### Modified Capabilities

- `site-route-classes`: adds the fifth class `deploy` for `POST .../deploys` and
  `POST .../deploys/{commit}/activate`, served to a primary session with the live `platform.owner`
  grant or to a `site_deployer` device paired for that site. The `management` class stays primary
  session only. This delta requires SITE-025 to be archived first.

Other shared capabilities do not change. The gateway has no database role, so
`postgres-provisioning` does not change. The `release-artifacts` capability of DPL-022 covers
binaries that a systemd unit starts. A site bundle is not a binary and no unit starts it, so this
change adds `site-bundles` beside it and reuses its verification pattern without changing its
requirements.

## Repositories, in merge order

1. `ratatoskr-contracts`: the `sites/bundle-manifest.v1` schema and the request and response shapes
   of the deploy routes. It merges first, because every repository below reads them.
2. `ratatoskr-sites`: the deploy receipt and the deploy store in the domain service, and the
   `ratatoskr-sites-gateway` binary with its unit. It needs SITE-025 merged, because the gateway
   reads the approved manifest that SITE-025 introduces.
3. `ratatoskr-platform`: the `site_deployer` device kind and its pairing for one site, the `deploy`
   route class and its rows for the deploy and activate routes, and the trust rule for
   `X-Ratatoskr-Client-IP`. The `/v1/sites` prefix, the route classes and the approval routes come
   from SITE-025. It merges before `ratatoskr-site-sdk`, whose deploy command pairs as that device.
4. `ratatoskr-site-sdk`: the reusable bundle workflow and the `ratatoskr-site deploy` command.
5. `ratatoskr-workspace`: pins, the Ansible enrolment and ingress block, the port and storage rows,
   the harness checks and the documentation. It merges last. Its provisioning part waits until DPL-022
   (`add-deployment-automation`) is merged and archived, because it extends that playbook, its
   Molecule scenario and `deploy_inventory.rs`.

## Outside this change

- Server-side rendering or any site process other than static files. A site that needs a server
  is a separate decision.
- Building site bundles on the host. The host never runs a site repository's build.
- Per-site Content Security Policy exceptions. Version 1 has one fixed policy.
- Creating DNS records. `cloudflared tunnel route dns` is an operator step that the runbook
  describes, because it changes the owner's Cloudflare account.
- The web client's bundle. The gateway could serve it later, but that remains an open decision in
  `DEPLOYMENT_TARGET.md`.
- Owner sign-in, owner editing and live updates (SITE-027). This change forwards only the
  `/_r/v1/sites/<site id>/` prefix, and SITE-027 extends that allowlist.
- Running anything on the real host. The freeze lifts only when the owner edits
  `DEPLOYMENT_TARGET.md`.

## Rollback

Nothing has shipped, so there is nothing to roll back on a host. Each repository change is reverted
with `git revert`. After the host is live, removing a hostname from the managed ingress block stops
that site at the tunnel, and activating the previous deploy rolls a site back without a download.

## Impact

- New: `services/sites-gateway` and its unit in `ratatoskr-sites`; a deploy receipt, deploy
  tables and the projection rewrite in its existing service; the `site_deployer` device kind in
  Platform's `identity` schema, edited in place; `sites/bundle-manifest.v1` in `ratatoskr-contracts`;
  `.github/workflows/reusable-site-bundle.yml` and the `deploy` command in `ratatoskr-site-sdk`.
- Changed: Edge's route table in `ratatoskr-platform`; `deploy/ansible/` (enrolment, host
  directories, ingress block), `docs/DEPLOYMENT_TARGET.md` and `docs/NOTES_AND_SITES.md` in this
  repository.
- Host: one more systemd unit, one user, one group, one directory tree on NVMe, and one marked block
  in the `cloudflared` configuration. No new runtime: the gateway is a Rust binary.
- Public traffic: anonymous requests now reach the Pi. Cloudflare caching of static files is
  expected and the gateway's headers make it safe.
