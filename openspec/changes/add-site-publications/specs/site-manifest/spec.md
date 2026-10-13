# Spec Delta

## Purpose

Defines the site manifest that a site repository carries, the closed set of capabilities that a
manifest can ask for, the owner approval that Platform holds, and the one rule that decides which
capabilities, hostname and publications are in force for a site.

## ADDED Requirements

### Requirement: A site manifest has one closed shape

A site manifest SHALL be a TOML file named `ratatoskr-site.toml` that validates against the contract
schema `sites/site-manifest.v1`. It SHALL hold the site id (lower-case ASCII letters, digits and
`-`, 3 to 40 characters), exactly one hostname, one or more publication ids, and a list of requested
capabilities. A manifest with an unknown key, an unknown capability name or a second hostname SHALL
be refused with the class `sites.manifest_invalid`, and the refusal SHALL name the key or the value.

#### Scenario: An unknown capability is refused

- **WHEN** the owner submits a manifest that requests the capability `notes.delete`
- **THEN** the submission fails with `sites.manifest_invalid` naming `notes.delete`, and the active
  manifest does not change, verified by
  `crates/manifest/tests/validate.rs::unknown_capability_is_refused` in `ratatoskr-sites`

#### Scenario: The contract fixtures cover the shape

- **WHEN** the contract fixture test validates every fixture under `fixtures/sites/site-manifest/`
- **THEN** each `valid-*` fixture passes and each `invalid-*` fixture fails on the key or value its
  name states, verified by
  `tools/contractsc/tests/sites_fixtures.rs::site_manifest_fixtures_match_their_names` in
  `ratatoskr-contracts`

### Requirement: The last valid submission is the active manifest

The sites service SHALL store every valid submitted manifest by the SHA-256 digest of its bytes, and
the last valid submission of a site SHALL be its active manifest. Submitting a manifest SHALL NOT
change what the site serves until the rule of the effective set allows it.

#### Scenario: A submission alone grants nothing

- **WHEN** the owner submits a first manifest for a new site and does not approve it
- **THEN** the site has an active manifest and every content route of the site answers 404
  `sites.site_not_found`, verified by
  `services/sites/tests/manifest_projection.rs::submitted_manifest_alone_serves_nothing`

### Requirement: Capabilities are a closed set with a fixed audience

The capability names SHALL be exactly `pages.read`, `assets.read`, `search.publication`,
`live.release`, `draft.read`, `notes.edit`, `library.read` and `knowledge.search`. Only the first
four SHALL be available to an anonymous visitor. The other four SHALL be available only to a
`site_owner` session, which this change does not issue, so they grant nothing in this change.

#### Scenario: An owner-only capability gives an anonymous visitor nothing

- **WHEN** an approved manifest requests `draft.read` and an anonymous request reaches the sites
  service on a route that is not under `content/`
- **THEN** the sites service refuses the anonymous claim and returns no data, verified by
  `services/sites/tests/route_classes.rs::anonymous_claim_is_refused_outside_content`

### Requirement: Platform holds the only site approval

The only store of site approvals SHALL be Platform's `identity.site_approvals`, one row per site,
bound to the approved manifest digest. Edge SHALL serve `POST` (approve) and `DELETE` (withdraw)
`/v1/sites/{site}/manifest/approval` itself, only to a primary session with `platform.owner`. Each
change SHALL publish one `evt.platform.site_approval.changed.v1` (site id, digest, approved
capabilities, hostname, state `approved` or `withdrawn`).

#### Scenario: An approval is stored in Platform and announced once

- **WHEN** the owner approves the active manifest of a site
- **THEN** `identity.site_approvals` holds one row with that digest, and the outbox holds one
  `evt.platform.site_approval.changed.v1` with state `approved`, verified by
  `crates/public-api/tests/site_approvals.rs::approval_is_stored_and_announced` in
  `ratatoskr-platform`

#### Scenario: The sites service holds no approval authority

- **WHEN** a request for `POST /internal/sites/{site}/approval` or any other approval path reaches
  the sites service
- **THEN** it answers as an unknown route, and the sites schema has no table that an approval is
  written to except the read projection, verified by
  `services/sites/tests/manifest_projection.rs::sites_service_has_no_approval_route`

### Requirement: An approval names the active digest

An approval request SHALL name the digest of the manifest it approves. When that digest is not the
digest of the active manifest, the approval SHALL fail with `platform.manifest_digest_stale` and
change nothing.

#### Scenario: A stale digest is refused

- **WHEN** the owner approves a digest and a newer manifest became active before the request
- **THEN** the approval fails with `platform.manifest_digest_stale` and no row changes, verified by
  `crates/public-api/tests/site_approvals.rs::stale_digest_is_refused` in `ratatoskr-platform`

### Requirement: The sites service keeps only a projection of approvals

The sites service SHALL consume `evt.platform.site_approval.changed.v1` through the durable
`ratatoskr_sites_approvals` and SHALL keep a read projection of the last approved digest and state
per site. It SHALL NOT change that projection from any other input.

#### Scenario: A withdrawal reaches the projection

- **WHEN** Platform publishes `evt.platform.site_approval.changed.v1` with state `withdrawn` for an
  approved site
- **THEN** the sites projection marks the site withdrawn and every content route of the site answers
  404 `sites.site_not_found`, verified by
  `services/sites/tests/manifest_projection.rs::withdrawal_event_stops_the_site`

### Requirement: The effective set of a site is approved and active

This requirement is the only definition of a site's effective set. Its capabilities SHALL be those
of the last approved manifest that the active manifest also declares; its publications SHALL be
those that both name; its hostname SHALL be the approved one. An addition takes effect only after an
approval; a removal stops at once. Without an approval, or after a withdrawal, the set SHALL be
empty.

#### Scenario: An added capability waits for approval

- **WHEN** the owner submits a manifest that adds `search.publication` to an approved manifest that
  did not request it
- **THEN** the search route still answers 404 `sites.site_not_found` until the owner approves the
  new digest, and answers 200 after that, verified by
  `services/sites/tests/effective_set.rs::added_capability_waits_for_approval`

#### Scenario: A removed capability stops at once

- **WHEN** the owner submits a manifest that removes `search.publication` from an approved manifest
- **THEN** the search route answers 404 `sites.site_not_found` before any new approval, verified by
  `effective_set.rs::removed_capability_stops_without_approval`

#### Scenario: A new hostname and a new publication wait for approval

- **WHEN** the owner submits a manifest that changes the hostname and adds a publication
- **THEN** the effective hostname stays the approved one and no page of the added publication enters
  a release until the owner approves the new digest, verified by
  `effective_set.rs::new_hostname_and_publication_wait_for_approval`

### Requirement: Absence is one answer

A request for a public capability that is not in the site's effective set, or for any content of a
site that has no approval or a withdrawn approval, SHALL be answered with HTTP 404 and the stable code
`sites.site_not_found`, with the same body as a request for a site id that does not exist.

#### Scenario: An unrequested public capability looks like a missing site

- **WHEN** an approved site does not request `search.publication` and a visitor calls its search route
- **THEN** the answer equals the answer for a site id that does not exist, verified by
  `effective_set.rs::unrequested_public_capability_is_not_found`

### Requirement: A hostname belongs to one approved site

Two approved sites SHALL NOT have the same hostname. An approval that would give a hostname to a
second site SHALL fail with `platform.site_hostname_taken` and SHALL leave both approvals unchanged.

#### Scenario: A second site claims a hostname

- **WHEN** the owner approves a manifest of site `b` that names the hostname of approved site `a`
- **THEN** the approval fails with `platform.site_hostname_taken`, verified by
  `crates/public-api/tests/site_approvals.rs::hostname_is_unique_across_approved_sites` in
  `ratatoskr-platform`
