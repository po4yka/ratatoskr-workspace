# fleet-ingest-redelivery Specification

## Purpose
TBD - created by archiving change xr-021-fleet-round-4. Update Purpose after archive.

## Requirements

### Requirement: A retryable ingest failure is redelivered without a budget

Knowledge SHALL settle a transient failure of the documents family, the social family (a capture and a removal) and the AI-archive family (a tombstone and every other fact) by redelivering the message, with a delay of `min(2 s * 2^(delivered - 1), 60 s)`, for as long as the failure lasts, and SHALL NOT terminate it after a number of deliveries. A failure that can never succeed by redelivery (an undecodable message, a payload the contract refuses) SHALL be rejected with a closed class at its first delivery. Each error variant that maps to a retry SHALL be decided one by one as redeliverable or rejected, with a test.

#### Scenario: A fault longer than any former budget

- **WHEN** provider transient errors followed by a PostgreSQL outage last at least eight deliveries for a document, a social capture, a social removal and an AI-archive conversation
- **THEN** each fact is applied once after the fault clears, with no Term and no dead-letter row, verified against a real broker and PostgreSQL by the ingest tests of `ratatoskr-knowledge` and flow F2 of the native smoke when it is run

#### Scenario: An undecodable message

- **WHEN** a message that is not an envelope arrives
- **THEN** it is terminated at its first delivery and does not block the durable

### Requirement: The repository family keeps a bounded budget

Knowledge SHALL keep the bounded delivery budget for the repository-analysis request family, because its terminal delivery settles a `knowledge.repository_analysis.failed.v1` fact that the requester waits for, and the constant and its documentation SHALL say so.

#### Scenario: A repository request that cannot be analysed

- **WHEN** a repository request fails transiently on every delivery
- **THEN** it ends in its failed fact at the fifth delivery

### Requirement: Redelivery is visible and nothing is dead-lettered into a table

Knowledge SHALL log a WARN on every redelivery from the second on, carrying the family, the class and the delivery count and never content, and SHALL expose a label-free counter `knowledge_ingest_redeliveries_total` on the operator listener beside the recap redelivery counter. The `knowledge.ingest_failures` table SHALL NOT exist.

#### Scenario: Redeliveries are counted

- **WHEN** a delivery is redelivered during an outage
- **THEN** the counter is above zero on the operator listener and the schema has no `ingest_failures` table, verified by the schema tests of `ratatoskr-knowledge`
