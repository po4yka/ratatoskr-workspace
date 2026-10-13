# Spec Delta

## Purpose

Defines how the sites gateway maps a request hostname to one approved site, what it serves from that
site's current deploy, what it forwards to Edge, and which headers and limits it applies.

## ADDED Requirements

### Requirement: A hostname selects exactly one approved site

The gateway SHALL serve a request only when its `Host` header, compared case-insensitively and without a port, equals a hostname that exactly one approved site names and that site has a current deploy. Any other request SHALL receive a 404 contract envelope with the code `sites.gateway.unknown_host`.

#### Scenario: A hostname that no site names

- **WHEN** `services/sites-gateway/tests/host_routing.rs::an_unknown_host_gets_404_and_no_site_bytes` sends a request with `Host: unknown.example` to a gateway that serves two sites
- **THEN** the response is 404 with `sites.gateway.unknown_host`, and its body contains no byte of either site's bundle

#### Scenario: A site is approved but has no deploy

- **WHEN** `services/sites-gateway/tests/host_routing.rs::an_approved_site_without_a_deploy_gets_no_deploy` requests the hostname of an approved site that has no current deploy
- **THEN** the response is 404 with `sites.gateway.no_deploy`

### Requirement: The gateway projection follows every approval change

The sites service SHALL rewrite the gateway projection of a site when it consumes `evt.platform.site_approval.changed.v1` through the durable `ratatoskr_sites_approvals` (SITE-025), for an approval, a withdrawal through `DELETE /v1/sites/{site}/manifest/approval` (SITE-025, owned by Edge) and a hostname change. The gateway SHALL apply a rewritten projection within five seconds.

#### Scenario: A withdrawal reaches the projection

- **WHEN** `services/sites/tests/gateway_projection.rs::withdrawal_rewrites_projection_within_five_seconds` delivers `evt.platform.site_approval.changed.v1` with state `withdrawn` for site `a`
- **THEN** within five seconds `site.json` of `a` no longer marks it approved and lists no hostname

#### Scenario: A hostname change reaches the projection

- **WHEN** `services/sites/tests/gateway_projection.rs::hostname_change_rewrites_projection` delivers an `approved` event for site `a` with the hostname `new.example` in place of `old.example`
- **THEN** `site.json` of `a` lists `new.example` and not `old.example`

#### Scenario: The gateway drops a withdrawn site

- **WHEN** `services/sites-gateway/tests/host_routing.rs::a_withdrawn_site_is_dropped_within_five_seconds` rewrites `site.json` of site `a` as withdrawn and then requests its hostname every 100 ms
- **THEN** every request later than five seconds after the rewrite receives 404 with `sites.gateway.unknown_host`

### Requirement: Static paths serve the current deploy only

For a selected site, the gateway SHALL answer `GET` and `HEAD` on a path with the file of that path from the current deploy, with `ETag` set to the file's SHA-256. When the manifest enables the entry fallback, a path with no file outside `/.ratatoskr/` SHALL serve the entry document. Any other method SHALL receive 405.

#### Scenario: A file of another site is requested

- **WHEN** `services/sites-gateway/tests/static_serving.rs::the_host_selects_the_file_of_its_own_site` requests `app.js` with the hostname of site `a`, and both `a` and `b` hold an `app.js`
- **THEN** the body equals the file of `a`'s current deploy

#### Scenario: A conditional request matches

- **WHEN** `services/sites-gateway/tests/static_serving.rs::a_matching_etag_returns_304` sends `If-None-Match` with the SHA-256 of the current file
- **THEN** the response is 304 with no body

#### Scenario: A path with no file and the fallback on

- **WHEN** `services/sites-gateway/tests/static_serving.rs::the_entry_fallback_serves_the_entry_document` requests `/notes/some-page` for a site whose manifest enables the entry fallback
- **THEN** the response is 200 with the entry document

#### Scenario: A write method on a static path

- **WHEN** `services/sites-gateway/tests/static_serving.rs::a_post_on_a_static_path_returns_405` sends a `POST` for `/index.html`
- **THEN** the response is 405 and the deploy on disk is unchanged

### Requirement: The reserved path for SDK pages is served without fallback

`/.ratatoskr/` is reserved for SDK pages: every bundle built from the SDK template ships `.ratatoskr/sign-in/index.html`. The gateway SHALL serve `/.ratatoskr/*` from the current deploy, resolving a folder path to its `index.html`, with `Cache-Control: no-store`, and SHALL never apply the entry fallback under it.

#### Scenario: The sign-in callback page is requested

- **WHEN** `services/sites-gateway/tests/static_serving.rs::the_sign_in_callback_is_served_with_no_store` requests `/.ratatoskr/sign-in?state=x` with the hostname of site `a`
- **THEN** the response is 200 with the file `.ratatoskr/sign-in/index.html` of `a`'s current deploy and `Cache-Control: no-store`

#### Scenario: An unknown path under the reserved SDK path

- **WHEN** `services/sites-gateway/tests/static_serving.rs::an_unknown_sdk_path_is_404_without_fallback` requests `/.ratatoskr/other` for a site whose manifest enables the entry fallback
- **THEN** the response is 404 and not the entry document

### Requirement: Hashed assets of the previous deploy stay reachable

When a path has no file in the current deploy, the gateway SHALL serve the file of that path from the previous deploy if the previous manifest marks it as content-hashed. It SHALL NOT serve any other file of the previous deploy.

#### Scenario: A client loaded the entry document before a switch

- **WHEN** `services/sites-gateway/tests/static_serving.rs::a_hashed_asset_of_the_previous_deploy_is_served` switches the current deploy from commit `a` to commit `b` and then requests `assets/app.3f9a1c.js`, which only `a` holds and marks as hashed
- **THEN** the response is 200 with the file of `a`

#### Scenario: An unhashed file of the previous deploy

- **WHEN** `services/sites-gateway/tests/static_serving.rs::an_unhashed_file_of_the_previous_deploy_is_not_served` requests `about.html`, which only the previous deploy holds and does not mark as hashed
- **THEN** the response is the entry fallback or 404, and never the previous file

### Requirement: Cache headers follow the manifest

The gateway SHALL send `Cache-Control: public, max-age=31536000, immutable` for a file that the manifest marks as content-hashed, and `Cache-Control: public, max-age=60, must-revalidate` for every other static file outside `/.ratatoskr/`, including the entry document.

#### Scenario: A hashed asset and the entry document

- **WHEN** `services/sites-gateway/tests/headers.rs::hashed_files_are_immutable_and_the_entry_document_is_short_lived` requests `assets/app.3f9a1c.js`, marked as hashed, and then `/`
- **THEN** the first response carries `immutable` and the second carries `max-age=60, must-revalidate`

### Requirement: Static responses carry fixed security headers

Every static response SHALL carry `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `X-Frame-Options: DENY` and a Content Security Policy that allows scripts, styles, images, fonts and connections only from the site's own origin, plus `data:` images, with `object-src 'none'`, `base-uri 'self'` and `frame-ancestors 'none'`.

#### Scenario: Headers on the entry document

- **WHEN** `services/sites-gateway/tests/headers.rs::every_static_response_carries_the_security_headers` requests `/` and `/.ratatoskr/sign-in` of an approved site
- **THEN** each of the four headers is present on both responses with exactly the documented value

### Requirement: The forwarding prefix reaches only the site's own API

A request under `/_r/` SHALL be forwarded to Edge only when its path starts with `/_r/v1/sites/<site id>/` and `<site id>` is the site that the hostname selects. The gateway SHALL remove the `/_r` prefix, and SHALL refuse every other `/_r/` path with 404 and `sites.gateway.route_not_forwarded`.

#### Scenario: A site tries to reach another site's API

- **WHEN** `services/sites-gateway/tests/forwarding.rs::another_sites_api_is_not_forwarded` requests `/_r/v1/sites/b/content/pages` with the hostname of site `a`
- **THEN** the response is 404 with `sites.gateway.route_not_forwarded`, and the stub Edge receives no request

#### Scenario: A site reaches its own content

- **WHEN** `services/sites-gateway/tests/forwarding.rs::the_sites_own_api_is_forwarded_without_the_prefix` requests `/_r/v1/sites/a/content/pages` with the hostname of site `a`
- **THEN** the stub Edge receives `GET /v1/sites/a/content/pages` and the client receives Edge's status, headers and body unchanged

### Requirement: Forwarding adds no identity and buffers nothing

Before it forwards, the gateway SHALL remove every inbound header whose name starts with `x-ratatoskr-`, and SHALL add no identity of its own. It SHALL stream request and response bodies under `/_r/` without buffering them.

#### Scenario: A client forges an identity header

- **WHEN** `services/sites-gateway/tests/forwarding.rs::inbound_ratatoskr_headers_are_removed` requests `/_r/v1/sites/a/content/pages` with `x-ratatoskr-user-id: 1`
- **THEN** the request that the stub Edge receives has no `x-ratatoskr-user-id` header

### Requirement: The gateway sets the client address that Edge rate-limits on

The gateway SHALL remove any inbound `X-Ratatoskr-Client-IP` and SHALL set it to the value of `CF-Connecting-IP` on every forwarded request. It SHALL open its connections to Edge from its configured loopback source address. Edge SHALL use `X-Ratatoskr-Client-IP` only on a connection from that address, and SHALL ignore and remove it on any other connection.

#### Scenario: A client forges its address through the gateway

- **WHEN** `services/sites-gateway/tests/forwarding.rs::client_ip_is_set_from_cf_connecting_ip` sends a forwarded request with `X-Ratatoskr-Client-IP: 1.1.1.1` and `CF-Connecting-IP: 2.2.2.2`
- **THEN** the stub Edge receives exactly one `X-Ratatoskr-Client-IP` header, with the value `2.2.2.2`, on a connection from the configured source address

#### Scenario: Another local peer sends the header to Edge

- **WHEN** `crates/http/tests/client_ip_trust.rs::client_ip_header_is_ignored_from_other_peers` sends `X-Ratatoskr-Client-IP: 3.3.3.3` to Edge from `127.0.0.1`, which is not the configured gateway address
- **THEN** Edge keys its per-client `public` bucket on the peer and not on `3.3.3.3`, and the downstream request carries no `X-Ratatoskr-Client-IP`

#### Scenario: The gateway's header is trusted

- **WHEN** `crates/http/tests/client_ip_trust.rs::client_ip_header_is_used_from_the_gateway_peer` sends `X-Ratatoskr-Client-IP: 4.4.4.4` to Edge from the configured gateway address
- **THEN** Edge keys its per-client `public` bucket on `4.4.4.4`

### Requirement: Server-sent events under the forwarding prefix are flushed at once

For a forwarded response of type `text/event-stream`, the gateway SHALL send each event to the client as soon as Edge sends it, in the same order, without compression and without a read timeout shorter than Edge's keep-alive interval. It SHALL pass `Last-Event-ID` to Edge unchanged.

#### Scenario: An event stream passes through

- **WHEN** `services/sites-gateway/tests/forwarding.rs::server_sent_events_arrive_within_100_ms_without_compression` lets the stub Edge send three server-sent events one second apart on a forwarded stream
- **THEN** the client receives each event within 100 ms of Edge sending it, in the same order, and the response has no `Content-Encoding`

#### Scenario: A client resumes a stream

- **WHEN** `services/sites-gateway/tests/forwarding.rs::last_event_id_reaches_edge_unchanged` opens `/_r/v1/sites/a/events` with `Last-Event-ID: 42`
- **THEN** the request that the stub Edge receives carries `Last-Event-ID: 42`

#### Scenario: A quiet stream stays open

- **WHEN** `services/sites-gateway/tests/forwarding.rs::a_keep_alive_only_stream_stays_open_for_two_minutes` lets the stub Edge send only its keep-alive comment every fifteen seconds for two minutes of paused time
- **THEN** the client connection stays open for the whole period

### Requirement: The gateway limits load before it does work

The gateway SHALL apply a token bucket per client key, where the key is the `CF-Connecting-IP` header and is used for no other purpose. A client over its budget SHALL receive 429 with `Retry-After`. A body on `/_r/` larger than the configured cap SHALL be refused with 413 before it is forwarded.

#### Scenario: One client exceeds its budget

- **WHEN** `services/sites-gateway/tests/limits.rs::a_client_over_its_burst_gets_429_with_retry_after` sends twice the burst size of requests within one second from one client key
- **THEN** the requests over the burst receive 429 with `Retry-After`

#### Scenario: A second client is not affected

- **WHEN** `services/sites-gateway/tests/limits.rs::a_second_client_is_not_affected` sends one request from a second client key while the first key is over its budget
- **THEN** the second client's request is served normally

#### Scenario: An oversized forwarded body

- **WHEN** `services/sites-gateway/tests/limits.rs::an_oversized_forwarded_body_gets_413_without_a_forward` sends a `/_r/` request whose declared body is larger than the cap
- **THEN** the response is 413 and the stub Edge receives no request
