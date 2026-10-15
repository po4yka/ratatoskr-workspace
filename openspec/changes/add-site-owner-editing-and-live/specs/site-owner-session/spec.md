# Spec Delta

## Purpose

Defines how the owner of a site gets a session that is valid only for that site, how the site
presents it, and how the owner sees and ends it.

## ADDED Requirements

### Requirement: A site sign-in code is single-use, short-lived and bound to one site

`POST /v1/sites/{site}/sign-in-codes` is a management route. Only a live browser session that no
paired device opened may approve a sign-in: Platform SHALL issue a site sign-in code only to such a
session that holds `platform.owner`, and only for a site that serves under an approved manifest
(SITE-025 `site-manifest`). When the code is redeemed, Platform SHALL check again that the session
that approved it is live and holds `platform.owner`. The code SHALL be bound to the site id, the owner, a
PKCE S256 challenge, the return path and the approved hostname. It SHALL expire 60 seconds after
issue, SHALL be redeemable once, and Platform SHALL store only its digest.

#### Scenario: The owner signs in to a site

- **WHEN** the owner's primary session requests a sign-in code for an approved site with a challenge, and the site posts that code with the matching verifier to `/v1/sites/{site}/sessions` within 60 seconds
- **THEN** Platform creates one session of kind `site_owner` with audience `site:<site id>` and the response sets the cookie `__Host-ratatoskr-site` with `HttpOnly`, `Secure`, `SameSite=Strict`, `Path=/` and no `Domain` attribute
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_sessions.rs::redeem_sets_host_only_strict_cookie`

#### Scenario: The code is stored only as a digest

- **WHEN** a sign-in code is issued and the identity tables are then searched for its bytes
- **THEN** no row holds the code, and one row holds its SHA-256 digest
- **Test:** `ratatoskr-platform` `crates/identity/tests/site_sign_in.rs::only_the_digest_is_stored`

#### Scenario: A code expires

- **WHEN** a live code is posted with the matching verifier 61 seconds after issue
- **THEN** Platform returns the unauthenticated error and creates no session
- **Test:** `ratatoskr-platform` `crates/identity/tests/site_sign_in.rs::code_expires_after_sixty_seconds`

#### Scenario: A device session asks for a code

- **WHEN** a session opened by a paired device requests a site sign-in code
- **THEN** Platform refuses the request, because only a live browser session that no paired device opened may approve a sign-in
- **Test:** `ratatoskr-platform` `crates/identity/tests/site_sign_in.rs::device_session_cannot_issue_code`

#### Scenario: The site is not approved

- **WHEN** the owner's primary session requests a sign-in code for a site whose approval is withdrawn
- **THEN** Platform returns 404 `sites.site_not_found` and issues no code
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_sessions.rs::unapproved_site_issues_no_code`

### Requirement: Redeeming a code needs the code and its verifier only

`POST /v1/sites/{site}/sessions` is the only sign-in route. It SHALL accept an anonymous request and
SHALL authenticate it only by the code and the PKCE verifier. Every invalid code (unknown, expired,
already redeemed, bound to another site, or presented with a verifier that does not match) SHALL
produce the same unauthenticated error and create no session.

#### Scenario: A redeemed code is presented again

- **WHEN** a code that already opened a session is posted a second time with the correct verifier
- **THEN** Platform returns the unauthenticated error and the number of `site_owner` sessions does not change
- **Test:** `ratatoskr-platform` `crates/identity/tests/site_sign_in.rs::code_is_single_use`

#### Scenario: A code is presented without the matching verifier

- **WHEN** a live code is posted with a verifier whose S256 digest is not the bound challenge
- **THEN** Platform returns the same unauthenticated error as for an unknown code and creates no session
- **Test:** `ratatoskr-platform` `crates/identity/tests/site_sign_in.rs::verifier_mismatch_is_indistinguishable_from_unknown`

#### Scenario: A code is presented at another site

- **WHEN** a live code issued for site A is posted with its verifier to `/v1/sites/B/sessions`
- **THEN** Platform returns the same unauthenticated error and creates no session
- **Test:** `ratatoskr-platform` `crates/identity/tests/site_sign_in.rs::code_for_another_site_is_indistinguishable_from_unknown`

### Requirement: An owner session authenticates only on its own site's routes

A session of kind `site_owner` SHALL authenticate only on a site-origin route or the release route
whose `{site}` equals the site id in its audience, and only when presented in the cookie
`__Host-ratatoskr-site`. Platform SHALL NOT read that cookie on any other route. A `site_owner`
session presented anywhere else SHALL be treated as no credential.

#### Scenario: The owner session calls another site

- **WHEN** a `site_owner` session of site A calls `GET /v1/sites/B/drafts/pages/home`
- **THEN** Platform answers as it answers an anonymous caller, and returns no draft content of site B
- **Test:** `ratatoskr-platform` `crates/identity/tests/site_owner_session.rs::other_site_is_anonymous`

#### Scenario: The owner session calls a general route

- **WHEN** a `site_owner` session calls `GET /v1/library/search` or `GET /v1/operations`
- **THEN** Platform returns the unauthenticated error
- **Test:** `ratatoskr-platform` `crates/identity/tests/site_owner_session.rs::general_route_is_unauthenticated`

#### Scenario: The owner session calls a management route of its own site

- **WHEN** a `site_owner` session of site A calls `POST /v1/sites/A/sign-in-codes`
- **THEN** Platform returns the unauthenticated error and issues no code
- **Test:** `ratatoskr-platform` `crates/identity/tests/site_owner_session.rs::management_route_is_unauthenticated`

#### Scenario: The owner session is sent as a bearer header

- **WHEN** the credential of a `site_owner` session is sent in an `Authorization` header to its own site route
- **THEN** Platform returns the unauthenticated error
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_sessions.rs::bearer_header_is_refused`

### Requirement: An owner session has a bounded life and no refresh

A `site_owner` session SHALL end 12 hours after issue, or 1 hour after its last use, whichever comes
first. It SHALL have no refresh credential. A new sign-in SHALL create a new session and SHALL NOT
extend an existing one.

#### Scenario: An idle session ends

- **WHEN** a `site_owner` session is not used for 61 minutes and is then presented on its own site route
- **THEN** Platform returns the unauthenticated error
- **Test:** `ratatoskr-platform` `crates/identity/tests/site_owner_session.rs::idle_after_sixty_one_minutes_fails`

#### Scenario: A session reaches its absolute lifetime

- **WHEN** a `site_owner` session that was used every 10 minutes is presented 12 hours and 1 minute after issue
- **THEN** Platform returns the unauthenticated error
- **Test:** `ratatoskr-platform` `crates/identity/tests/site_owner_session.rs::absolute_lifetime_twelve_hours_fails`

#### Scenario: A second sign-in does not extend the first

- **WHEN** the owner signs in twice to site A, 11 hours apart, and presents the first session 12 hours and 1 minute after its issue
- **THEN** the first session fails and the second session authenticates
- **Test:** `ratatoskr-platform` `crates/identity/tests/site_owner_session.rs::new_sign_in_does_not_extend_old_session`

### Requirement: Unsafe requests from a site carry proof of the site origin

On a site-origin route and on the release route, Platform SHALL accept a method other than `GET`,
`HEAD` and `OPTIONS` from a `site_owner` session only when the request carries the header
`X-Ratatoskr-Site-Request: 1` and an `Origin` header equal to `https://` followed by the site's
approved hostname. Platform SHALL answer no CORS preflight on routes under `/v1/sites/{site}/`.

#### Scenario: A cross-site form posts an edit

- **WHEN** a request to `POST /v1/sites/{site}/edits` carries a valid owner cookie but no `X-Ratatoskr-Site-Request` header
- **THEN** Platform returns the forbidden error and publishes no command
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_sessions.rs::unsafe_method_without_site_header_is_forbidden`

#### Scenario: The origin is another host

- **WHEN** a request to `POST /v1/sites/{site}/edits` carries the header and the cookie, and `Origin` names a hostname other than the approved one
- **THEN** Platform returns the forbidden error and publishes no command
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_sessions.rs::foreign_origin_is_forbidden`

#### Scenario: A preflight request

- **WHEN** an `OPTIONS` request with `Access-Control-Request-Method: POST` reaches `/v1/sites/{site}/edits`
- **THEN** the response carries no `Access-Control-Allow-Origin` header
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_sessions.rs::no_cors_preflight_on_site_routes`

### Requirement: The owner sees and ends site sessions

The owner's session list SHALL show each live `site_owner` session with its site id, approved
hostname, issue time and last use, and no credential data. The owner SHALL be able to revoke one
such session, or every session of one site. When the approval of a site is withdrawn through the
SITE-025 approval route, Platform SHALL revoke every `site_owner` session of that site in the same
transaction.

#### Scenario: The session list

- **WHEN** the owner lists sessions while one `site_owner` session of site A is live
- **THEN** the list holds that session with site id, hostname, issue time and last use, and holds no token, digest or cookie value
- **Test:** `ratatoskr-platform` `crates/public-api/tests/sessions.rs::site_owner_sessions_are_listed_without_credentials`

#### Scenario: The owner revokes all sessions of a site

- **WHEN** the owner revokes all sessions of site A while two `site_owner` sessions of site A and one of site B are live
- **THEN** both sessions of site A fail authentication at once, and the session of site B still authenticates
- **Test:** `ratatoskr-platform` `crates/public-api/tests/sessions.rs::revoke_all_for_one_site_spares_other_sites`

#### Scenario: The approval is withdrawn

- **WHEN** the owner calls `DELETE /v1/sites/A/manifest/approval` while a `site_owner` session of site A is live
- **THEN** the next request of that session fails authentication
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_sessions.rs::withdrawn_approval_revokes_site_sessions`
