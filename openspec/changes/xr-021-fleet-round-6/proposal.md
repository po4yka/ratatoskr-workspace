## Why

Round 5 of changeset XR-021 left four defects that the repository owner approved for a sixth and last round. A provider key that Knowledge's repository lane could not use (rejected, out of credit, model withdrawn) or a spend-budget refusal closed a GitHub analysis request as failed after about thirty seconds, although the operator could fix the cause, and GitHub had already recorded the repository's metadata as evaluated, so nothing re-queued the analysis. channel-digests kept the exact canonical manifest text, which contains every selected post body, for ever: the body retention timer and the withdrawal of posts deleted upstream minimized `post_revisions.body` and left the same bodies readable through `GET /v1/manifests/{id}`. ChatGPT and Claude recorded one stream sequence per outbox row at the broker's acknowledgement, so a fact row that the pump had selected before a deletion was still published without any record of its copy, and an acknowledgement whose commit failed lost the sequence of a copy for good. The workspace fleet map still described Round 1 (a `PUT` that Edge no longer sends, port `9084` shared by three services), and two F1 assertions passed for a refused upload on a `404` and for a transfer row that no longer existed. This change records, in the store the whole fleet reads, the behaviour that is true at those boundaries after Round 6, corrects the map and the assertions, adds the native legs, runs them, and advances the pins of the five repositories that changed.

## What Changes

- Add to `knowledge-ingest-limits`: the repository analysis waits out an operator-fixable provider failure and a spend-budget refusal and the GitHub request stays pending while it waits (R6-01).
- Add to `channel-digest-chain`: a manifest is minimized by the body retention timer and by withdrawal, its route answers `410` once its text is gone, and Knowledge treats `410` as terminal (R6-02).
- Add to `fleet-deletion-delivery`: every PubAck sequence of a fact is recorded, a fact row in flight is serialized with its deletion by a row lock, an acknowledgement whose commit failed is carried, and one residual is named (R6-03).
- Correct `docs/fleet-map.html` to the port table of `docs/DEPLOYMENT_TARGET.md` and the origin/main of the children, and make two F1 assertions of the native smoke assert what their names say (R6-04).
- Add native legs: F1 asserts the digest-mismatch refusal and the failed transfer row, F4 a manifest retention leg, F6 an in-flight deletion leg for ChatGPT and Claude, F7 a wait leg and a plain transient-fault leg in place of the 401 closure. The state directory and the evidence root are `XR-021-r6`.
- Advance the pins of knowledge, github, channel-digests, chatgpt and claude to their Round 6 heads and record the round in `changesets/XR-021-fleet-cross-repo-fixes.yaml`.

**Breaks, named:** channel-digests `digest_manifests.canonical_text` becomes nullable and the table gains `minimized_at` and the link table `digest_manifest_sources`; the manifest route gains the `410` status; `CanonicalManifest` carries the message pairs; Knowledge gains `DigestSourceClientError::Gone` and the repository family's wait; ChatGPT and Claude replace `published_stream_seq` by `published_stream_seqs`, publish a first copy of a row in a per-row transaction bounded to 5 s and gain a counter for a mark that lands on no row. The development status applies: one version, no migration, databases are recreated from the edited schema definitions. No contract changes and no new contracts commit.

## Capabilities

### Modified Capabilities

- `knowledge-ingest-limits`: the repository family's wait, and the pending GitHub request (added requirement).
- `channel-digest-chain`: manifest retention, withdrawal and the `410` (added requirements).
- `fleet-deletion-delivery`: the record of every published copy, the row lock and the carried acknowledgement (added requirements).

## Impact

- Repositories with Round 6 work: knowledge, github (tests and documentation only), channel-digests, chatgpt, claude. Platform, contracts, extractor, vault, x, instagram, threads, telegram, browser-extension, export-agent, mobile and web have none.
- Rollout order: channel-digests, then Knowledge (it reads the `410`), then ChatGPT and Claude, then github (no behaviour change), then the workspace pins. Recreate the channel-digests, ChatGPT and Claude databases from the edited schemas before starting the new binaries.
- Rollback: reset the five pins to the Round 5 heads recorded in the changeset and recreate the same three databases from the reset schemas.
