## Why

Rounds 1 to 3 of changeset XR-021 are merged. Round 3 shipped a native smoke harness that no flow had ever been run through, and the Round 3 by-hand smokes and the independent verifiers then found a fourth set of defects, each re-verified against `origin/main` before it was planned. A Claude archive that carries a project knowledge file ends `partially_succeeded` and the bytes are not retained, because the production import path never calls the ingestor that the accepted `project-knowledge-files` behaviour describes. Claude's privacy deletion leaves the deleted export's project description, conversation title and knowledge file in the shared rows and re-announces them to Knowledge after the tombstone. ChatGPT queues no tombstone for an account whose live mapping changed after its facts were announced, so Knowledge keeps the derived data for good. Knowledge dead-letters a documents, social or conversation delivery after five redeliveries and writes a row that nothing reads, so an outage of about a minute loses an ingestion that the producer already reported as published. Channel-digests reports a deep history as a partial acquisition although the whole window was read on page one, and fails a quiet channel with deep history. Threads refuses a shared link whose tracking parameter is percent-encoded. Telegram answers a PDF that was sent plain and then forwarded with a refusal although the item was saved, loses every capture of a sender whose Platform session was revoked until the cached credential expires, and accepts a notification ack wait that Edge's durable cannot honour. ChatGPT's `schema.sql` still carries migration-style `ALTER TABLE` statements. This change records, in the store the whole fleet reads, the behaviour that is true at those boundaries after round 4, adds the two workspace checks that stop the last two kinds of drift, fixes the native harness defects the first honest read found, and advances the pins to the round 4 heads.

## What Changes

- Add requirements to `ai-archive-import-completeness`: a Claude project knowledge file is ingested and verified on the production import and a completeness report counts it; a deletion restores the survivors of both providers to a version a retained export holds and removes the sources only the deleted export presented; the ChatGPT tombstone owner is the owner the archive's facts named.
- Add the capability `fleet-ingest-redelivery`: a retryable ingest failure of the documents, social and AI-archive families is redelivered without a budget and never dead-lettered, a failure that can never succeed is rejected at its first delivery, and the repository family keeps its bounded budget because its terminal delivery settles a fact a requester waits for.
- Modify `channel-digest-chain`: acquisition stops at the digest window, and a channel is partial only when the window was not read completely.
- Modify `social-capture-lifecycle`: the Threads grammar applies to the authority and the path only, never to the query or the fragment.
- Modify `content-capture-command`: a Telegram capture's idempotency key describes the exact request body, a conflict is a transient class, a Platform credential that was rejected is exchanged again once, and the notification ack wait is exactly Edge's fixed 30 seconds.
- Add two workspace checks: `schema_in_place.rs` (no `schema.sql` adds a column with `ALTER TABLE`) and `service_ack_wait_constants_agree_with_edges_durable_table` in `bus_durables.rs`. Both are documented in `docs/QUALITY_GATES.md` with what each cannot see.
- Fix the native smoke harness (R4-12): the shadowed `name` in `assert`, the `getMe` fields of the fake Bot API, the F3 assertions that one two-line message could satisfy, the F7 closure that accepted a failed fact, and the `XR-021-r3` state directory and evidence root. Add the legs listed in `integration/native/README.md`. No flow has been run through `run.sh` as committed; the README says so per flow.
- Advance the pins of platform, knowledge, channel-digests, github, threads, telegram, claude, chatgpt and x to their round 4 heads, record the round in `changesets/XR-021-fleet-cross-repo-fixes.yaml` and archive `xr-021-fleet-round-3` and then this change when every task of each is ticked.

**Breaks, named:** Claude's `schema.sql` gains `export_observations.content_digest` and the `entity_versions` table, and its parsed types derive serde; ChatGPT's `schema.sql` loses seven `ALTER TABLE` statements and its tombstone owner no longer follows the live mapping; Knowledge's `ingest_failures` table is removed and a retryable ingest failure is no longer dead-lettered after five deliveries; Telegram's capture idempotency key has a new derivation (`capture.v2`) and its notification ack wait must be exactly 30; the Threads permalink grammar accepts what it refused. The development status applies: one version, no migration, a database is recreated from the edited definition.

## Capabilities

### New Capabilities

- `fleet-ingest-redelivery`: how Knowledge settles a failed delivery of each ingest family.

### Modified Capabilities

- `ai-archive-import-completeness`: knowledge files, survivor content after a deletion, the tombstone owner.
- `channel-digest-chain`: window-bounded acquisition.
- `social-capture-lifecycle`: the Threads permalink grammar.
- `content-capture-command`: the Telegram capture key, session recovery and ack wait.

## Impact

- Repositories with round 4 work: platform (documentation), knowledge, channel-digests, github, threads, telegram, claude, chatgpt and x (a CI repair of round 3). Contracts, extractor, vault, instagram, browser-extension, export-agent, mobile and web have none.
- Rollout order: no contract changes, so the children are independent; Claude's R4-03 needs its R4-02 first. Services fail startup until Edge has provisioned their durable, as in round 3, and Telegram's dispatcher now also refuses an ack wait other than 30.
- Rollback: reset the pins to the round 3 heads recorded in the changeset; recreate the Claude, ChatGPT and Knowledge databases from the schema of the reset pin.
