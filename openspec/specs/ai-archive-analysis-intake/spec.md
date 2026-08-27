# ai-archive-analysis-intake Specification

## Purpose
Defines the v1 exchange between AI-archive producers and Knowledge for normalized facts,
conversation analysis/search, revision linkage, and authoritative tombstones without transferring
raw archive bytes.

## Requirements

### Requirement: AI-archive facts carry independently usable provenance

`ratatoskr-ai-archive-contracts` SHALL define state-carried facts named
`ai_archive.archive.imported.v1`, `ai_archive.project.added.v1`,
`ai_archive.project.updated.v1`, `ai_archive.conversation.added.v1`,
`ai_archive.conversation.updated.v1`, `ai_archive.artifact.added.v1`, and
`ai_archive.artifact.updated.v1`. Each subject fact SHALL carry its complete normalized subject
and the immutable import provenance containing owner, archive id, raw export digest, and parser
name/version. A consumer SHALL be able to admit one fact without a prior import event, and no fact
SHALL embed raw export bytes or credentials.

#### Scenario: an updated Artifact arrives without its import event

- **WHEN** Knowledge receives a valid `ai_archive.artifact.updated.v1` envelope after missing all
  earlier archive events
- **THEN** it records the tenant, archive, Artifact, export digest, parser provenance, and current
  Artifact receipt without retrieving the raw export

### Requirement: Conversation analysis and linkage are revision-specific

Knowledge SHALL admit a valid conversation fact into its durable analysis inbox, create its normal
analysis and search projection, and emit `knowledge.ai_archive_analysis.completed.v1` only for the
exact owner, archive, conversation id, and normalized-content digest it accepted. The archive
producer SHALL link that completion only to a previously published revision with those same values.
Knowledge-derived identifiers SHALL NOT be stored in archive state.

#### Scenario: a published conversation reaches search and links its completion

- **WHEN** Knowledge accepts one valid `ai_archive.conversation.added.v1` envelope and analysis
  completes
- **THEN** its search projection exists and the resulting completion links only to that
  conversation revision in Claude Archive

### Requirement: Explicit tombstones remove derived Knowledge data without deleting archive evidence

`ratatoskr-ai-archive-contracts` SHALL define `ai_archive.subject.tombstoned.v1` as a typed,
state-carried tombstone fact carrying owner, archive id, subject kind and id, reason, immutable
deletion evidence reference, and observed time. On receiving it, Knowledge SHALL remove derived
analysis, embedding, and search data for an affected conversation and suppress an older
conversation delivery. The removal SHALL NOT delete producer-owned raw evidence or imply a
deletion beyond the tombstone reason.

#### Scenario: a tombstoned conversation is absent from search

- **WHEN** Knowledge accepts `ai_archive.subject.tombstoned.v1` for a conversation with a search
  projection
- **THEN** subsequent searches omit the conversation and an older delivery cannot recreate its
  analysis, embeddings, or search projection

### Requirement: Snapshot absence is not a tombstone fact

Producers SHALL emit `ai_archive.subject.tombstoned.v1` only from explicit provider deletion,
Compliance deletion, or approved reconciliation-policy evidence. They SHALL NOT emit it merely
because a later personal or organization export omits a subject.

#### Scenario: a later partial export omits a prior project

- **WHEN** a producer receives a later export that omits a prior project without explicit deletion
  evidence
- **THEN** it emits no tombstone fact and Knowledge retains existing derived data subject to its
  normal availability policy
