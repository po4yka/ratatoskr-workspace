## ADDED Requirements

### Requirement: An Instagram fact is digested and timed by what the post says

The Instagram service SHALL compute the content digest of a social snapshot from what the snapshot states: SHA-256 over the canonical JSON of the domain `instagram.snapshot-content`, the canonical permalink, the shortcode, the caption (or null), the upstream availability (`available`, `deleted` or `unavailable`) and the snapshot's media, built by one function that the snapshot builder calls, with no constant digest remaining. A `social.source.updated.v1` snapshot SHALL carry as `captured_at` the instant the current revision was resolved, never earlier than the capture's own time; a `social.source.captured.v1` keeps the capture time. A completion SHALL be linked to a capture only when its digest equals the digest of the capture's current snapshot. An update whose caption changed, or that records a post deleted upstream, SHALL therefore carry a digest and an `observed_at` different from the first fact's, so Knowledge analyses it.

#### Scenario: The caption changes

- **WHEN** a re-resolution changes a post's caption
- **THEN** the updated fact's digest differs from the captured fact's and its `captured_at` is later, and Knowledge makes a second analysis revision and moves the head, verified by the Instagram tests against real PostgreSQL and the Knowledge ingest tests; the Meta resolution that produces such an update is not reachable in the native smoke, which has no credentials

#### Scenario: A completion for the first digest after the update

- **WHEN** a completion for the first digest arrives after the update
- **THEN** it does not link, and a completion for the new digest does
