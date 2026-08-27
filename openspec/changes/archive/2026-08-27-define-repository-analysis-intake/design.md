## Context

See `proposal.md` for motivation and `specs/repository-analysis-intake/spec.md` for the boundary
behaviour. The current social-source interface treats a state-carried source fact as an analysis
request, but GitHub Catalog needs a separate request record because a watch trigger and a metadata
revision are not a portable source snapshot and Catalog must expose pending state. Existing
`knowledge.analysis.completed.v1` is social-source-specific and cannot be reused with a different
payload.

## Goals / Non-Goals

**Goals:**

- Publish typed, fixture-backed request and terminal-linkage payloads that let each service operate
  idempotently without cross-schema reads.
- Make revision identity and request identity explicit enough for Catalog to resolve pending state
  safely after replays, out-of-order deliveries, and later repository changes.
- Keep private content and Knowledge implementation details outside the event envelope.

**Non-Goals:**

- A source-blob transport or authorization protocol; `BlobRef` names immutable bytes but does not
  expose their location or grant access.
- Knowledge repository prompt/output design, budget implementation, or provider admission.
- GitHub watch, metadata, outbox, inbox, or notification implementation.

## Decisions

### D1: Use one typed request and two source-specific terminal facts

`knowledge.repository_analysis.requested.v1`,
`knowledge.repository_analysis.completed.v1`, and
`knowledge.repository_analysis.failed.v1` are distinct event types in a new GitHub-domain contract
crate. This avoids assigning a second incompatible payload to the already social-specific
`knowledge.analysis.completed.v1`, and lets failures be terminal without fabricating a result.
The existing generic-looking event name is therefore not an alternative.

### D2: Identity is composite and revision-based

The request carries both the Catalog UUID and GitHub numeric repository ID: the former routes a
completion to Catalog's record, while the latter preserves the provider-stable identity across
rename and transfer. A canonical immutable source-revision digest plus the requested contract
forms the durable deduplication identity. The opaque request ID provides direct correlation, but a
consumer must verify the composite identity before changing state.

### D3: Small declared metadata travels; README uses a content reference

The contract contains only bounded, named repository metadata fields needed by the analysis family.
README bytes stay behind `BlobRef`, including its digest, media type and byte length. This avoids
replaying private content through an event broker while allowing the future owner-approved blob
transport to prove the exact bytes analysed. If a README is absent, a closed absence reason is part
of the immutable revision rather than a missing field that could mean either unknown or omitted.

### D4: The terminal result is an opaque reference

Knowledge sends an opaque `EntityRef` result reference only after a result becomes accepted. Catalog
stores that reference and status but never receives a Knowledge run ID, prompt, raw response, or
analysis JSON. This preserves Knowledge ownership while satisfying the visible result-linkage
requirement.

### D5: Rollout is contracts, consumers, then producer

`ratatoskr-contracts` publishes the typed package and schemas first. Knowledge then deploys a
tolerant inbox and terminal emitter before GitHub emits requests. GitHub consumer support for
terminal facts can deploy before its producer. This permits safe replay and rollback: an unpublished
request event produces no external work, while a deployed consumer keeps understanding retained
terminal facts until its inbox retention expires.

## Risks / Trade-offs

[A `BlobRef` has no transport in this change] → Repository analysis remains gated on the separate
owner-authorized blob access path; this definition never turns a digest into an implicit storage API.

[A completion is replayed or arrives out of order] → Catalog matches request and revision identity
transactionally and preserves superseded evidence instead of rewriting the current linkage.

[A Knowledge budget defers work indefinitely] → Pending remains an honest state; only Knowledge can
admit, cancel, or fail the request, so Catalog does not duplicate it.

[The event includes private repository metadata] → Classification, bounded fields, tenant binding,
and `BlobRef` rather than raw README bytes keep the boundary minimal; contracts fixtures must use
synthetic data.

## Migration Plan

1. Add the typed contracts, schemas, fixtures, and compatibility baselines in `ratatoskr-contracts`.
2. Ratify this store specification.
3. Implement and deploy Knowledge's tolerant request consumer and terminal publisher.
4. Implement Catalog's terminal consumer and pending projection, then enable its request producer.
5. If a rollout is stopped, disable Catalog request publication; retain and consume terminal facts
   for existing requests until the relevant inbox retention has elapsed.
