## Purpose

Defines the fleet-visible delivery, recovery, security, readiness, and deployment behavior that connects GitHub Catalog's durable domain workflows to the Platform-owned message bus.

## ADDED Requirements

### Requirement: GitHub uses one exact classified subject inventory

GitHub Catalog SHALL consume scheduled synchronization only from `cmd.github.sync.requested.v1`, Knowledge completion only from `evt.knowledge.repository_analysis.completed.v1`, Knowledge failure only from `evt.knowledge.repository_analysis.failed.v1`, and Vault policy feedback only from `evt.vault.backup_policy.acknowledged.v1`. It SHALL publish repository-analysis admission requests only to `evt.knowledge.repository_analysis.requested.v1` and desired backup policy only to `cmd.vault.target.desired.v1`. Persisted outbox and inbox subjects SHALL equal these transport subjects, including their class prefixes; the process SHALL reject every undeclared subject.

#### Scenario: Outbound records name their transport subjects
- **WHEN** a repository-analysis request and a desired backup policy are committed to the outbox
- **THEN** their subjects are exactly `evt.knowledge.repository_analysis.requested.v1` and `cmd.vault.target.desired.v1`, with no prefix inferred at publish time

#### Scenario: Foreign delivery changes no domain state
- **WHEN** GitHub receives a message on a subject outside its four declared inputs
- **THEN** the message cannot reach a GitHub durable or handler and no inbox or domain row changes

### Requirement: Outbox stores the final contract-valid wire message atomically

Each GitHub outbox row SHALL contain the complete final wire message that is published. A repository-analysis request SHALL use the current canonical event envelope and typed request payload. A desired backup policy SHALL use the current canonical command envelope and typed policy document. The domain mutation, wire message, stable message identity, subject, aggregate ordering key, and sequence SHALL commit atomically; credentials, authorization headers, provider bodies, and private diagnostics MUST NOT appear in the envelope or outbox.

#### Scenario: Repository revision and analysis event commit together
- **WHEN** GitHub commits a new immutable repository source revision
- **THEN** the same transaction stores one contract-valid analysis-request event envelope whose event identity equals the outbox message identity and whose tenant, repository aggregate, and source revision correlate to that commit

#### Scenario: Policy command is self-contained
- **WHEN** the policy debounce worker commits a changed desired policy
- **THEN** the outbox stores one canonical command envelope carrying that exact policy version and enough correlation identity for a consumer to validate it without reading GitHub's database

#### Scenario: Secret material is absent by construction
- **WHEN** an outbox envelope is serialized, logged as metadata, or delivered to a fixture consumer
- **THEN** it contains no GitHub token, database credential, NKey seed, authorization header, raw private provider response, or private diagnostic

### Requirement: Platform provisions fixed least-privilege GitHub delivery

Platform SHALL pre-provision one GitHub command durable filtered to scheduled sync and three GitHub event durables filtered individually to Knowledge completion, Knowledge failure, and Vault policy acknowledgement. Each durable SHALL use explicit acknowledgement, bounded acknowledgement wait and delivery attempts, deliver-all replay, and a stable cursor. GitHub's service identity SHALL inspect, fetch, and acknowledge only those four durables, publish only its two declared outbound subjects, subscribe only to its reply inbox, and SHALL NOT create consumers, inspect unrelated streams, directly subscribe to command/event wildcards, purge streams, or delete streams or consumers.

#### Scenario: Downtime preserves every inbound family independently
- **WHEN** one message for each inbound subject is published while GitHub is stopped and GitHub later starts
- **THEN** each fixed durable resumes from its own cursor and delivers its stored message

#### Scenario: GitHub cannot widen its bus authority
- **WHEN** the GitHub identity attempts consumer creation, an unrelated durable fetch, wildcard subscription, foreign publish, purge, or deletion
- **THEN** NATS denies the operation while all six declared publish/fetch paths remain usable

#### Scenario: Durable drift blocks startup
- **WHEN** a named GitHub durable exists with a different filter or acknowledgement policy
- **THEN** GitHub reports the topology mismatch, does not replace or mutate the durable, and does not report ready

### Requirement: Outbox publication is ordered, at least once, and recoverable

GitHub SHALL claim only due unpublished rows under bounded leases and concurrency, publish the stored bytes using the outbox message identity as `Nats-Msg-Id`, and mark a row published only after JetStream confirms persistence. It SHALL preserve sequence within an aggregate ordering key, SHALL allow unrelated keys to progress independently, and SHALL retain failed rows with bounded backoff, attempt count, stable redacted error code, and an explicit dead-letter state that can be operator-requeued without changing message bytes or identity.

#### Scenario: Crash after broker acknowledgement loses nothing
- **WHEN** JetStream persists a message and GitHub terminates before marking its outbox row published
- **THEN** restart republishes the same subject, bytes, and message identity, downstream idempotency absorbs any redelivery, and the row eventually becomes published

#### Scenario: One broken ordering key does not block another
- **WHEN** the earliest row for one repository repeatedly fails while a due row for another repository is publishable
- **THEN** the second repository progresses while no later row for the failing repository overtakes its predecessor

#### Scenario: Exhausted delivery remains recoverable
- **WHEN** one row reaches its configured publication-attempt limit
- **THEN** its payload and identity remain stored in a visible dead-letter state and an explicit operator requeue makes the identical row due again without creating another message

### Requirement: Inbound acknowledgement follows durable handling

GitHub SHALL acknowledge an inbound JetStream delivery only after its corresponding inbox and domain outcome commit. Duplicate deliveries whose prior terminal outcome committed SHALL be acknowledged without repeating the effect. A transient database, provider, or dependency failure SHALL leave the message eligible for delayed redelivery. A permanently malformed or foreign envelope SHALL commit a redacted terminal rejection tied to stable stream delivery coordinates and SHALL be terminated so it cannot poison the durable.

#### Scenario: Commit before acknowledgement is replay-safe
- **WHEN** GitHub commits a Knowledge completion or Vault acknowledgement and terminates before its JetStream acknowledgement
- **THEN** redelivery finds the terminal inbox record, repeats no projection change, and advances the durable acknowledgement floor

#### Scenario: Transient dependency failure is retried
- **WHEN** an otherwise valid delivery encounters a retryable database or provider failure before a terminal inbox outcome commits
- **THEN** GitHub does not acknowledge it and a later delivery can perform the intended work

#### Scenario: Malformed envelope cannot poison a durable
- **WHEN** a delivery on an owned subject violates its canonical envelope or typed payload contract
- **THEN** GitHub records one redacted terminal rejection, changes no domain projection, terminates the delivery, and continues processing later messages

### Requirement: Sync inbox claims distinguish unfinished work from duplicates

A scheduled sync command SHALL be considered a duplicate only after its command identity has a committed terminal inbox outcome. A claim whose work failed, was cancelled, or lost its lease before terminal completion SHALL remain resumable on redelivery. Re-execution SHALL reuse durable synchronization checkpoints and SHALL NOT infer star or list removals from an incomplete pass.

#### Scenario: Provider failure after claim resumes
- **WHEN** GitHub claims a valid sync command and the provider fails before the command reaches a terminal inbox outcome
- **THEN** redelivery retries or resumes the command instead of reporting it as an already-completed duplicate

#### Scenario: Completed command is not repeated
- **WHEN** a sync command reaches its committed terminal outcome and the broker redelivers the same command identity
- **THEN** GitHub acknowledges the duplicate without starting another sync run or provider request

#### Scenario: Interrupted full snapshot preserves absence safety
- **WHEN** a retried sync follows a cancelled, truncated, or failed full snapshot
- **THEN** no absence-based star or list removal is established from the incomplete attempt

### Requirement: Due local workflows continuously reach the outbox

While serving, GitHub SHALL run bounded workers that dispatch due repository-analysis requests and reconcile dirty backup policy after its trailing deadline. Restart SHALL recover due database state without an external kick, duplicate version, or duplicate outbox message. Failure of one due item SHALL be recorded and SHALL NOT permanently stop either worker.

#### Scenario: Queued analysis becomes publishable without an API call
- **WHEN** a repository-analysis request reaches its durable due time while the service is serving
- **THEN** it moves to pending with one outbox envelope without an operator or HTTP request invoking the dispatcher

#### Scenario: Dirty policy publishes after restart
- **WHEN** backup policy is marked dirty, GitHub stops before the trailing deadline, and restarts after the deadline
- **THEN** the worker derives current state and commits exactly one next policy version and outbox command

#### Scenario: Worker failure does not end scheduling forever
- **WHEN** one due reconciliation attempt fails transiently
- **THEN** the failure is observable and a later bounded attempt runs without restarting the service

### Requirement: Readiness proves the bus runtime can serve work

GitHub SHALL report ready only while its database is usable, bus connection is active, all four fixed durables match their required topology, and the publisher, consumers, and due-work supervisor are alive. Merely serving the admin and domain listeners SHALL NOT satisfy readiness. A single dead-letter row or provider-specific sync failure SHALL remain visible as workflow health without making shared service readiness false when the bus runtime can still process unrelated work.

#### Scenario: Listener-only process is unready
- **WHEN** the admin and domain listeners are bound but the bus supervisor is absent or stopped
- **THEN** `/ready` reports a stable non-ready dependency result

#### Scenario: Broker loss changes readiness
- **WHEN** GitHub loses its usable bus connection beyond the configured observation bound
- **THEN** readiness becomes non-ready and returns only after the connection, durable checks, and workers recover

#### Scenario: One dead letter is separately observable
- **WHEN** one outbox row is dead-lettered while other ordering keys and all shared dependencies remain usable
- **THEN** GitHub stays service-ready and exposes nonzero dead-letter count and oldest-age evidence without exposing its payload

### Requirement: Shutdown drains the bus without losing accepted work

On termination GitHub SHALL stop accepting new domain requests and new bus claims, stop creating due outbox work, finish or release finite in-flight database claims within its configured ceiling, leave uncommitted inbound deliveries available for redelivery, close both HTTP listeners and the bus connection, and then close its database. The deployment supervisor timeout SHALL exceed the validated process shutdown ceiling.

#### Scenario: Signal during inbound work preserves redelivery
- **WHEN** GitHub receives its termination signal before an inbound domain outcome commits
- **THEN** it does not acknowledge the delivery and the fixed durable can redeliver it after restart

#### Scenario: Signal after commit repeats no work
- **WHEN** termination arrives after the inbox outcome commits but before the acknowledgement completes
- **THEN** restart safely acknowledges the redelivery without repeating the domain effect

#### Scenario: Publisher lease is recoverable
- **WHEN** termination interrupts an outbox claim before publish confirmation
- **THEN** the lease expires or is released and the identical row can be claimed after restart

### Requirement: Deployment artifacts carry the fleet-bus boundary

GitHub SHALL provide an `aarch64-unknown-linux-gnu` systemd role using a dedicated Unix identity, the allocated loopback domain API port `8092`, an allocated operator port recorded by the workspace, the owned PostgreSQL role, and a protected NKey seed file. The role SHALL use `Type=exec`, bounded off-boot logging, explicit resource and filesystem restrictions, and a stop timeout longer than the process ceiling. Secret values SHALL NOT appear in the unit, checked-in environment example, process arguments, logs, metrics, or readiness output.

#### Scenario: Checked-in deployment is internally consistent
- **WHEN** the GitHub deployment profile is validated against the workspace deployment contract and Platform NATS configuration
- **THEN** its ports, service identity, NKey path, database ownership, writable paths, log path, and shutdown bounds agree exactly

#### Scenario: Missing bus seed fails safely
- **WHEN** the serving role has no readable NKey seed file
- **THEN** configuration/startup fails with the field name and a stable rule without printing a path's contents or any secret value

### Requirement: Fixture integration crosses every GitHub bus boundary

The workspace SHALL provide a deterministic profile with PostgreSQL, a Platform-configured NATS server, a fake GitHub provider, and fixture Knowledge/Vault peers. It SHALL prove scheduled sync intake, both outbound subjects, all three inbound event families, due-work execution, restart recovery, exact durable cursors, readiness, shutdown, and redaction. Passing fixture evidence SHALL remain distinct from hosted CI, live GitHub, live Knowledge/Vault, production-host, and deployment acceptance.

#### Scenario: Full fixture flow converges
- **WHEN** the profile publishes one scheduled sync, causes one repository analysis request and one dirty backup policy, and returns matching Knowledge and Vault facts
- **THEN** GitHub consumes the sync once, publishes both exact outbound envelopes, records both feedback families once, and exposes no secret material

#### Scenario: Restart windows lose no message
- **WHEN** the profile restarts GitHub once after inbound commit before acknowledgement and once after outbound broker acknowledgement before outbox marking
- **THEN** every intended domain outcome exists once, the outbox converges, and all four durable cursors advance without an unbounded backlog

#### Scenario: Fixture result is labelled honestly
- **WHEN** the profile passes using only synthetic credentials and fixture peers
- **THEN** its evidence is labelled fixture integration and makes no provider, downstream-service, hosted-CI, or deployment-host claim
