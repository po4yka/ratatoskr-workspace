# Spec Delta

## Purpose

Defines the anonymous Content Delivery API through which a site reads the current release of its
publications, the `public` Edge route class that carries it, the cache and rate rules that keep the
single host able to serve public traffic, search over the current release, and the client that the
site SDK generates from the contract.

## ADDED Requirements

### Requirement: The Content Delivery API has four read routes

Edge SHALL serve, in the route class `public`, exactly these routes for a site id `{site}`:
`/v1/sites/{site}/content/release` (the current `sites/release.v1` document),
`/v1/sites/{site}/content/pages/{slug}` (one `sites/page.v1`),
`/v1/sites/{site}/content/assets/{sha256}` (the bytes of one asset with its media type) and
`/v1/sites/{site}/content/search`. Each SHALL accept `GET` and `HEAD`.

#### Scenario: The four routes answer for a site with a release

- **WHEN** a client without a credential calls each of the four routes of an approved site that
  has a current release
- **THEN** each answers 200 with a body that validates against its contract type, verified by
  `services/sites/tests/delivery.rs::the_four_routes_answer_for_an_approved_site` in
  `ratatoskr-sites`

### Requirement: Other methods are refused at Edge

A request in the route class `public` with a method other than `GET` or `HEAD` SHALL be refused by
Edge with HTTP 405 and the contract error envelope, and SHALL NOT reach the sites service.

#### Scenario: A write method is refused at Edge

- **WHEN** a client sends `POST /v1/sites/{site}/content/pages/home`
- **THEN** Edge answers 405 with the contract envelope and the sites service receives no request,
  verified by `crates/http/tests/public_route_class.rs::write_method_is_refused_before_proxy` in
  `ratatoskr-platform`

### Requirement: Only the current release is served

A page or an asset that is not in the current release of the site SHALL be answered with HTTP 404
and the stable code `sites.page_not_found` or `sites.asset_not_found`, also when an earlier release
of the site held it.

#### Scenario: A page of an earlier release is gone

- **WHEN** a page existed in the previous release and the current release no longer holds it
- **THEN** `GET /v1/sites/{site}/content/pages/{slug}` answers 404 with `sites.page_not_found`,
  verified by `delivery.rs::page_of_earlier_release_is_not_found`

### Requirement: The public route class is anonymous and identical for every caller

A request in the route class `public` SHALL NOT need a credential. Edge SHALL NOT read a cookie or
an `Authorization` header on it, SHALL forward neither, and SHALL mint only an anonymous claim with
a correlation id. A response SHALL NOT carry `Set-Cookie`, and SHALL be the same for a request with
no credential, an invalid credential and a valid owner credential.

#### Scenario: An owner credential does not change the answer

- **WHEN** the same page is requested once without a credential and once with a valid owner
  session
- **THEN** both responses have the same status, headers (apart from date and correlation id) and
  body, and neither sets a cookie, verified by
  `public_route_class.rs::credential_does_not_change_a_public_response`

### Requirement: Every kind of absence takes one code path

The delivery routes SHALL answer every absence that `site-manifest` defines (a site id that does not
exist, a site with no approval or a withdrawn approval, a public capability outside the effective
set) with the same headers and body, through one code path that reads no database row, so that
neither the answer nor its timing tells the cases apart.

#### Scenario: Four kinds of absence look the same

- **WHEN** a client requests the release route of a missing site, an unapproved site and a
  withdrawn site, and the search route of a site that does not request `search.publication`
- **THEN** the four responses have the same status, the same code and the same body, verified by
  `delivery.rs::every_kind_of_absence_is_the_same_answer`

### Requirement: Public content has a bounded cache lifetime

The release, page and search routes SHALL answer with `Cache-Control: public` and a `max-age` of at
most 60 seconds. The asset route SHALL answer with `Cache-Control: public` and a `max-age` of at
most 3600 seconds. A withdrawal SHALL therefore stop all public content within 3600 seconds, also in
a shared cache, and the owner documentation SHALL say so.

#### Scenario: Cache lifetimes stay inside the bound

- **WHEN** the contract test reads the `Cache-Control` header of each of the four routes
- **THEN** release, page and search answers have `max-age` of at most 60 and asset answers of at
  most 3600, verified by `delivery.rs::cache_lifetimes_are_bounded`

### Requirement: Public content supports conditional requests

The release, page and search routes SHALL carry an `ETag` that changes when the current release
changes, and the asset route SHALL carry the asset digest as its `ETag`. Each route SHALL answer a
matching `If-None-Match` with HTTP 304 and no body.

#### Scenario: A conditional request after no change

- **WHEN** a client repeats a page request with the `ETag` of its first answer and no release was
  published in between
- **THEN** the answer is 304 with no body, verified by `delivery.rs::unchanged_page_answers_304`

### Requirement: Public requests are rate-limited before any work

Edge SHALL apply, before it proxies a `public` request, a token bucket per client keyed on the
`X-Ratatoskr-Client-IP` header and a total budget per site. When and from which peer Edge trusts
that header is owned by the `site-gateway` capability of SITE-026 (`add-site-gateway-hosting`). A request over either limit SHALL be answered with
HTTP 429, the contract fault and `Retry-After`, and SHALL NOT reach the sites service.

#### Scenario: A burst over the per-client limit

- **WHEN** requests with one `X-Ratatoskr-Client-IP` value send more requests to one site than its
  bucket allows
- **THEN** the excess requests are answered 429 with `Retry-After` and the stub sites service counts
  only the admitted requests, verified by
  `public_route_class.rs::per_client_limit_is_enforced_before_proxy`

### Requirement: Search covers only the current release

Search SHALL return results only from the pages of the current release: slug, title and a snippet
of at most 300 Unicode scalar values, in descending relevance with a deterministic tie-break. Its
index SHALL be built from the release itself and SHALL NOT read Knowledge or any note outside the
release.

#### Scenario: A private note never matches

- **WHEN** a visitor searches a canary string that only an unselected note of the publication holds
- **THEN** the result list is empty and `has_more` is false, verified by
  `services/sites/tests/search.rs::search_never_returns_unselected_content`

#### Scenario: A search after a new release

- **WHEN** a page is removed by a new release and a visitor searches a word that only that page held
- **THEN** the result list is empty, verified by `search.rs::search_follows_the_current_release`

### Requirement: Search parameters are bounded

Search SHALL accept `q` of 1 to 256 Unicode scalar values, `limit` from 1 to 50 and a non-negative
`offset`. Any other value SHALL fail as an invalid request before a search runs.

#### Scenario: An over-long query is refused

- **WHEN** a visitor searches with a `q` of 257 Unicode scalar values
- **THEN** the answer is the stable invalid-request error and no search runs, verified by
  `search.rs::over_long_query_is_refused_before_search`

### Requirement: The site SDK is generated from the contract

`@ratatoskr/site-sdk` SHALL expose a typed client for every route of the Content Delivery API, with
types generated from `sites/release.v1`, `sites/page.v1` and the published API description. Its
check SHALL fail when the committed generated code differs from a fresh generation against the
pinned contracts.

#### Scenario: The generated client drifts from the contract

- **WHEN** a field is added to `sites/page.v1` and the SDK is not regenerated
- **THEN** the SDK's `generated-drift` check fails and names the changed file, verified by
  `scripts/check-generated.test.ts` in `ratatoskr-site-sdk`

### Requirement: The starter template works without change

The starter template in `ratatoskr-site-sdk` SHALL build with no code change and render a release
that the delivery API serves.

#### Scenario: The starter template reads a fixture release

- **WHEN** the starter template is built and run against a stub delivery API that serves
  `fixtures/release/minimal/`
- **THEN** the home page shows the fixture page titles, verified by
  `template/tests/fixture-release.test.ts` in `ratatoskr-site-sdk`
