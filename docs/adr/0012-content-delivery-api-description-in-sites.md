# ADR-0012: The Content Delivery API description lives in `ratatoskr-sites`

> Status: Accepted  
> Date: 2026-10-15  
> Decided by: the workspace coordinator, under the repository owner's instruction to complete the
> work  
> Changes: `openspec/changes/add-site-publications` (SITE-025), task 3.7  
> Related: [ADR-0011](0011-independent-sites-on-the-single-host.md)

## Context

SITE-025 task 3.6 said that `ratatoskr-contracts` adds the Content Delivery API to "the published
API description", and design D10 said that `@ratatoskr/site-sdk` generates its types from that
description. `ratatoskr-contracts` publishes message schemas and documents (`sites/release.v1`,
`sites/page.v1`, `sites/site-manifest.v1`), not HTTP route descriptions. Platform's routes are
described in Platform's own `openapi/openapi.json`, and `ratatoskr-web` pins that file with a digest
lock (`openapi/openapi.lock.json`: the digest, the Platform commit and the generator version).

The Content Delivery API is served by `ratatoskr-sites` through Edge in the `public` route class.
Its routes, their parameters and their cache rules change with that service, not with the
contracts.

## Decision drivers

- One owner for each description: the repository that serves a route describes it.
- The site SDK must fail its build when the description it generated from changes.
- The documents that the routes return stay one shared definition, in `ratatoskr-contracts`.
- No new mechanism: the fleet already pins an API description with a digest lock.

## Considered options

1. **`ratatoskr-contracts` publishes the description.** Rejected. The contracts repository would
   describe routes it does not serve, and every route change of the sites service would need a
   contracts release first.
2. **Platform's `openapi/openapi.json` describes the routes.** Rejected. Edge forwards the `public`
   class to the sites service and does not own its routes.
3. **`ratatoskr-sites` publishes the description, and the SDK pins it.** Chosen.

## Decision

The Content Delivery API description lives in `ratatoskr-sites` as `openapi/content-delivery.json`.
Its schemas reference `sites/release.v1` and `sites/page.v1` of `ratatoskr-contracts` and do not
copy them. `ratatoskr-site-sdk` pins the file with a digest lock, in the same way as `ratatoskr-web`
pins Platform's `openapi/openapi.json`: the lock records the digest of the file, the `ratatoskr-sites`
commit and the generator version, and the SDK's check fails when the vendored file and the lock
disagree.

## Consequences

- SITE-025 task 3.6 does not add an API description to `ratatoskr-contracts`.
- SITE-025 tasks 7.2 and 7.3 (the generated client and its drift check) wait for
  `openapi/content-delivery.json` in `ratatoskr-sites`.
- Design D10 of SITE-025 names `ratatoskr-sites` as the source of the description.
- A route change in `ratatoskr-sites` reaches the SDK only through a new lock in the SDK.

## Security and privacy

The description states only public routes and the shapes of published content. It holds no secret,
no private hostname and no route of the owner's session.

## Compatibility

The API keeps its first version, as the development status in `AGENTS.md` requires. An additive
change to the description is a new digest in the SDK's lock.

## Validation

- `ratatoskr-sites` checks that `openapi/content-delivery.json` describes the routes it serves.
- `ratatoskr-site-sdk` checks that its vendored copy matches its lock (SITE-025 tasks 7.2 and 7.3).

## Follow-up

- Add `openapi/content-delivery.json` to `ratatoskr-sites`.
- Then implement SITE-025 tasks 7.2 and 7.3 in `ratatoskr-site-sdk`.
