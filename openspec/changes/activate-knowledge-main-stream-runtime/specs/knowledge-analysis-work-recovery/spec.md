## Purpose

Defines crash-safe, replay-safe execution and terminal publication for every analysis family admitted from the Knowledge primary event stream.

## ADDED Requirements

### Requirement: Admission creates recoverable work
Knowledge SHALL represent each admitted document, social, AI-archive, or repository-analysis fact as durable work with an explicit state, attempt policy, next eligible instant, lease ownership, and immutable input identity. Receipt deduplication alone SHALL NOT mark analysis work complete.

#### Scenario: Crash after admission does not strand work
- **WHEN** Knowledge commits an event receipt and stops before an analysis worker starts
- **THEN** a later process claims and completes the admitted work without requiring another upstream event

#### Scenario: Redelivery does not duplicate work
- **WHEN** the same immutable event is delivered again before or after its admitted work completes
- **THEN** Knowledge has one logical work item and does not repeat a completed provider charge or terminal outcome

#### Scenario: Expired lease is reclaimed
- **WHEN** a worker stops while holding non-terminal work and its lease expires
- **THEN** another worker can reclaim the same work from its persisted state without creating a second logical analysis

### Requirement: Every persisted analysis state is recoverable
For document, social, AI-archive, and repository analysis, Knowledge SHALL either resume deterministically from every persisted non-terminal state or explicitly transition that state to a retryable, uncertain, or final failure. Restart SHALL NOT require an illegal transition back to the initial state and SHALL NOT repeat a provider request whose accepted response is already durable.

#### Scenario: Restart at each pipeline boundary
- **WHEN** the process is stopped after any persisted pipeline transition and then restarted
- **THEN** the work either reaches the same terminal result without duplicate durable output or enters an explicit uncertain state when external acceptance cannot be proven

#### Scenario: Uncertain provider acceptance is not retried blindly
- **WHEN** a connection fails after a provider may have accepted a billable request and the provider offers no idempotency or reconciliation primitive
- **THEN** Knowledge records an uncertain outcome and requires explicit policy-authorized requeue instead of automatically issuing another request

#### Scenario: Transient dependency failure is bounded
- **WHEN** a provider, content resolver, database, blob store, or broker dependency reports a retryable failure
- **THEN** Knowledge records the next eligible attempt with bounded backoff and does not spin or hold a bus delivery open for the retry interval

#### Scenario: Final failure terminates work once
- **WHEN** retry policy is exhausted or a non-retryable analysis failure is confirmed
- **THEN** the work enters one final failure state and any required failure fact is queued exactly once

### Requirement: Source lifecycle ordering protects derived state
Knowledge SHALL compare authoritative source revision and lifecycle state before analysis or search mutation. Social removal and AI-archive tombstone facts SHALL delete the owner's scoped derived analysis, embeddings, and search entries and SHALL prevent older or equal source facts from recreating them.

#### Scenario: Social update supersedes an older replay
- **WHEN** a social update is accepted and an older capture or update is delivered later
- **THEN** the newer source head, analysis, and search projection remain authoritative and the older delivery creates no replacement result

#### Scenario: Social removal suppresses resurrection
- **WHEN** a social source is removed and an older capture or update is replayed afterward
- **THEN** its scoped derived state remains absent and no completion fact claims a new analysis

#### Scenario: Archive tombstone suppresses resurrection
- **WHEN** an AI-archive subject is tombstoned and an older added or updated fact is replayed afterward
- **THEN** its scoped derived state remains absent while unrelated owners and subjects are unchanged

### Requirement: Repository content is resolved through an authenticated bounded boundary
Repository analysis SHALL resolve the requested immutable README content reference through its owning service boundary, verify the returned digest and owner scope, enforce bounded response size and timeout, and never interpret a blob reference as a local filesystem path or fetch an arbitrary caller-supplied URL.

#### Scenario: Verified README is analysed
- **WHEN** an authorized repository request resolves immutable README bytes whose digest matches the request
- **THEN** Knowledge analyses exactly those bytes and queues one repository-analysis completion fact

#### Scenario: Unavailable or corrupt README is classified
- **WHEN** the content boundary is unavailable, unauthorized, oversized, or returns bytes with a conflicting digest
- **THEN** Knowledge applies the declared retry or final-failure policy without analysing unverified content

### Requirement: Terminal state and publication intent are atomic
Every Knowledge terminal success or failure fact SHALL be inserted into a general transactional outbox in the same commit that makes the corresponding work terminal. An independent publisher SHALL retry unsent rows, publish on the exact allowed subject with the envelope event identifier as the broker deduplication identity, and mark a row sent only after broker acknowledgement.

#### Scenario: Crash before terminal publication
- **WHEN** Knowledge commits a terminal result and outbox row and stops before broker acknowledgement
- **THEN** restart republishes the same logical fact and downstream consumers observe no second logical terminal outcome

#### Scenario: Idle startup drains existing outbox
- **WHEN** Knowledge starts with unsent terminal rows and receives no new inbound event
- **THEN** the publisher drains those rows without waiting for a new analysis

#### Scenario: Broker uncertainty preserves publication intent
- **WHEN** a publish acknowledgement is lost or the broker disconnects during publication
- **THEN** the row remains retryable with the same message identity and is not falsely marked sent

### Requirement: Integrated acceptance proves all primary families and recovery boundaries
The workspace SHALL provide a task-namespaced, exact-SHA integration profile with real JetStream and Knowledge storage, a scripted analysis provider, a real Extractor document fixture, and canonical injected social, AI-archive, and repository facts. It SHALL label fixture proof separately from live producer, provider, deployment, and hosted-CI proof.

#### Scenario: Main families reach observable outcomes
- **WHEN** the profile publishes one valid fixture for each primary family
- **THEN** Knowledge records the expected receipt and work, produces the expected analysis and search state, and publishes each required terminal fact

#### Scenario: Restart and deletion matrix passes
- **WHEN** the profile exercises commit-before-ack redelivery, restart at each durable boundary, terminal publish uncertainty, social removal, AI-archive tombstone, and stale replay
- **THEN** no work is stranded, scripted idempotent provider calls and logical terminal facts are not duplicated, uncertain non-idempotent provider outcomes are surfaced, and deleted derived state is not resurrected

#### Scenario: Fixture proof is not overstated
- **WHEN** the profile injects a canonical event for a producer whose live publisher is not part of this change
- **THEN** the verification record identifies that evidence as contract/runtime fixture proof and does not claim live producer publication or deployment
