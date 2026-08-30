## Context

See `proposal.md` for motivation. GitHub Catalog already has a transactional `outbox_events` table, an `inbox_events` table, typed domain handlers for scheduled sync, Knowledge terminal facts and Vault acknowledgement, and functions that dispatch due analysis and backup policy. Its service binary starts only database-backed HTTP listeners. It has no NATS dependency, bus configuration, publisher, durable consumers, worker supervisor, bus-aware readiness, or deployment role. Worse, scheduled-sync handling currently inserts its inbox claim before provider work and treats any later redelivery as a duplicate even when the first attempt never completed.

Platform owns the two bounded JetStream streams and their security policy. Applications must not create consumers. The current shared contracts already supply the command/event envelope types needed by this change; no payload contract needs another version. The database is disposable during development, so schema changes edit `schema.sql` in place and all call sites move together.

## Goals / Non-Goals

**Goals:**

- Make every currently implemented GitHub cross-service workflow reachable from the serving process.
- Preserve accepted intent across process, broker, provider, and database failure windows without an exactly-once claim.
- Keep Platform topology authority separate from GitHub message authority.
- Make readiness and telemetry distinguish shared runtime health from one failed message or provider account.
- Supply a production-shaped systemd configuration and fixture proof across the exact transport boundary.

**Non-Goals:**

- Adding new GitHub domain events that have no current typed producer.
- Activating Knowledge or Vault production runtimes or claiming their business outcome.
- Changing shared payload meaning or introducing a second envelope or subject version.
- Operating the frozen host, generating production seeds, registering live schedules, or calling live GitHub.
- Treating fixture peers as evidence for deployed downstream services.

## Decisions

### 1. Persist classified subjects and final wire bytes

`outbox_events.subject` becomes the exact NATS subject. Its payload becomes the final serialized envelope object, not a domain payload that a later publisher must enrich. Producers create the envelope inside the same transaction as the domain state. `message_id` equals the event or command identity and is later sent as `Nats-Msg-Id`.

Repository analysis uses `evt.knowledge.repository_analysis.requested.v1` because the published shared type is an `EventPayload`: it records that GitHub durably requested Knowledge admission, while Knowledge remains free to admit or reject work. Desired policy uses `cmd.vault.target.desired.v1` and a canonical command envelope constructed around the current `DesiredBackupPolicy` document. Knowledge terminal facts and Vault feedback are canonical event envelopes; scheduled sync is the existing canonical command envelope.

Runtime subject inference was rejected because a restart must publish exactly the bytes and destination accepted by the original domain transaction. Retaining unclassified names was rejected because it makes `cmd.` versus `evt.` an adapter guess and hides permission drift.

### 2. Provision four independent inbound durables

Platform adds:

- `ratatoskr_github_sync` on the command stream for `cmd.github.sync.requested.v1`;
- `ratatoskr_github_analysis_completed` on the event stream for `evt.knowledge.repository_analysis.completed.v1`;
- `ratatoskr_github_analysis_failed` on the event stream for `evt.knowledge.repository_analysis.failed.v1`;
- `ratatoskr_github_vault_policy_ack` on the event stream for `evt.vault.backup_policy.acknowledged.v1`.

Separate durables make each family cursor, backlog, delivery limit and failure independently observable, and avoid one poison family consuming another's delivery budget. One multi-filter durable was rejected because a single blocked cursor would combine unrelated authorities and complicate least-privilege proof.

The GitHub NKey may publish the two declared application subjects, call consumer-info/next/ack only for these four durable names, and subscribe only to `_INBOX.>`. It receives no general `$JS.API.>` or wildcard `cmd.>`/`evt.>` authority.

### 3. Give the outbox persisted claims, ordering keys and recovery state

The current schema is extended in place with an aggregate `ordering_key`, monotonic `ordering_sequence`, lease owner/deadline, attempt count, next-attempt time, published time, dead-letter time and stable last-error code. The publisher takes a bounded `FOR UPDATE SKIP LOCKED` batch, but a row is claimable only when no earlier unpublished/non-superseded row for the same ordering key exists. Repository-analysis envelopes order per repository; backup policy orders under one estate key.

On broker acknowledgement the publisher conditionally marks the still-owned lease published. A failure releases or expires the lease and schedules bounded exponential backoff with jitter. Exhaustion retains the exact row as dead-letter. A narrow operator command requeues that same identity after inspection; it never edits payload or creates another row.

A single global FIFO was rejected because one private repository or downstream permission error could halt all fleet communication. Unordered batching was rejected because a later policy or repository revision could overtake its predecessor.

### 4. Model inbox receipt, lease and terminal outcome separately

Inbox rows gain transport coordinates, processing lease, attempt state, terminal outcome and safe failure code. The consumer records or resumes a receipt, invokes the subject-specific handler, commits domain state and terminal inbox state together where possible, then acknowledges JetStream. A committed terminal row makes redelivery a no-op acknowledgement.

Canonical validation failure and foreign payload type are permanent: GitHub commits a redacted terminal rejection and terminates the broker delivery. Database unavailability, provider/network failures, cancellation and lost leases are retryable: the delivery is negatively acknowledged with bounded delay or left unacknowledged during shutdown.

The current `insert ... on conflict => Duplicate` sync behavior is replaced by a claim state machine. Only `consumed` or `rejected` is a terminal duplicate. `received`, `processing` with an expired lease, and `retryable_failure` can resume. Provider sync already uses durable checkpoints and authoritative full-snapshot completion, so replay does not turn an incomplete listing into absence evidence.

### 5. Supervise seven bounded workers with shared cancellation

The serving process starts one outbox publisher, four durable consumers, one due-analysis dispatcher and one policy reconciliation worker. Each uses finite batch size, concurrency, operation timeout, poll interval and backoff from validated configuration. A supervisor observes task exit, reports component heartbeat, restarts retryable loop failures with bounded backoff, and begins coordinated cancellation on process drain.

Independent loops are chosen over one select loop so a slow provider sync cannot delay Vault feedback or outbox publication. An unbounded task per delivery is rejected for Pi memory/file-descriptor safety. The database remains the work queue; no in-memory queue is authoritative.

### 6. Authenticate sync commands with account-owned credentials at execution

The sync consumer parses the command enough to identify the account, loads the active encrypted credential under GitHub's existing credential boundary, and constructs an authenticated provider adapter for that delivery. A shared rate-limit ledger remains keyed by non-secret token reference. Fleet serving requires the encryption key configuration; secret values never enter message, inbox diagnostics, logs or metrics.

Passing one unauthenticated process-global provider adapter to every sync command was rejected because production sync cannot work and account credentials must not cross tenant boundaries.

### 7. Readiness covers shared dependencies, not individual business outcomes

Startup reads the protected seed, connects to NATS, verifies the two streams and four durable configurations through its permitted info calls, starts all seven workers, then marks ready. Ongoing observations cover database, bus connection, durable topology and supervisor heartbeats. Loss beyond a small observation bound makes readiness false. One provider failure or dead-letter remains a metric/workflow state while unrelated work can proceed.

This fixes listener-only false readiness without turning one revoked PAT into a deployment-wide outage.

### 8. Deploy GitHub as a dedicated systemd role

The GitHub repository adds an arm64 `Type=exec` unit, redacted environment example and logrotate rule. The workspace allocates operator port `9469`; the domain listener remains `127.0.0.1:8092`. The operator listener binds for the documented monitoring path only when the host firewall is updated by a separately authorized deployment action. The unit reads the NKey seed and other secrets from protected files/environment, writes logs under the approved NVMe log root, uses a dedicated user, restricts writable paths, and sets `TimeoutStopSec=130s`, above the process maximum.

Compose remains fixture-only. No host file, firewall or running service is changed by repository delivery.

### 9. Prove crash windows with controllable fixture peers

The workspace profile uses Platform's actual NATS configuration with generated synthetic NKeys, disposable PostgreSQL, a fake GitHub HTTP provider, and small Knowledge/Vault fixture peers. Fault hooks stop GitHub after inbound commit before ack and after outbound broker ack before database mark. Tests assert exact message identities, bytes, domain row counts, durable acknowledgement floors, lag and readiness under deadlines rather than sleeps.

Directly calling GitHub handler functions was rejected as integration proof because it bypasses the absent runtime boundary. Fixture proof remains explicitly distinct from live provider and deployed downstream evidence.

## Risks / Trade-offs

- **[Changing stored subject/envelope shape breaks old development databases and local readers]** → Development policy requires one current schema and disposable databases; update all callers/tests together and add no migration or compatibility decoder.
- **[Repository-analysis request remains event-classified despite its name]** → Follow the already-published `EventPayload` contract and document the semantic distinction: GitHub records a request for admission, while Knowledge owns admission and work. A later contract change, if desired, is separate and must update both services.
- **[Four durables increase topology and worker count]** → They provide independent cursors and fault isolation; cap pulls and tasks conservatively and verify exact permissions with a real broker.
- **[A dead-letter blocks later rows for one ordering key]** → Preserve sequence truth, expose the blocking key and age without payload, and provide exact-identity operator requeue while unrelated keys continue.
- **[Provider retries can repeat external reads]** → Use existing checkpoints, conditional requests, idempotent projections and full-snapshot authority; never infer removals from an incomplete retry.
- **[Bus dependency makes startup/readiness stricter]** → This is intentional because a busless GitHub process cannot perform its declared fleet role; operator-only commands validate only the configuration they actually need.
- **[Port 9469 monitoring requires a host firewall change]** → Commit only the allocation and unit/profile; live firewall modification stays outside this task and no deployment claim is made.

## Migration Plan

1. Create changeset `GHB-017` and isolated child worktrees from the recorded `origin/main` commits.
2. Merge Platform's fixed durables, GitHub NKey permissions and real-broker permission tests first. Provisioning is additive and unused by the old GitHub process.
3. Merge GitHub's schema-in-place changes, envelope-producing call sites, outbox/inbox adapters, workers, readiness, deployment artifacts and documentation. Recreate development/test databases from the current schema.
4. Run the workspace profile against exact proposed child commits, including both forced restart windows and negative permission checks.
5. After both child PRs merge, update workspace pins and lock, rerun repository and integration gates, record evidence and merge the workspace change.

Rollback first disables GitHub schedules and stops the bus-enabled unit so no new delivery is claimed. Restore the previous GitHub binary/unit configuration and workspace pins, removing bus-only environment keys that the old strict configuration does not recognize. Retain outbox/inbox databases and all four Platform durables; do not delete, purge or reset cursors. The additive Platform topology may remain idle until the runtime is restored.
