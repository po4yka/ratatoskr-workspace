## Purpose

Defines the fleet-owned bus topology and observable runtime boundary through which Knowledge durably accepts its primary document and analysis event families.

## ADDED Requirements

### Requirement: Platform owns an exact Knowledge consumer topology
Platform SHALL pre-provision one fixed pull consumer named `ratatoskr_knowledge_main` on `ratatoskr_events` with explicit acknowledgements, replay from the durable cursor, and filters exactly for:

- `evt.content.document.extracted.v1`;
- `evt.social.source.captured.v1`, `evt.social.source.updated.v1`, and `evt.social.source.removed.v1`;
- `evt.ai_archive.archive.imported.v1`, `evt.ai_archive.conversation.added.v1`, `evt.ai_archive.conversation.updated.v1`, `evt.ai_archive.project.added.v1`, `evt.ai_archive.project.updated.v1`, `evt.ai_archive.artifact.added.v1`, `evt.ai_archive.artifact.updated.v1`, and `evt.ai_archive.subject.tombstoned.v1`;
- `evt.knowledge.repository_analysis.requested.v1`.

Platform SHALL also pre-provision the existing `ratatoskr_knowledge_channel_recap` consumer on the command stream. Knowledge SHALL verify and open these fixed consumers but SHALL NOT create, delete, or repair them.

#### Scenario: Platform startup creates the missing topology
- **WHEN** Platform starts against streams that do not yet contain the fixed Knowledge consumers
- **THEN** it creates both consumers with their exact names, streams, filters, acknowledgement policy, and replay policy

#### Scenario: Matching topology is reused
- **WHEN** Platform starts again after the fixed consumers already exist with the required configuration
- **THEN** startup succeeds without resetting either durable cursor

#### Scenario: Topology drift is not concealed
- **WHEN** either fixed consumer exists with a different stream, filter set, acknowledgement policy, or replay policy
- **THEN** Platform and Knowledge refuse readiness and neither process mutates the mismatched consumer

### Requirement: Knowledge bus authority is least privilege
The Platform-owned Knowledge identity SHALL be permitted only to connect, inspect, fetch from, and acknowledge the two fixed Knowledge consumers, subscribe to its reply inbox, and publish the exact Knowledge terminal subjects `evt.knowledge.analysis.completed.v1`, `evt.knowledge.ai_archive_analysis.completed.v1`, `evt.knowledge.repository_analysis.completed.v1`, `evt.knowledge.repository_analysis.failed.v1`, and the existing channel-recap terminal subjects. It SHALL NOT create consumers, inspect or fetch from foreign consumers, subscribe directly to `evt.>` or `cmd.>`, publish source facts or arbitrary events, or administer streams.

#### Scenario: Required Knowledge operations are permitted
- **WHEN** the Knowledge identity opens each fixed consumer, fetches and acknowledges an allowed delivery, and publishes each allowed terminal subject
- **THEN** the broker authorizes those operations without production credentials appearing in repository files or test output

#### Scenario: Excess authority is denied
- **WHEN** the Knowledge identity attempts consumer creation, foreign-consumer access, broad event subscription, source-event publication, or stream administration
- **THEN** the broker denies the operation

### Requirement: Knowledge validates and durably admits every primary delivery
Knowledge SHALL accept only canonical envelopes delivered on the matching exact subject. Before durable admission it SHALL validate envelope version, event type, expected producer, tenant and aggregate relationships, payload identity, and payload contract. It SHALL durably record a collision-checking receipt and schedulable work before acknowledging the bus delivery.

#### Scenario: Valid delivery is acknowledged after commit
- **WHEN** a valid primary delivery arrives and Knowledge can commit its receipt and work atomically
- **THEN** Knowledge acknowledges the delivery only after the commit and the admitted work remains discoverable after restart

#### Scenario: Commit failure is retried by transport
- **WHEN** Knowledge cannot durably commit a valid primary delivery because of a transient storage failure
- **THEN** it does not acknowledge the delivery and requests bounded redelivery

#### Scenario: Permanent invalid delivery cannot block the cursor
- **WHEN** a delivery has a permanently invalid subject, envelope, producer, tenant relationship, aggregate relationship, or payload
- **THEN** Knowledge records a content-free rejection, terminates that delivery, creates no domain work, and can process the following valid delivery

#### Scenario: Event identifier collision is visible
- **WHEN** an existing event identifier is redelivered with different immutable subject or envelope content
- **THEN** Knowledge records a collision, refuses the conflicting fact, and does not treat it as a harmless duplicate

### Requirement: Primary-stream health participates in readiness
When primary event consumption is enabled for the deployable, Knowledge SHALL report ready only while storage is available, the broker connection is live, the exact fixed consumer is open, required content-resolution and analysis dependencies are usable, and all primary worker supervisors are running. A configured but unavailable dependency SHALL make readiness fail rather than silently disable the primary stream.

#### Scenario: Missing consumer keeps Knowledge unready
- **WHEN** Knowledge starts while `ratatoskr_knowledge_main` is absent or mismatched
- **THEN** liveness remains available for diagnosis but readiness returns unavailable and no replacement consumer is created

#### Scenario: Runtime disconnect changes readiness
- **WHEN** a ready Knowledge process loses its broker connection or a required primary worker exits
- **THEN** readiness becomes unavailable until the same configured topology and worker set are healthy again

### Requirement: Shutdown preserves unsettled primary work
Knowledge SHALL stop accepting new deliveries and work claims, settle completed admissions, negatively acknowledge or release any delivery that did not commit, stop outbox publication after its bounded drain, join every primary worker, and close storage last.

#### Scenario: Shutdown during an in-flight delivery
- **WHEN** Knowledge receives termination after fetching a primary delivery but before durable admission completes
- **THEN** the delivery remains eligible for redelivery and storage is not closed while a worker can still commit

#### Scenario: Shutdown after admission
- **WHEN** termination begins after a primary delivery has committed
- **THEN** the bus delivery may be acknowledged independently of analysis completion and the durable work resumes after restart
