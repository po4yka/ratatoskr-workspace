## Purpose

Defines the privacy-safe import completeness summary that archive services expose to clients through
the existing Platform operation snapshot, without embedding archive content or parser details.

## ADDED Requirements

### Requirement: Terminal archive import results carry a bounded summary
An AI archive producer that reports a terminal successful or partially successful import SHALL add
one result with `result_kind` `ai_archive.import`, an `ai_archive:<uuid>` target, and a typed
`ai_archive_import_summary` object. The object SHALL contain the target archive id, provider,
completeness classification, conversation/message/asset/gap counts, warning count, and an optional
report reference. It SHALL NOT contain archive content, titles, local paths, provider identifiers,
credentials, raw parser diagnostics, or individual gap/warning text.

#### Scenario: Complete import result is readable from its operation
- **WHEN** an archive producer reports a succeeded import with a complete completeness report
- **THEN** a client reading the Platform operation receives an `ai_archive.import` result whose
  summary declares `complete` and has a zero gap count

#### Scenario: Import with gaps remains explicit
- **WHEN** an archive producer reports a terminal import whose completeness is not `complete`
- **THEN** the result summary carries that exact classification and a non-zero gap count

### Requirement: Consumers do not infer a missing summary
A client SHALL use the summary only when it is present and structurally valid for the matching
`ai_archive.import` target. A terminal operation that lacks a valid summary SHALL remain an
unverified backend result, not a complete or gap-free import.

#### Scenario: Older producer omits the additive summary
- **WHEN** a client reads a succeeded archive-import operation without an
  `ai_archive_import_summary`
- **THEN** the client reports that details are unavailable and does not present import completeness
