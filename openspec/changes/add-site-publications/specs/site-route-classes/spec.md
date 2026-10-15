# Spec Delta

## Purpose

Defines the class of every route under `/v1/sites/{site}/`, the guard that each class applies at
Edge, and the check in the sites service that keeps an anonymous claim on the public content routes.

## ADDED Requirements

### Requirement: Every site route has exactly one class

Every route under `/v1/sites`, the collection itself and every route under `/v1/sites/{site}/`,
SHALL have exactly one class (`management`, `site-origin`, `sign-in` or `release`) in Edge's route
table, and Edge SHALL fail to start when one has none. A
later change that needs another class adds it to this requirement.

#### Scenario: A route without a class stops Edge

- **WHEN** Edge's route table holds a route under `/v1/sites/{site}/` with no class
- **THEN** Edge refuses to start and names the route, verified by
  `crates/public-api/tests/site_route_classes.rs::unclassified_site_route_fails_start_up` in
  `ratatoskr-platform`

### Requirement: The routes of this change have fixed classes

The routes that this change adds SHALL have these classes in Edge's route table:

| Route | Class |
|---|---|
| `GET /v1/sites` | management |
| `GET .../manifest` | management |
| `PUT .../manifest` | management |
| `POST`, `DELETE .../manifest/approval` | management, served by Edge |
| `.../publications` and `.../publications/{publication}` (`GET`, `PUT`, `DELETE`) | management |
| `GET .../releases` | management |
| `POST .../releases` | release |
| `GET`, `HEAD .../content/*` | site-origin, class `public` |

#### Scenario: The route table matches the class list

- **WHEN** the test reads Edge's route table rows under `/v1/sites/{site}/`
- **THEN** each route of the table above has exactly the class it lists, verified by
  `site_route_classes.rs::site_routes_have_their_listed_classes`

### Requirement: Edge lists the sites capability to the owner

Platform SHALL list the client capability `sites.manage` (`Capability::SitesManage`) with the route
`/v1/sites` to any signed-in caller, as it lists `notes.vaults`, when the sites route is configured
and the database is reachable, and SHALL NOT list it otherwise. The management routes still need the
owner grant. It is a capability of the
web client, not a site capability: the web client shows its sites section only when it is listed,
and the guards of the site route classes do not read it.

#### Scenario: The sites route is not configured

- **WHEN** a signed-in caller reads the capabilities of a Platform whose route table has no sites route
- **THEN** `sites.manage` is not listed, and it is listed with the route `/v1/sites` once the route
  is configured and the database is reachable, verified by
  `crates/public-api/tests/capabilities.rs::sites_manage_follows_the_sites_route` in
  `ratatoskr-platform`

### Requirement: A management route needs the primary owner session

A `management` route SHALL be served only to a primary Platform session whose principal holds the live
`platform.owner` grant, and SHALL NOT depend on any site capability. Any other caller SHALL get the
stable forbidden or unauthenticated error, and the request SHALL NOT reach the sites service.

#### Scenario: A session without the owner grant manages a site

- **WHEN** a primary session whose principal lacks `platform.owner` calls
  `PUT /v1/sites/{site}/manifest`
- **THEN** Edge answers with the stable forbidden error and the stub sites service receives no
  request, verified by `site_route_classes.rs::management_route_needs_live_owner_grant`

### Requirement: The release class has two guards

A route of the class `release`, which in this change is only `POST /v1/sites/{site}/releases`, SHALL
be accepted from a primary session with the live `platform.owner` grant, or from a `site_owner`
session of the same site whose effective set holds `notes.edit`. Every other caller SHALL be refused
before a command is written. This change issues no `site_owner` session, so only the first guard can
pass in this change.

#### Scenario: An anonymous build request

- **WHEN** a request with no credential calls `POST /v1/sites/{site}/releases`
- **THEN** Edge refuses it and its outbox holds no `cmd.sites.release.build_requested.v1`, verified by
  `crates/public-api/tests/sites_build_command.rs::anonymous_build_request_writes_no_command` in
  `ratatoskr-platform`

#### Scenario: The owner requests a build

- **WHEN** a primary session with `platform.owner` calls `POST /v1/sites/{site}/releases`
- **THEN** Edge writes one outbox row of type `cmd.sites.release.build_requested.v1`, verified by
  `sites_build_command.rs::owner_build_request_publishes_one_command`

### Requirement: The sites service accepts an anonymous claim only on content routes

The sites service SHALL refuse a request that carries Edge's anonymous claim on every route that is
not under `/v1/sites/{site}/content/`, and SHALL return no data for it.

#### Scenario: An anonymous claim on a management route

- **WHEN** a request with an anonymous claim reaches the sites service on
  `GET /v1/sites/{site}/releases`
- **THEN** the sites service refuses it with the stable unauthenticated error and returns no release
  data, verified by
  `services/sites/tests/route_classes.rs::anonymous_claim_is_refused_outside_content` in
  `ratatoskr-sites`
