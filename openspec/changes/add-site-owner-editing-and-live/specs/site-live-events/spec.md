# Spec Delta

## Purpose

Defines what the site event stream sends, to which caller, in which shape, and how a client resumes
it after a break.

## ADDED Requirements

### Requirement: The stream sends each event type only to its audience

`GET /v1/sites/{site}/events` SHALL be a server-sent event stream whose events conform to
`sites/site-event.v1`. It SHALL send `release.published` to any caller with `live.release`. It SHALL
send `draft.changed`, `edit.completed` and `edit.conflicted` only to a `site_owner` session of that
site.

#### Scenario: An anonymous page and the owner watch the same site

- **WHEN** an anonymous connection and a `site_owner` connection are open on site S, and a note in S's publication changes and is then released
- **THEN** the owner connection receives `draft.changed` and then `release.published`, and the anonymous connection receives only `release.published`
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_events.rs::anonymous_sees_only_release_published`

### Requirement: A public event carries no page list and no private content

The `release.published` payload SHALL hold only the release id and the publication time. It SHALL
NOT hold a list of pages, slugs or titles, a source reference, a vault path or draft content. A site
that receives it fetches the navigation again.

#### Scenario: The release event shape

- **WHEN** a release is published and an anonymous connection receives `release.published`
- **THEN** the payload holds exactly the release id and the publication time
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_events.rs::release_payload_holds_only_id_and_time`

#### Scenario: A page list is refused by the contract

- **WHEN** a `release.published` fixture that carries a list of changed slugs is validated against `sites/site-event.v1`
- **THEN** validation fails
- **Test:** `ratatoskr-contracts` `crates/sites-contracts/tests/site_event.rs::release_published_refuses_page_list`

### Requirement: A client resumes from the last event it received

Each event SHALL carry an id that increases within a site. A request with `Last-Event-ID` inside the
retained window SHALL first receive, in order, every event after that id that the caller may see, and
then follow new events. A request with an id outside the retained window, or an unknown id, SHALL
receive a `resync` event first. The retained window SHALL hold at least the last 256 events or the
last 24 hours of a site, whichever is smaller.

#### Scenario: A short break loses nothing

- **WHEN** an owner connection receives event id N, drops, three events follow, and the client reconnects with `Last-Event-ID: N`
- **THEN** the new connection receives those three events in order, without a `resync` event
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_events.rs::resume_inside_window_replays_in_order`

#### Scenario: A long break asks for a refetch

- **WHEN** a client reconnects with an id that is older than the retained window
- **THEN** the first event on the new connection is `resync`
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_events.rs::resume_outside_window_starts_with_resync`

#### Scenario: Edge restarted

- **WHEN** Edge restarts and a client reconnects with an id that it received before the restart
- **THEN** the first event on the new connection is `resync`
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_events.rs::restart_starts_with_resync`

### Requirement: The stream stays open and bounded

The stream SHALL send a keep-alive comment at least every 15 seconds. Platform SHALL limit concurrent
anonymous connections to a configured bound per client (default 4) and a configured bound per site
(default 64). The client is the value of `X-Ratatoskr-Client-IP` that the sites gateway sets. A
connection above either bound SHALL get the stable retryable unavailable error. Connections of the
site's `site_owner` sessions SHALL NOT count against either bound.

#### Scenario: An idle stream

- **WHEN** a connection is open and no event occurs for 40 seconds
- **THEN** the client receives at least two keep-alive comments
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_events.rs::keep_alive_every_fifteen_seconds`

#### Scenario: One client opens too many streams

- **WHEN** the per-client bound is 4, one client already holds 4 anonymous connections on site S, and the same client opens a fifth while another client opens its first
- **THEN** the fifth connection gets the retryable unavailable error and the other client's connection opens
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_events.rs::per_client_bound_refuses_fifth_anonymous_stream`

#### Scenario: The per-site bound is reached

- **WHEN** the per-site bound is 2, two anonymous connections from two clients are open on site S, and a third anonymous connection and one owner connection arrive
- **THEN** the third anonymous connection gets the retryable unavailable error and the owner connection opens
- **Test:** `ratatoskr-platform` `crates/public-api/tests/site_events.rs::anonymous_bound_spares_owner`
