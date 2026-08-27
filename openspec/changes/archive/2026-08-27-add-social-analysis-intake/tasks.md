# Tasks: add-social-analysis-intake

## Implementation by repository

- [x] 1. `ratatoskr-workspace/repos/contracts` — publish `social.source.removed.v1`, optional snapshot author, and typed `knowledge.analysis.completed.v1`. Blocks 2–4: consumers cannot honour removal, authorless snapshots, or completion linkage without them.
- [x] 2. This store — this change's spec delta validated and merged to `openspec/specs/social-analysis-intake/spec.md`.
- [x] 3. `ratatoskr-knowledge` — documentation alignment naming the real event names and citing this spec (branch `feat/align-social-event-names`).
- [x] 4. `ratatoskr-social/instagram` — plan item 5 publisher implementing the producer side of this spec.

## 1. ratatoskr-workspace/repos/contracts

- [x] 1.1 Failing test `tests/events.rs::removed_payload_round_trips_through_envelope`: a `SocialSourceRemoved` set into an envelope comes back typed with event type `social.source.removed.v1`.
- [x] 1.2 Implement the payload, its closed `RemovalReason`, and crate export until it passes.
- [x] 1.3 Failing test `tests/snapshot_roundtrip.rs::snapshot_without_author_parses_and_reemits_absent`: an authorless snapshot parses and re-emits absent; implement optional `author`.
- [x] 1.4 Add failing test `tests/events.rs::social_source_analysis_completed_round_trips_through_envelope`; it must assert the completion payload's exact event type and `(owner, social_source_id, content_digest)` linkage fields.
- [x] 1.5 Implement and register `SocialSourceAnalysisCompleted`, regenerate schema/TypeScript artifacts, add valid/invalid/compat fixtures, extend invalid expectations, bless the API baseline, and run the repository gate.

## 2. This store

No failing test can precede a spec document; validation is the gate.

- [x] 2.1 `openspec validate --all --strict --store ratatoskr-workspace` passes with this change present.

## 3. ratatoskr-knowledge

Documentation cannot start from a failing test.

- [x] 3.1 `docs/ARCHITECTURE.md` section 16.2 names `social.source.captured.v1`, `social.source.updated.v1`, `social.source.removed.v1` and cites this store spec instead of restating it.

## 4. ratatoskr-social/instagram

Implemented under change `add-social-source-publishing` in that repository; its own tasks carry the test-first pairs. This item closes when that repository's gate is green on its default branch.

## Out of this change

Knowledge social analysis family implementation (its plan item 9, separate changesets against this spec); broker topology decisions.
