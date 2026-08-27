## Purpose

Defines replay-safe AI-archive facts that let Knowledge index normalized
conversation evidence and remove derived results only after authoritative
tombstone evidence.

## ADDED Requirements

### Requirement: Published archive facts carry independently verifiable provenance

The AI-archive contract SHALL publish `ai_archive.archive.imported.v1` and
conversation/project added/updated facts whose payloads link each subject to its
owning archive import and expose the immutable source-export digest/reference,
parser name/version, owner, provider, normalized content digest, and graph
revision required to validate the fact without reading a producer database.

#### Scenario: Contract fixture links normalized subjects to immutable archive evidence

- **WHEN** a consumer deserializes a valid imported-archive fixture and linked
  conversation-added and project-added fixtures
- **THEN** it can verify that the owner, provider, archive identity,
  source-export digest/reference, and parser identity agree, and that the
  conversation's content digest/graph record and the project's normalized
  content digest/record round-trip unchanged

#### Scenario: Added and updated facts converge under replay

- **WHEN** a consumer receives a duplicate conversation or project fact or an older
  revision after a newer one
- **THEN** it retains at most one current source head for that owner and
  subject and does not regress the current content digest or parser
  revision

### Requirement: Authoritative AI-archive tombstones are publishable facts

The AI-archive contract SHALL define a tombstone event for an archive or a
normalized conversation or project that carries its owner, provider, stable archive and
subject identities, deletion reason, immutable evidence reference, observed
time, and parser identity when a parser created the record.  The event SHALL
mean that only explicit provider deletion, compliance deletion, or approved
reconciliation evidence exists; absence from one snapshot SHALL NOT produce it.

#### Scenario: Tombstone fixture preserves authoritative deletion evidence

- **WHEN** a contract fixture represents an explicitly deleted conversation,
  project, or archive
- **THEN** a consumer can identify the exact owner and subject, verify its
  evidence reference and reason, and round-trip every payload member without
  treating a missing-snapshot observation as a tombstone

### Requirement: Knowledge removes only tombstoned derived archive state

Knowledge SHALL durably deduplicate each published AI-archive fact, queue or
advance analysis/search state from valid import, conversation, and project facts, and
remove or mark unavailable every analysis, embedding, and search projection
derived from exactly the tombstoned archive subject.  It SHALL retain no
producer-owned raw export bytes and SHALL leave other tenants and subjects
unchanged.

#### Scenario: Tombstone propagation removes one conversation from search

- **WHEN** Knowledge has an indexed conversation and receives its valid
  tombstone event
- **THEN** a subsequent authorized search cannot return that conversation's
  derived projection, all of its derived Knowledge state is unavailable, and
  an unrelated conversation remains searchable

#### Scenario: Tombstone propagation removes one project from search

- **WHEN** Knowledge has indexed a project and receives its valid project
  tombstone event
- **THEN** a subsequent authorized search cannot return that project's derived
  projection, while an unrelated project remains searchable

#### Scenario: Tombstone replay is idempotent

- **WHEN** Knowledge receives the same archive tombstone event more than once
- **THEN** the first delivery performs the scoped removal and later deliveries
  complete without recreating, double-removing, or affecting unrelated state

### Requirement: Contract rollout protects deletion propagation

The fleet SHALL publish the contract and compatible Knowledge tombstone
consumer before an archive producer emits a tombstone.  Producer and consumer
conformance gates SHALL exercise the published contract fixtures, event linkage
round-trip, and tombstone propagation before workspace pins advance.

#### Scenario: Producer rollout is blocked by an unavailable consumer

- **WHEN** the tombstone contract is published but the compatible Knowledge
  consumer gate has not passed
- **THEN** an archive producer does not enable tombstone publication and the
  workspace integration pin does not advance
