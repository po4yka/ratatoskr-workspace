# Spec Delta

## Purpose

Defines how Edge decides, for a site-origin request, whether the caller may use the capability that
the route needs. The class of each route is defined by `site-route-classes`, and which capabilities
a site has is defined by `site-manifest`; this capability only enforces the effective set on
site-origin routes.

## ADDED Requirements

### Requirement: Every site-origin route needs one named capability

Each site-origin route SHALL be bound to exactly one capability from the closed list `pages.read`,
`assets.read`, `search.publication`, `live.release`, `draft.read`, `notes.edit`, `library.read` and
`knowledge.search`. Platform SHALL check that capability against the site's effective capability
set, as SITE-025 `site-manifest` defines it, before it forwards the request or reads any data for
it.

#### Scenario: A site-origin route without a capability

- **WHEN** the Edge route table holds a site-origin route that names no capability
- **THEN** Edge refuses to start and names the route
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_capabilities.rs::site_origin_route_names_one_capability`

### Requirement: Refusals do not reveal what a site has

For a site-origin request, Platform SHALL answer 404 `sites.site_not_found` when the site has no
approved manifest, when its approval is withdrawn, or when the route's capability is a public
capability that the site did not request. It SHALL answer 403 `edge.capability_not_granted` when a
`site_owner` session of that site calls a route whose owner-only capability is not in the effective
set.

#### Scenario: A public capability that was not requested

- **WHEN** an anonymous caller requests `GET /v1/sites/{site}/content/search` for an approved site whose manifest does not request `search.publication`
- **THEN** Platform returns 404 `sites.site_not_found`, the same answer as for an unknown site
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_capabilities.rs::unrequested_public_capability_is_site_not_found`

#### Scenario: An owner-only capability that was not granted

- **WHEN** a `site_owner` session calls `GET /v1/sites/{site}/library` and `library.read` is not in the effective set
- **THEN** Platform returns 403 `edge.capability_not_granted` and Knowledge receives no request
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_capabilities.rs::ungranted_owner_capability_is_forbidden`

### Requirement: Owner-only capabilities never reach an anonymous caller

The capabilities `draft.read`, `notes.edit`, `library.read` and `knowledge.search` SHALL need a
`site_owner` session of the requested site. An anonymous caller, or a session of another site, SHALL
get the unauthenticated error on their routes, whatever the manifest and the approval say.

#### Scenario: An anonymous caller asks for a draft

- **WHEN** an anonymous caller requests `GET /v1/sites/{site}/drafts/pages/home` for a site whose effective set includes `draft.read`
- **THEN** Platform returns the unauthenticated error and the sites service receives no request
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_capabilities.rs::owner_only_capability_refuses_anonymous`

#### Scenario: A withdrawn site

- **WHEN** a `site_owner` session calls `GET /v1/sites/{site}/drafts/pages/home` after the approval of that site is withdrawn
- **THEN** Platform returns the unauthenticated error, because the withdrawal revoked the session, and an anonymous `content/*` request returns 404 `sites.site_not_found`
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_capabilities.rs::withdrawn_site_is_site_not_found`

### Requirement: An unknown effective set fails closed

When Platform cannot determine a site's effective capability set, it SHALL refuse every owner-only
capability of that site, and the release route for a `site_owner` session, with the stable retryable
unavailable error.

#### Scenario: The sites service is down

- **WHEN** the sites domain API refuses connections and a `site_owner` session posts to `/v1/sites/{site}/edits`
- **THEN** Platform returns the retryable unavailable error and publishes no command
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_capabilities.rs::unknown_effective_set_fails_closed`
