## Context

See `proposal.md`. `ratatoskr-instagram@4161a83db86335637e234737024687ff79e2095e` already creates canonical captured, updated, and removed envelopes transactionally, but its deployable constructs `LoggingTransport`, whose `deliver` always returns success. `run_once` therefore sets `published_at` without an external carrier. `ratatoskr-platform@070b718238c4e6e45a5b7fc08ebe719ed5374e33` owns the NATS server policy; its Instagram identity can operate only the browser-capture durable and cannot publish facts. The event stream already accepts `evt.>` and the Instagram service already depends on `async-nats`, so no contract or production dependency is missing.

The current Instagram schema is edited in place and applied only to a fresh database. IG-014 adds no migration and does not need a schema change: the existing `event_type`, `payload`, `published_at`, `attempt_count`, and `next_attempt_at` columns contain everything required for real delivery and cutover repair.

## Goals / Non-Goals

**Goals:**

- Make `published_at` mean a received JetStream publish acknowledgement, never a local log side effect.
- Preserve every failed or disabled delivery as durable retryable intent.
- Recover all rows falsely credited by the only previously shipped transport before cutover.
- Keep the Instagram identity confined to its browser-capture durable and three owned event subjects.
- Prove the actual Platform policy and Instagram publisher against a real broker without provider credentials.

**Non-Goals:**

- Add or change SocialSource payload fields or event names.
- Implement Knowledge's missing social-event consumer or claim indexing.
- Deploy to the Raspberry Pi, rotate production NKeys, or operate a production database.
- Rework general outbox abstractions across other services.

## Decisions

### Expand the Platform ACL before deploying the producer

Platform adds exactly three publish subjects to the existing Instagram user stanza:

- `evt.social.source.captured.v1`
- `evt.social.source.updated.v1`
- `evt.social.source.removed.v1`

The existing consumer-info, next-message, acknowledgement, and `_INBOX.>` permissions remain unchanged. No `evt.>`, `cmd.>`, direct event subscription, stream administration, or consumer-create permission is added. Platform merges and deploys first; until then the corrected producer receives no acknowledgement and safely retains its rows.

Alternatives rejected: sharing Edge's credential broadens command authority; granting `evt.social.source.>` permits event types Instagram does not own; embedding permissions in a client credential duplicates Platform's deployment authority.

### Publish the stored row type and bytes through a JetStream transport

Change `EventTransport::deliver` to receive `event_id`, stored `event_type`, and canonical envelope bytes. `run_once` selects all three from the outbox, verifies the JSON envelope declares the same type, and calls a closed mapping from the three canonical event types to exact `evt.*` subjects. The concrete service transport calls JetStream publish and awaits the returned server acknowledgement inside a finite configured timeout. Only a successful acknowledgement returns `Ok`.

The transport never renders the envelope, NKey seed, owner, or subject payload. Diagnostics carry event id, allowlisted subject, error class, and retry count only. Existing `async-nats`, `tokio`, and JSON dependencies are sufficient; no new production dependency is added.

Alternatives rejected: Core NATS publish without JetStream acknowledgement cannot prove persistence; deriving a subject by arbitrary string concatenation can turn corrupt storage into authority over a foreign subject; parsing only the envelope ignores a disagreeing typed database column.

### Share one authenticated broker client at startup

Factor the existing NKey/anonymous connection code into one bounded connector. When bus configuration exists, startup connects once, validates the fixed browser-command consumer, creates the JetStream transport from a clone of the same authenticated client, and only then exposes readiness. The command consumer and publisher get separate task handles but one identity and connection policy.

When bus configuration is absent, neither consumer nor publisher starts. The service remains useful for explicitly standalone/local lanes, but emits a warning and readiness/metrics state that broker delivery is disabled; outbox rows are not attempted or changed. A logging fallback is deleted rather than retained behind a flag.

### Honour persisted retry eligibility

`run_once` selects only unpublished rows whose `next_attempt_at` is absent or due, ordered by due time and event id. A failed delivery increments `attempt_count`, records a content-free error class if the current schema supports it, and moves `next_attempt_at` by the existing finite retry interval. A successful acknowledgement sets `published_at` and clears retry scheduling. A crash after broker acknowledgement but before the database update causes byte-identical redelivery under the same event id, which is the accepted at-least-once contract.

### Repair logging-era rows with an explicit stopped-service command

Add `repair-logging-outbox` to the Instagram binary's closed operator grammar. It requires the normal database configuration plus an explicit confirmation token naming the logging-only cutover, obtains an Instagram-specific PostgreSQL advisory transaction lock, and changes only supported SocialSource rows with non-null `published_at`: clear `published_at`, set `next_attempt_at` to the transaction time, and retain event id, envelope, attempt count, and occurrence metadata. It prints only the repaired count.

The documented order is: stop the old service; run the repair; repeat if the command did not return success; deploy the corrected binary; start it. Repeating before startup updates zero rows. The command is intentionally unavailable as an HTTP route and must never be run after the real publisher begins; replay would remain consumer-idempotent, but operational misuse would create needless duplicate deliveries. No migration or durable marker is added because development status forbids migration machinery and the stopped-service sequence makes the transaction itself the boundary.

Alternatives rejected: automatic repair on every startup would requeue genuinely acknowledged facts; a migration/marker table is forbidden during development; leaving historical rows behind would not fully correct the loss.

### Test the actual deployment policy and the actual producer together

Platform's NATS permission test will materialize the checked-in `deploy/nats/ratatoskr.conf` by replacing public-key placeholders with disposable NKeys, rather than maintaining a second handwritten policy. A small test fixture command uses the existing `nkeys` dependency, writes admin and Instagram seeds only to a mode-0600 temporary directory, starts the pinned NATS test image, and reports connection metadata through files rather than logs.

Instagram adds real PostgreSQL/JetStream tests for acknowledgement, denial/timeout retention, due scheduling, type mismatch refusal, disabled-bus behavior, and repair atomicity. The workspace IG-014 runner starts the Platform fixture, passes its temporary endpoint/seed paths to the Instagram test, and verifies exact stored bytes, subject, `published_at` ordering, and forbidden-authority attempts. Docker unavailability is a failed integration precondition, never a skip.

This profile proves producer-to-stream delivery only. The evidence explicitly leaves downstream acknowledgement, Knowledge indexing, live credentials, provider behavior, and deployment unverified.

## Risks / Trade-offs

- [A publish acknowledgement can arrive immediately before process death] → The row redelivers with the same event id and bytes; consumers are contractually idempotent.
- [Permission denial can resemble a timeout] → Persist and expose a bounded transport error class, keep the row unpublished, and prove the denial path with the actual ACL.
- [Historical repair is operator-sensitive] → Use a closed confirmation token, transaction, advisory lock, stopped-service runbook, dry count in tests, and no network side effect.
- [One broker connection serves consumer and producer tasks] → `async-nats::Client` is cloneable and multiplexed; connection failure affects readiness/freshness visibly while PostgreSQL remains the durable source.
- [The workspace currently lacks reproducible pins] → IG-014 records exact child base/final SHAs and test paths in its changeset; this is coordination evidence, not a claim that the broader fleet snapshot issue is solved.
- [Docker is unavailable on the current host] → Repo-local unit/database tests and hosted exact-SHA CI remain mandatory; composed proof must run on a host/CI runner with Docker before workspace completion is claimed.

## Migration Plan

1. Platform RED/GREEN: add failing least-privilege tests against the actual config, then add only the three Instagram publish grants; run the full Platform gate, commit, push, and wait for exact-SHA hosted checks.
2. Instagram RED/GREEN: add broker-ack, retry, disabled-bus, mismatch, and repair tests; replace `LoggingTransport`, wire the shared client, and add the repair command; run the full Instagram gate, commit, push, and wait for exact-SHA hosted checks.
3. Workspace: add IG-014 changeset and composed runner/evidence, exercise Platform's actual policy with Instagram's actual transport, then commit and push the workspace coordination revision.
4. Deployment order, if separately authorized: deploy/reload Platform NATS policy; stop Instagram; run `repair-logging-outbox`; deploy/start Instagram; observe unpublished depth drain and broker acknowledgements. Knowledge consumption remains a separate rollout.

Rollback stops Instagram first and restores its prior binary without running the logging publisher against repaired rows; the narrow Platform grants can remain during diagnosis or be removed in a later Platform rollback. No acknowledged event or outbox row is deleted.
