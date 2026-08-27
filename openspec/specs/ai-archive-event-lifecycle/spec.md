# AI archive event lifecycle across repositories

## Purpose

Defines replay-safe AI-archive facts that let Knowledge index normalized conversation evidence.

Knowledge removes derived results only after authoritative tombstone evidence.

## Requirements

### Requirement: Published archive facts carry independently verifiable provenance

The AI-archive contract SHALL publish `ai_archive.archive.imported.v1` and conversation/project added/updated facts that link every subject to its owning import and expose immutable export reference, parser name/version, owner, provider, normalized content digest, and graph revision without requiring a producer-database read.

#### Scenario: Contract fixture links normalized subjects to immutable archive evidence

- **WHEN** a consumer deserializes a valid imported-archive fixture and linked conversation-added and project-added fixtures
- **THEN** it verifies owner, provider, archive identity, source-export reference, parser identity, and normalized content records agree and round-trip

#### Scenario: Added and updated facts converge under replay

- **WHEN** a consumer receives a duplicate fact or an older revision after a newer conversation or project fact
- **THEN** it retains at most one current source head and does not regress content digest or parser revision

### Requirement: Authoritative AI-archive tombstones are publishable facts

The AI-archive contract SHALL define a tombstone event for an archive, conversation, or project carrying owner, provider, stable archive and subject identities, deletion reason, immutable evidence reference, observed time, and parser identity when a parser created the record. It SHALL mean only that explicit provider deletion, compliance deletion, or approved reconciliation evidence exists; absence from one snapshot SHALL NOT produce it.

#### Scenario: Tombstone fixture preserves authoritative deletion evidence

- **WHEN** a contract fixture represents an explicitly deleted conversation, project, or archive
- **THEN** a consumer identifies the exact owner and subject, verifies its evidence reference and reason, and round-trips the payload without treating a missing snapshot as a tombstone

### Requirement: Knowledge removes only tombstoned derived archive state

Knowledge SHALL durably deduplicate published AI-archive facts, queue or advance analysis/search state from valid import, conversation, and project facts, and remove or mark unavailable every analysis, embedding, and search projection derived from exactly the tombstoned subject. It SHALL retain no producer-owned raw export bytes and SHALL leave other tenants and subjects unchanged.

#### Scenario: Tombstone propagation removes one conversation from search

- **WHEN** Knowledge has an indexed conversation and receives its valid tombstone event
- **THEN** an authorized search cannot return that conversation's derived projection and an unrelated conversation remains searchable

#### Scenario: Tombstone propagation removes one project from search

- **WHEN** Knowledge has an indexed project and receives its valid project tombstone event
- **THEN** an authorized search cannot return that project's derived projection while an unrelated project remains searchable

#### Scenario: Tombstone replay is idempotent

- **WHEN** Knowledge receives the same archive tombstone event more than once
- **THEN** the first delivery performs scoped removal and later deliveries complete without recreating, double-removing, or affecting unrelated state

### Requirement: Contract rollout protects deletion propagation

The fleet SHALL publish the contract and compatible Knowledge tombstone consumer before an archive producer emits a tombstone. Producer and consumer conformance gates SHALL exercise published contract fixtures, event linkage round-trip, and tombstone propagation before workspace pins advance.

#### Scenario: Producer rollout is blocked by an unavailable consumer

- **WHEN** the tombstone contract is published but the compatible Knowledge consumer gate has not passed
- **THEN** an archive producer does not enable tombstone publication and the workspace integration pin does not advance
