# Article analysis across repositories

## Purpose

Defines the repository-boundary guarantees for producing one versioned, validated article analysis
from immutable canonical Document IR without changing source ownership.

## Requirements

### Requirement: Article analysis is bound to immutable source evidence

Every article analysis SHALL name the source document identifier and content digest, the analysis
contract, prompt, context-builder, and model-policy versions, and the source block indexes used.
Knowledge SHALL consume the supplied Document IR and SHALL NOT fetch or read Extractor-owned tables.

#### Scenario: the source content changes

- **WHEN** the same source identifier arrives with a different Document IR content digest
- **THEN** Knowledge creates a distinct analysis run and preserves the prior result

### Requirement: The first result is strict and grounded

The first article-analysis result SHALL contain one bounded summary and a bounded list of key points.
Each key point SHALL reference at least one block index present in the supplied Document IR. Unknown
fields, out-of-range block references, and values outside the documented limits SHALL be rejected.

#### Scenario: a result cites a missing block

- **WHEN** a provider response contains a key point whose block index is absent from the source
- **THEN** the response is not accepted as an article-analysis result

### Requirement: Model output remains untrusted evidence

Knowledge SHALL store each raw response as an owned content-addressed blob before destructive parsing,
validate it independently, and record every attempt. At most one additional provider attempt SHALL be
allowed after the first, either for an eligible transient failure or for a repairable invalid result.

#### Scenario: one invalid response is repaired

- **WHEN** the first response is structurally repairable and the second response is valid
- **THEN** both attempts and raw blob references remain recorded and only the validated result succeeds

### Requirement: The first slice has no production inference side effect

Default tests and CI SHALL use a deterministic fake provider and SHALL require no provider credential,
network call, token charge, event publication, or search index.

#### Scenario: the repository gate runs without credentials

- **WHEN** the complete Knowledge test suite runs with no inference environment variable
- **THEN** article-analysis tests finish through the fake provider and make no external model request
