## Implementation by repository

- [x] 1. `ratatoskr-contracts` — publish typed request/completion/failure payloads, fixtures, generated schemas, and compatibility baselines. Published at `b53fd76dce2a9e54de88d6a751bf22f3f4244fa3`.
- [x] 2. This store — ratify the shared `repository-analysis-intake` specification.
- [x] 3. `ratatoskr-knowledge` — implement durable request intake and terminal-linkage construction in the archived `repository-analysis-family-intake` change. Published at `b2097663ce36b1a70b14a264f8b2744b4a9466d5`.
- [x] 4. `ratatoskr-github` — implement plan item 9 in the archived `repository-watches-analysis` change. Published at `1d671bde3dc56ef9771c927d4a777fae968b0efa`.

## 1. Typed wire contract

- [x] 1.1 Add the GitHub contract package and its structural registration.
- [x] 1.2 Add and observe failing tests for immutable request, matching completion, and terminal failure shape.
- [x] 1.3 Implement the three payloads, safe failure vocabulary, fixtures, schemas, TypeScript, and compatibility baselines; run the contracts gate.

## 2. Knowledge consumer

- [x] 2.1 Create and archive the Knowledge OpenSpec change citing this capability.
- [x] 2.2 Add PostgreSQL coverage for redelivery, digest collision, matching completion, and final failure.
- [x] 2.3 Persist the request once, construct matching terminal facts once, and verify the Knowledge repository gate.

## 3. GitHub watch producer and projection

- [x] 3.1 Create and archive the GitHub OpenSpec change citing this capability.
- [x] 3.2 Add PostgreSQL red tests for watch registration, observed metadata delta, and completion linkage.
- [x] 3.3 Persist and rate-shape immutable request delivery, deduplicate revisions, consume terminal facts, retain the opaque result link, and verify the GitHub repository gate.

## 4. Store validation

- [x] 4.1 Validate this change strictly and archive it only after all producer and consumer commits are published.
