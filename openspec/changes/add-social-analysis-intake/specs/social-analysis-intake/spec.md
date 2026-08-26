## ADDED Requirements

### Requirement: A social-source fact is itself the analysis request

Consumers that analyse social sources SHALL create their analysis runs from received `social.source.captured.v1` and `social.source.updated.v1` facts alone, keyed idempotently by the snapshot's `social_source_id` plus `content_digest`. There SHALL be no separate command channel from a producing service into an analysing service.

#### Scenario: one digest creates one run

- **WHEN** a consumer receives a captured fact and then redeliveries of the same fact
- **THEN** exactly one analysis run exists for that `social_source_id` and `content_digest`

### Requirement: Results link back through identity plus content digest

Every analysis-completion fact about a social source SHALL name the `social_source_id` it analysed and the `content_digest` of the snapshot analysed. Producing services SHALL link results to their own records using only these two values; a result whose digest differs from the record's current normalized state SHALL be treated as superseded evidence, never merged silently.

#### Scenario: a changed digest supersedes without erasing

- **WHEN** a source's normalized record changes and a new run completes while the older result still exists
- **THEN** both results remain retrievable with their own digests, and consumers read the newest digest as current

#### Scenario: linkage needs no shared identifiers

- **WHEN** a producer matches a completion fact against its stored records
- **THEN** the match uses `social_source_id` and `content_digest` only, with no Knowledge-side identifier written into producer storage

### Requirement: Removal propagates as stop-analysing, not as upstream deletion

Upon receiving `social.source.removed.v1`, consumers SHALL stop treating the named source as analysable for its owner and SHALL remove derived artifacts (analyses, embeddings, index entries) per privacy policy. A removal fact SHALL NOT be interpreted as the provider deleting the post, and SHALL NOT delete any producer-owned source record.

#### Scenario: a user-requested deletion clears derived data

- **WHEN** a consumer receives a removed fact carrying `reason = "user_requested"`
- **THEN** analyses and embeddings for that `social_source_id` become unavailable to the product and are deleted or tombstoned per policy

#### Scenario: removal does not touch the provider record

- **WHEN** a removed fact is processed for a source the producer still stores as a tombstoned local record
- **THEN** no consumer event, retry, or re-analysis recreates derived data for that owner and source

### Requirement: Unavailable-only captures publish nothing

A producer SHALL NOT emit any social-source fact for a capture whose resolution ended without preserved normalized content, because today's published snapshot cannot represent such a record truthfully. Such records stay local until a contract change makes them representable.

#### Scenario: an unavailable fallback stays local

- **WHEN** a capture's resolution ends in an unavailable fallback
- **THEN** no captured, updated, or removed fact exists downstream for it, and no analysing service holds derived data for it
