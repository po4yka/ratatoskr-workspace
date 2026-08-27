## Implementation by repository

### 1. ratatoskr-contracts (merged first)

- [x] 1.1 Add failing conformance coverage for project/Artifact lifecycle facts and tombstones.
- [x] 1.2 Publish the v1 state-carried project/Artifact, tombstone, and archive-analysis completion
  contracts with JSON-schema fixtures at `51065776ac53be391d6a0a6295465e7d002a3477`.

### 2. ratatoskr-knowledge (merged second)

- [x] 2.1 Add failing fixture-driven tests for archive receipt, analysis/search, completion, and
  tombstone removal.
- [x] 2.2 Admit all lifecycle envelopes, retain project/Artifact receipts, analyse conversation
  facts, and delete/suppress derived conversation data on tombstone.
- [x] 2.3 Run the Knowledge repository gate against its disposable PostgreSQL database.

### 3. ratatoskr-claude (merged after Knowledge)

- [x] 3.1 Add failing contract-fixture, provenance, linkage, and tombstone publication tests.
- [x] 3.2 Persist complete envelopes in the Claude transactional outbox and enforce full import
  provenance for its normalized subjects.
- [x] 3.3 Validate and persist only exact Knowledge completion envelopes for published revisions.
- [x] 3.4 Run the Claude repository gate against its disposable PostgreSQL database.

### 4. ratatoskr-workspace (merged last)

- [x] 4.1 Validate the contract-to-Knowledge-to-Claude lifecycle and its deletion propagation in
  the repository integration tests.
- [x] 4.2 Record the rollout order and rollback boundary in this design; ChatGPT remains a
  non-publisher until it takes an equivalent producer change.
