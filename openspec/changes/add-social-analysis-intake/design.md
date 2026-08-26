# Design: add-social-analysis-intake

## Context

The published social contract (capability `social-source-contracts` in `ratatoskr-workspace/repos/contracts`) defines the facts; this spec defines only the boundary behaviour between producers and analysers. The Instagram connector's change `add-social-source-publishing` records the same agreement from the producer side as design note D6 and defers to this store spec once it exists.

## Goals / Non-Goals

Goals: make plan item 5 implementable by fixing request semantics, linkage keys, and deletion propagation at the boundary.

Non-Goals: Knowledge's analysis family internals; producer storage shapes; transport.

## Decisions

### D1: Facts are requests (no command channel)

State-carried facts already carry everything an analyser needs; a separate `analysis.requested` command would duplicate identity and ordering for no capability. Matches the article-analysis precedent, where runs are created from supplied evidence.

### D2: Linkage is `(social_source_id, content_digest)`

Identity alone cannot distinguish "same source, new content" — digest does. Both values already exist in every snapshot, so neither side needs new identifiers. Producers never store consumer-side ids, keeping ownership one-directional.

### D3: Removal is stop-analysing plus policy-driven derived-data removal

The contract's removed fact is about the library, not the provider. Consumers honour privacy by dropping derived artifacts; they do not touch producer records, and nothing implies upstream state.

## Risks / Trade-offs

[A redelivery after a removal resurrects a run] → consumers key runs idempotently and check removal state before creating derived data; the spec pins this via the second removal scenario.

[Digest churn creates run storms] → re-resolution that changes normalized content legitimately means new evidence; rate/budget controls stay inside the analysing service.

## Open Questions

None.
