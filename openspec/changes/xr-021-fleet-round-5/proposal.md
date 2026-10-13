## Why

Rounds 1 to 4 of changeset XR-021 are merged. Round 4 left three things open: no committed native flow had ever been run through `integration/native/run.sh`, the Round 4 verifiers and smokes had found defects rated medium or higher that were re-verified against `origin/main` on 2026-10-12, and the owner set a stream policy. Round 5 closes them. Round 4 stopped Knowledge from dead-lettering a retryable delivery, but it still lost content in four places: a provider key that was rejected, credit that ran out or a model that was withdrawn poisoned the run permanently, a conversation above 1 MiB failed the snapshot store and was never searchable, the same PDF captured twice became two library documents, and a survivor fact that shared the stale head's instant was filed as historical. Platform never removed an abandoned archive upload, so a laptop that stopped mid-upload left up to twice the archive size on the Pi for good, and the Export Agent retried a dead resumption token for ever instead of reopening a session. A privacy deletion addressed Claude's and ChatGPT's tombstones to the live account mapping, so a mapping change between import and deletion left a user's data in Knowledge; a tombstone was marked published at the broker's acknowledgement and never looked at again although the events stream drops its oldest message at 7 days or 1 GiB; and the deleted conversation's full text stayed in that stream, where nothing could remove it. channel-digests kept the oldest 100 posts of a window and dropped the newest silently, summarised posts that were deleted upstream in every later digest and never minimised a stored body. Instagram's content digest was a constant, so Knowledge never analysed an update, and Telegram's progress stream was cut every ten seconds by the whole-call timeout. This change records, in the store the whole fleet reads, the behaviour that is true at those boundaries after Round 5, adds the workspace checks that stop the drift in the new durables, the ACL and the alert rules, fixes and extends the native harness, runs it, and advances the pins to the Round 5 heads.

## What Changes

- Add the capability `fleet-deletion-delivery`: Knowledge acknowledges every deletion fact it applies or refuses; the five producers re-send until it does; every tombstone is addressed to the owner the subject was announced under; Edge erases the producer's published copy of deleted content from the events stream on request, and only for what the producer published (R5-06, R5-11, R5-12).
- Add the capability `fleet-bus-observability`: Edge exports consumer lag and stream state, and the lag alert rules are shipped and name only series that exist (R5-13).
- Add the capability `ai-archive-upload-path`: Platform removes abandoned staging and replaces a dead transfer session; the Export Agent classifies Platform answers, reopens and bounds its retries (R5-04, R5-05).
- Add the capability `content-document-identity`: one document identity per owner and content digest, from the extractor to Knowledge (R5-02).
- Add the capability `knowledge-ingest-limits`: a snapshot up to the broker payload, operator-fixable provider failures redelivered, an equal-time head replaced by the later event (R5-03, R5-08).
- Modify `channel-digest-chain`: the digest takes the newest posts and says when it did not take all; posts deleted upstream are withdrawn; stored bodies are minimised on a timer (R5-07).
- Modify `social-capture-lifecycle` (added requirement): an Instagram fact is digested and timed by what the post says (R5-09).
- Modify `content-capture-command` (added requirement): the Telegram progress stream is not cut by the whole-call timeout (R5-10).
- Modify `fleet-bus-topology`: the durable table holds 23 service durables, and only Edge may publish under `$JS.API.STREAM.` (the stream info of a KV bucket aside).
- Add four workspace checks and change two: `tombstone_acks.rs`, `alert_rules.rs`, `base_urls.rs`, and invariant 7 and the new publish rights in `bus_acl.rs`; `bus_durables.rs` follows the 23 durables and resolves a named filter constant. All are documented in `docs/QUALITY_GATES.md` with what each cannot see.
- Fix and extend the native smoke harness (R5-14): one interpreter chosen by a probe, a failed query is a failed assertion, no flow reads the removed `ingest_failures` table, the F6 probe order and the series-3 digest, F1 waits for fresh capabilities, the state directory is `XR-021-r5`, `RATATOSKR_SMOKE_REF` runs a flow against the heads the children publish, and the legs of Round 5 and the Round 4 legs that were never written are added. Run every flow F0 to F7 through `run.sh` as committed.
- Advance the pins of contracts, platform, extractor, knowledge, channel-digests, chatgpt, claude, x, instagram, threads, telegram, github, vault and export-agent to their Round 5 heads, record the round in `changesets/XR-021-fleet-cross-repo-fixes.yaml`, and archive `xr-021-fleet-round-3` and then `xr-021-fleet-round-4`.

**Breaks, named:** the extractor's `extraction_runs.document_id` is removed and the identifier is derived; Knowledge's `blob_bytes` below 8,388,608 refuses to start, a partial unique index on extractor sources is added, `ProviderError::OperatorAction` and two failure classes are added, the equal-time head rule changes and `knowledge.event_outbox` gains a subject; Platform gains five durables, ACL lines, `RATATOSKR__ARCHIVE_STAGING__SWEEP_INTERVAL_SECONDS` (rule V23), a dead session is replaced on `open`, and a command consumer; ChatGPT and Claude gain the `announced_subjects` ledger, lose the live-mapping deletion path (Claude's plan no longer refuses an unmapped tenant), gain outbox columns and the erasure command; X, Instagram and Threads gain outbox columns, a consumer and a durable; Instagram's digest preimage changes; channel-digests changes the warning text and gains `RETENTION__*` keys; the Export Agent's journal format changes; Telegram gains a stream client. The development status applies: one version, no migration, a database is recreated from the edited schema.

## Capabilities

### New Capabilities

- `fleet-deletion-delivery`: how a deletion fact is acknowledged, re-sent, addressed and erased from the stream.
- `fleet-bus-observability`: the series and alert rules that describe the bus.
- `ai-archive-upload-path`: staging cleanup, session replacement and the agent's handling of Platform answers.
- `content-document-identity`: the one document identity.
- `knowledge-ingest-limits`: snapshot ceiling, recoverable provider failures, head tie-break.

### Modified Capabilities

- `channel-digest-chain`: newest-post selection, withdrawal by absence, retention.
- `social-capture-lifecycle`: Instagram's digest and observation time.
- `content-capture-command`: the Telegram progress stream.
- `fleet-bus-topology`: the durable table and the stream API rule.

## Impact

- Repositories with Round 5 work: contracts, platform, extractor, knowledge, channel-digests, chatgpt, claude, x, instagram, threads, telegram and export-agent; github and vault move their pin only. Browser-extension, mobile and web have none.
- Rollout order: contracts first (additive: two registered messages), then the thirteen repositories in any order, then the workspace pins. Services fail startup until Edge has provisioned their durable, as before; Edge starts first, then Knowledge, then the five producers.
- Rollback: reset the pins to the Round 4 heads recorded in the changeset and recreate the extractor, Knowledge, ChatGPT, Claude, X, Instagram, Threads and channel-digests databases from the schema of the reset pin. The five new durables stay on the broker (their cursors are never deleted).
