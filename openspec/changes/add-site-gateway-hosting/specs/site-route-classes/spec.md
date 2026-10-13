# Spec Delta

This delta requires `add-site-publications` (SITE-025) to be archived first.

## MODIFIED Requirements

### Requirement: Every site route has exactly one class

Every route under `/v1/sites/{site}/` SHALL have exactly one class (`management`, `site-origin`,
`sign-in`, `release` or `deploy`) in Edge's route table, and Edge SHALL fail to start when one has
none. A later change that needs another class adds it to this requirement.

#### Scenario: A route without a class stops Edge

- **WHEN** Edge's route table holds a route under `/v1/sites/{site}/` with no class
- **THEN** Edge refuses to start and names the route, verified by
  `crates/http/tests/site_route_classes.rs::unclassified_site_route_fails_start_up` in
  `ratatoskr-platform`

## ADDED Requirements

### Requirement: The deploy routes have the deploy class

`POST /v1/sites/{site}/deploys` and `POST /v1/sites/{site}/deploys/{commit}/activate` SHALL have the class `deploy` in Edge's route table, and SHALL NOT have the class `management`.

#### Scenario: The deploy routes are not management routes

- **WHEN** `crates/http/tests/site_route_classes.rs::deploy_routes_have_the_deploy_class` reads the rows for `POST .../deploys` and `POST .../deploys/{commit}/activate`
- **THEN** both have the class `deploy`, and neither has the class `management`

### Requirement: A deploy route accepts the owner or the site's deployer device

A `deploy` route SHALL be served only to a primary Platform session whose principal holds the live `platform.owner` grant, or to a registered device of kind `site_deployer` that was paired for the same site. Any other caller SHALL get the stable forbidden or unauthenticated error, and the request SHALL NOT reach the sites service.

#### Scenario: A session without the owner grant deploys

- **WHEN** `crates/public-api/tests/sites_deploy_routes.rs::a_deploy_without_the_owner_grant_never_reaches_the_sites_service` posts a bundle with a primary session whose principal lacks `platform.owner`
- **THEN** Edge answers with the stable forbidden error and the stub sites service receives no request

#### Scenario: A deployer device of another site

- **WHEN** `crates/public-api/tests/sites_deploy_routes.rs::a_deployer_device_cannot_deploy_another_site` posts a bundle to site `b` with the session of a `site_deployer` device paired for site `a`
- **THEN** Edge answers with `edge.capability_not_granted` and the stub sites service receives no request

#### Scenario: A deployer device of the site

- **WHEN** `crates/public-api/tests/sites_deploy_routes.rs::a_deployer_device_deploys_its_site` posts a bundle to site `a` with the session of a `site_deployer` device paired for site `a`
- **THEN** the stub sites service receives the upload with minted claims that name the device kind and the site

#### Scenario: A deployer device on a management route

- **WHEN** `crates/public-api/tests/sites_deploy_routes.rs::a_deployer_device_reaches_no_other_route` calls `PUT /v1/sites/a/manifest` and `GET /v1/notes/connections` with the session of a `site_deployer` device paired for site `a`
- **THEN** Edge refuses both, because a management route needs the primary owner session, and no downstream receives a request
