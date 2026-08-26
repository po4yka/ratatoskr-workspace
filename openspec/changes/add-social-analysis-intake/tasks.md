# Tasks: add-social-analysis-intake

## Implementation by repository

- [ ] 1. `ratatoskr-workspace/repos/contracts` — publish `social.source.removed.v1` and the optional snapshot author (branch `feat/social-source-removed-event`). Blocks 2–4: consumers cannot honour removal or authorless snapshots without it.
- [ ] 2. This store — this change's spec delta validated and merged to `openspec/specs/social-analysis-intake/spec.md`.
- [ ] 3. `ratatoskr-knowledge` — documentation alignment naming the real event names and citing this spec (branch `feat/align-social-event-names`).
- [ ] 4. `ratatoskr-social/instagram` — plan item 5 publisher implementing the producer side of this spec.

## 1. ratatoskr-workspace/repos/contracts

- [ ] 1.1 Failing test `tests/events.rs::removed_payload_round_trips_through_envelope`: a `SocialSourceRemoved` set into an envelope comes back typed with event type `social.source.removed.v1`.
- [ ] 1.2 Implement the payload, its closed `RemovalReason`, and crate export until it passes.
- [ ] 1.3 Failing test `tests/snapshot_roundtrip.rs::snapshot_without_author_parses_and_reemits_absent`: an authorless snapshot parses and re-emits absent; implement optional `author`.
- [ ] 1.4 Register both edits (registry, contracts.toml), regenerate schema/TypeScript pair, add fixtures in both compat directions, extend invalid expectations, bless the API baseline, run the repository gate.

## 2. This store

No failing test can precede a spec document; validation is the gate.

- [ ] 2.1 `openspec validate --all --strict --store ratatoskr-workspace` passes with this change present.

## 3. ratatoskr-knowledge

Documentation cannot start from a failing test.

- [ ] 3.1 `docs/ARCHITECTURE.md` section 16.2 names `social.source.captured.v1`, `social.source.updated.v1`, `social.source.removed.v1` and cites this store spec instead of restating it.

## 4. ratatoskr-social/instagram

Implemented under change `add-social-source-publishing` in that repository; its own tasks carry the test-first pairs. This item closes when that repository's gate is green on its default branch.

## Out of this change

Knowledge social analysis family implementation (its plan item 9, separate changesets against this spec); broker topology decisions; Instagram tombstone storage (producer-side follow-up change once 7.x scope lands).
