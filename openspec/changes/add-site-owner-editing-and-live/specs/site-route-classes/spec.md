# Spec Delta

This delta requires `add-site-gateway-hosting` (SITE-026) to be archived first.

## ADDED Requirements

### Requirement: The sign-in routes have the management and sign-in classes

`POST /v1/sites/{site}/sign-in-codes` SHALL have the class `management`, and
`POST /v1/sites/{site}/sessions` SHALL have the class `sign-in`: it is served to an anonymous caller,
authenticated by the PKCE code and verifier only. No other route SHALL have the class `sign-in`.

#### Scenario: The sign-in rows have their classes

- **WHEN** `crates/http/tests/site_route_classes.rs::sign_in_routes_have_their_classes` reads the rows for `POST .../sign-in-codes` and `POST .../sessions`
- **THEN** the first has the class `management`, the second has the class `sign-in`, and no other row has the class `sign-in`

#### Scenario: A site session on a management route

- **WHEN** a `site_owner` session calls `PUT /v1/sites/{site}/manifest` or `POST /v1/sites/{site}/sign-in-codes`
- **THEN** Edge returns the unauthenticated error and the stub sites service receives no request, verified by `crates/http/tests/site_route_classes.rs::management_route_refuses_site_owner_session` in `ratatoskr-platform`

### Requirement: The owner routes on the site origin have the site-origin class

These routes SHALL have the class `site-origin`: `GET .../events`; `GET .../drafts/pages/{slug}`,
`GET .../drafts/sources/{source_ref}` and `POST .../drafts/sources/{source_ref}/blobs`;
`POST .../edits`; `GET .../conflicts/{conflict_id}`; `GET .../library`; and
`GET .../knowledge/search`.

#### Scenario: The site-origin rows have their class

- **WHEN** `crates/http/tests/site_route_classes.rs::site_owner_origin_routes_have_the_site_origin_class` reads the rows of the routes above
- **THEN** each has the class `site-origin`, and the draft upload row also has the budget class `transfer`

## MODIFIED Requirements

### Requirement: The release class has two guards

A route of the class `release`, which in this change is only `POST /v1/sites/{site}/releases`, SHALL
be accepted from a primary session with the live `platform.owner` grant, or from a `site_owner`
session of the same site whose effective set holds `notes.edit`. Every other caller SHALL be refused
before a command is written. A `site_owner` session whose effective set lacks `notes.edit` SHALL get
403 `edge.capability_not_granted`.

#### Scenario: An anonymous build request

- **WHEN** a request with no credential calls `POST /v1/sites/{site}/releases`
- **THEN** Edge refuses it and its outbox holds no `cmd.sites.release.build_requested.v1`, verified by
  `crates/public-api/tests/sites_build_command.rs::anonymous_build_request_writes_no_command` in
  `ratatoskr-platform`

#### Scenario: The owner requests a build

- **WHEN** a primary session with `platform.owner` calls `POST /v1/sites/{site}/releases`
- **THEN** Edge writes one outbox row of type `cmd.sites.release.build_requested.v1`, verified by
  `sites_build_command.rs::owner_build_request_publishes_one_command`

#### Scenario: A site session with notes.edit requests a build

- **WHEN** a `site_owner` session of the site, whose effective set holds `notes.edit`, calls `POST /v1/sites/{site}/releases` with the site-request header and the approved `Origin`
- **THEN** Edge writes one outbox row of type `cmd.sites.release.build_requested.v1`, verified by
  `sites_build_command.rs::site_owner_with_notes_edit_publishes_one_command`

#### Scenario: A site session without notes.edit requests a build

- **WHEN** a `site_owner` session whose effective set lacks `notes.edit` calls `POST /v1/sites/{site}/releases`
- **THEN** Edge answers 403 `edge.capability_not_granted` and its outbox holds no
  `cmd.sites.release.build_requested.v1`, verified by
  `sites_build_command.rs::site_owner_without_notes_edit_writes_no_command`

#### Scenario: A site session of another site requests a build

- **WHEN** a `site_owner` session of site `a` calls `POST /v1/sites/b/releases`
- **THEN** Edge refuses it as a request with no credential and writes no command, verified by
  `sites_build_command.rs::site_owner_of_another_site_writes_no_command`

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

#### Scenario: An anonymous claim on a draft route

- **WHEN** a request with an anonymous claim reaches the sites service on
  `GET /v1/sites/{site}/drafts/sources/{source_ref}`
- **THEN** the sites service refuses it with the stable unauthenticated error and returns no source,
  verified by `services/sites/tests/route_classes.rs::anonymous_claim_is_refused_on_draft_routes` in
  `ratatoskr-sites`
