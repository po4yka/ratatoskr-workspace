## 1. Implementation by repository — ratatoskr-contracts

- [x] 1.1 RED: add provenance and authoritative-tombstone fixture coverage in
  `crates/ai-archive-contracts/tests/events.rs` and
  `tests/compat_fixtures.rs`; focused tests failed because the prior contract
  lacked standalone import provenance and tombstone payloads.
- [x] 1.2 Implement conversation/project provenance members, typed
  `ai_archive.project.added.v1`/`ai_archive.project.updated.v1` and
  `ai_archive.subject.tombstoned.v1` payloads, validation, schema and
  compatibility fixtures; focused tests and the Contracts gate are green.
  Published directly to `main` as `9b700fc` after the user-authorized contract
  expansion.

## 2. Implementation by repository — ratatoskr-knowledge

- [x] 2.1 RED: in `crates/knowledge/tests/source_inbox.rs`, add
  `archive_tombstone_is_deduplicated_and_scoped` and project-tombstone coverage; run it against the
  published contract revision; confirm it fails because the inbox cannot
  validate or persist an archive tombstone receipt.
- [x] 2.2 Implement contract-validated archive tombstone admission and its
  durable idempotency receipt; the focused inbox test and the Knowledge gate
  are green. Published directly to `main` as `efdae94`, `3691e8e`, and
  `6981a7f`.
- [x] 2.3 RED: add archive project pipeline and deletion-propagation coverage;
  the focused tests initially failed because archive-derived state was neither
  identified by archive source nor removed on an authoritative tombstone.
- [x] 2.4 Implement the transactionally scoped removal/unavailability of
  conversation/project-derived source, analysis, projection, and embedding state while
  retaining producer-owned blobs; focused deletion and project-analysis tests
  plus the Knowledge gate are green.

## 3. Implementation by repository — ratatoskr-chatgpt

- [x] 3.1 RED: add normalized-event contract-fixture coverage; the initial
  focused tests failed because the archive had no contract conversion or outbox
  publication.
- [x] 3.2 Pin the published AI-archive contracts revision and implement
  normalized import/conversation/project conversion plus transactional outbox enqueue;
  fixture round-trip tests and the ChatGPT gate are green. Published directly
  to `main` as `381b530` and `ec9f83d`.
- [x] 3.3 Implement explicit-tombstone conversion and enqueue without deriving
  deletion from a missing snapshot; the tombstone round-trip and full ChatGPT
  gate are green.

## 4. Fleet integration

- [x] 4.1 Pin direct consumers and producers to published Contracts revision
  `9b700fc4de2a0f8c4d61115aaa563dd999dca18b`; fixture conformance, provenance
  linkage round-trip, and archive-scoped deletion propagation are green across
  the pinned revisions. Cannot start from a failing test: this is a
  cross-repository release-evidence update. The user explicitly authorized
  direct integration to `main` rather than pull requests.
