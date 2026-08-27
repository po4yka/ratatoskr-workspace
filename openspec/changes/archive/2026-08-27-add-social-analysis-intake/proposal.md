# Add the social-analysis intake spec

## Why

`ratatoskr-instagram` publishes social-source facts and `ratatoskr-knowledge` will analyse them, but no agreed interface says how a fact becomes an analysis request, how results link back, or how removals propagate. Without it, plan item 5 of the Instagram connector stays blocked: both repositories would have to guess the other's contract.

## What changes

Add one store spec, `social-analysis-intake`, binding both sides:

- captured/updated facts ARE the analysis requests; there is no separate command channel;
- results link back only through `(social_source_id, content_digest)`; a changed digest means a new run may supersede;
- `knowledge.analysis.completed.v1` has one published, typed, privacy-safe linkage payload: owner, `social_source_id`, `content_digest`, and completion instant only;
- `social.source.removed.v1` propagates deletion: consumers stop treating the source as analysable and remove derived artifacts per privacy policy; a removal never claims upstream deletion;
- producers publish nothing for captures that never produced preserved normalized content (unavailable-only records stay local until the contract can represent them truthfully).

## Repositories, in dependency order

| # | Repository | Deliverable | Merges |
|---|---|---|---|
| 1 | `ratatoskr-workspace/repos/contracts` | `social.source.removed.v1`, optional snapshot author, and typed `knowledge.analysis.completed.v1` linkage payload | first |
| 2 | this store | this change: the ratified interface spec | second |
| 3 | `ratatoskr-knowledge` | documentation alignment naming the real event names and citing this spec | third |
| 4 | `ratatoskr-social/instagram` | plan item 5 publisher implementing the producer side | last |

Knowledge's social analysis family remains its own later changeset against this spec; this change does not implement any consumer behaviour.

## What stays outside

Broker topology, NATS subject naming, Knowledge's internal run state machine, Instagram's outbox mechanics — each belongs to its owning repository.

## Rollback

None shipped by this change itself: it adds an agreement, not runtime behaviour. Repositories that implemented against it would revert through their own changes.
