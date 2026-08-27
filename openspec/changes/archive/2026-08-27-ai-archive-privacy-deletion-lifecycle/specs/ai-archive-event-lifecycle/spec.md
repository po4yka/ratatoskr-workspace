## MODIFIED Requirements

### Requirement: Authoritative AI-archive tombstones are publishable facts

The AI-archive contract SHALL define a tombstone event for an archive, conversation, project, or artifact carrying owner, provider, stable archive and subject identities, deletion reason, immutable evidence reference, observed time, and parser identity when a parser created the record. Its closed reason vocabulary SHALL include explicit provider deletion, compliance deletion, approved reconciliation evidence, and authorized owner-requested privacy deletion. Absence from one snapshot SHALL NOT produce a tombstone.

#### Scenario: Tombstone fixture preserves authoritative deletion evidence

- **WHEN** a contract fixture represents an explicitly deleted conversation, project, archive, or artifact
- **THEN** a consumer identifies the exact owner and subject, verifies its evidence reference and reason, and round-trips the payload without treating a missing snapshot as a tombstone

#### Scenario: Owner-requested privacy deletion has an exact reason

- **WHEN** an authorized owner privacy request makes an archive subject unavailable
- **THEN** the producer emits the existing `ai_archive.subject.tombstoned.v1` fact with `reason = "user_requested"` and non-sensitive immutable deletion evidence rather than relabeling the request as provider, compliance, or reconciliation evidence

### Requirement: Knowledge removes only tombstoned derived archive state

Knowledge SHALL durably deduplicate published AI-archive facts, queue or advance analysis/search state from valid import, conversation, and project facts, and remove or mark unavailable every analysis, embedding, and search projection derived from exactly the tombstoned subject. It SHALL retain no producer-owned raw export bytes and SHALL leave other tenants and subjects unchanged, including when the reason is `user_requested`.

#### Scenario: Tombstone propagation removes one conversation from search

- **WHEN** Knowledge has an indexed conversation and receives its valid tombstone event
- **THEN** an authorized search cannot return that conversation's derived projection and an unrelated conversation remains searchable

#### Scenario: Tombstone propagation removes one project from search

- **WHEN** Knowledge has an indexed project and receives its valid project tombstone event
- **THEN** an authorized search cannot return that project's derived projection while an unrelated project remains searchable

#### Scenario: Tombstone replay is idempotent

- **WHEN** Knowledge receives the same archive tombstone event more than once
- **THEN** the first delivery performs scoped removal and later deliveries complete without recreating, double-removing, or affecting unrelated state

#### Scenario: User-requested tombstone uses the same scoped deletion path

- **WHEN** Knowledge receives a valid `user_requested` tombstone for one conversation while another conversation of the same tenant is indexed
- **THEN** every derived row for the named conversation is unavailable, the sibling conversation remains searchable, and replay creates no additional deletion

### Requirement: Contract rollout protects deletion propagation

The fleet SHALL publish the additive tombstone contract and deploy a compatible Knowledge consumer before an archive producer emits `user_requested`. Contract, consumer, and producer conformance gates SHALL exercise the new fixture, event linkage round-trip, scoped tombstone propagation, and replay before workspace verification records the compatible snapshot.

#### Scenario: Producer rollout is blocked by an unavailable consumer

- **WHEN** the additive tombstone contract is published but the compatible Knowledge consumer gate has not passed
- **THEN** ChatGPT Archive does not enable `user_requested` tombstone publication and workspace verification does not claim a compatible snapshot

#### Scenario: Published privacy deletion is not rolled back into visibility

- **WHEN** a `user_requested` tombstone has been published and producer rollout is stopped
- **THEN** the compatible Knowledge consumer remains able to replay the fact and deleted derived state is not recreated
