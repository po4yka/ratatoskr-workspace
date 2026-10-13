## ADDED Requirements

### Requirement: A manifest is minimized by the body retention timer

The digest manifest SHALL be under the same body retention as a post revision. `channel_digests.digest_manifests.canonical_text` SHALL be nullable and the table SHALL carry `minimized_at`; exactly one of the two SHALL be set. `sha256`, `source_count`, `channel_count`, `owner_id`, `run_id` and `created_at` SHALL never change. A table `digest_manifest_sources` SHALL link a manifest to the `(channel_id, provider_message_id)` pairs it holds, written in the transaction that commits the manifest and not written by a replay. The retention sweep SHALL, after minimizing revision bodies, null `canonical_text` and set `minimized_at` for manifests whose run is terminal (`completed`, `partial` or `failed`) and whose run `window_start` is older than the same cutoff (`now` minus `RATATOSKR__RETENTION__BODY_DAYS`), oldest first, in the same batch size, and SHALL count them in `channel_digests_manifests_minimized_total` on the operator listener. The log line SHALL stay free of content.

#### Scenario: A terminal run is older than the cutoff

- **WHEN** the sweep meets a manifest whose terminal run started its window before the cutoff
- **THEN** its text is null and `minimized_at` is set, its digest and counts are unchanged, a manifest of a younger run or of a non-terminal old run is untouched, and the second counter counts it, verified by the retention tests of `ratatoskr-channel-digests` with PostgreSQL and by flow F4 of the native smoke when it is run, in which the run's window is rewound by SQL

### Requirement: Withdrawing a post minimizes the manifests that hold it

When a message disappears from a later walk of its channel and its revisions are withdrawn, channel-digests SHALL also null the whole `canonical_text` of every manifest that holds that message, whatever the state of the run, because one post cannot be cut out of a text whose digest is stored. A recap request whose manifest was withdrawn before Knowledge fetched it SHALL fail as `manifest_unavailable` and SHALL be retryable as a new run. A recap that Knowledge already stored SHALL NOT be withdrawn by this rule.

#### Scenario: A post is deleted upstream

- **WHEN** a message that an earlier manifest holds vanishes from a later walk
- **THEN** that manifest is minimized and a manifest that did not hold the message is intact, verified by the revision tests of `ratatoskr-channel-digests`; withdrawal by absence is not reachable in the native smoke, which has no MTProto credentials

### Requirement: The manifest route answers 410 once its text is gone

`GET /v1/manifests/{manifest_id}` SHALL answer `410 Gone` with an empty body when the owner, run and digest claims match a row whose text is minimized. Every other case SHALL be unchanged: `200` with the exact text and `Content-Type: application/json` for a live manifest, an empty `404` for an absent manifest, another owner's manifest, a missing or malformed claim, a run that is not the manifest's run and a digest that is not the stored one, and `503` for a database failure. The claims SHALL still gate the status, so `410` is reachable only by a caller that proves the owner, the run and the digest.

#### Scenario: Matching claims against a minimized manifest

- **WHEN** a caller presents the matching owner, run and digest for a minimized manifest
- **THEN** the route answers `410` with an empty body, a wrong digest or another owner answers `404`, and a manifest that was not minimized answers `200` with its exact text, verified by `ratatoskr-channel-digests` route tests and by flow F4 of the native smoke when it is run

### Requirement: Knowledge treats a gone manifest as terminal

Knowledge's digest source client SHALL map a `410` from the manifest route to a distinct error, and the bounded manifest attempt SHALL settle `manifest_unavailable` at once on it, without scheduling the one retry that an unavailable or timed-out answer gets, because a minimized manifest never comes back. Knowledge's own stored copy of a manifest (`knowledge.channel_recap_manifests`) is a Knowledge-owned copy and SHALL NOT be reached by this change.

#### Scenario: The route answers 410

- **WHEN** the route answers `410` and then `503` in separate attempts
- **THEN** the first settles `manifest_unavailable` with no retry scheduled and the second still schedules its one retry, verified by the digest source client tests of `ratatoskr-knowledge`
