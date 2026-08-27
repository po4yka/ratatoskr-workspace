# repository-analysis-intake Specification

## Purpose
Defines the durable boundary through which GitHub Catalog requests analysis of one immutable
repository revision and receives an auditable, privacy-safe terminal linkage from Knowledge.

## Requirements

### Requirement: A request identifies one immutable repository-analysis input

`knowledge.repository_analysis.requested.v1` SHALL identify the owner, the Catalog repository
identity, GitHub's stable numeric repository identity, the requested repository-analysis contract,
and one immutable source revision. The source revision SHALL contain a digest of the bounded
metadata snapshot and an explicit README state: either a content-addressed `BlobRef` for preserved
README bytes or a closed vocabulary value explaining why README bytes are absent. A request SHALL
not carry provider credentials, URLs that grant access, filesystem paths, raw README bytes, prompts,
or model configuration.

The metadata snapshot SHALL carry only the declared analysis inputs and SHALL bound text and list
fields. Its stable digest and README state SHALL be sufficient for a recipient to determine whether
two requests concern the same source revision without consulting Catalog storage.

#### Scenario: a request names an available README revision

- **WHEN** Catalog observes a watched repository whose preserved README bytes and metadata revision
  are available for analysis
- **THEN** it publishes one request naming the owner, both repository identities, the immutable
  metadata digest, and the README `BlobRef`

#### Scenario: a request represents an absent README truthfully

- **WHEN** Catalog observes a watched repository whose provider response establishes that no README
  is available
- **THEN** it publishes a request with the declared absent-README state and no synthetic content
  reference

### Requirement: Requests deduplicate by immutable input and requested contract

Catalog SHALL derive and persist an idempotency key from the owner, Catalog repository identity,
stable GitHub repository identity, immutable source-revision identity, and requested
repository-analysis contract. At-least-once delivery or repeated watch triggers with that same key
SHALL designate one outstanding request. A changed metadata digest, README state or digest, or
requested analysis contract SHALL designate a distinct request and SHALL NOT overwrite the earlier
request's terminal evidence.

#### Scenario: delivery is replayed

- **WHEN** the same `knowledge.repository_analysis.requested.v1` delivery is received more than once
- **THEN** Knowledge creates or resumes at most one analysis run for its idempotency key and Catalog
  retains one pending request rather than publishing a duplicate

#### Scenario: a later revision supersedes pending evidence

- **WHEN** a watched repository receives a request for a different immutable source revision while
  an earlier request remains pending
- **THEN** both requests remain auditable and Catalog exposes the newer revision as pending without
  treating a terminal fact for the older revision as the newer result

### Requirement: Knowledge emits terminal linkage facts without leaking analysis internals

After accepting a request, Knowledge SHALL emit exactly one terminal fact for each terminal outcome:
`knowledge.repository_analysis.completed.v1` for an accepted result or
`knowledge.repository_analysis.failed.v1` for a final failure. Each terminal fact SHALL echo the
request identity and immutable source-revision identity. A completion SHALL also carry an opaque
Knowledge-owned result reference; a failure SHALL carry only a stable, user-safe failure code and
its retryability, never raw provider output or credentials.

#### Scenario: a completion resolves its matching pending request

- **WHEN** Catalog receives a completion whose request and immutable revision identity match one of
  its outstanding requests
- **THEN** it marks only that request resolved and links the opaque result reference to that
  repository revision

#### Scenario: a stale completion arrives after a newer request

- **WHEN** Catalog receives a valid completion for an older revision after it has requested analysis
  of a newer revision
- **THEN** it retains the older result as revision evidence and keeps the newer request visibly
  pending

#### Scenario: a final failure does not remain pending forever

- **WHEN** Catalog receives a valid final-failure fact for an outstanding request
- **THEN** it resolves that request to a visible failed state using the stable failure code and
  retryability, without inventing a result reference

### Requirement: Catalog and Knowledge preserve ownership and admission boundaries

Catalog SHALL rate-shape only its outbound request production and SHALL keep an otherwise accepted
request visibly pending until a matching terminal fact arrives. Knowledge SHALL make all admission,
requeue, daily or monthly budget, model, retry, and result-retention decisions independently. A
request event SHALL not imply that Knowledge accepted inference work, and Catalog SHALL not infer a
completed analysis from delivery, timeout, or lack of a terminal event.

#### Scenario: Knowledge defers work for budget

- **WHEN** Knowledge receives a valid deduplicated request but its budget ledger defers admission
- **THEN** Catalog keeps the matching request pending and does not publish another request for the
  same idempotency key solely because no completion has arrived

### Requirement: Terminal facts are authenticated to the requested owner and revision

Catalog SHALL accept a terminal linkage fact only when its owner, Catalog repository identity,
stable GitHub repository identity, request identity, and immutable source-revision identity match a
locally persisted outstanding request. A terminal fact with any mismatch SHALL be retained or
rejected as invalid delivery according to Catalog's inbox policy and SHALL NOT change a repository's
visible pending or result linkage state.

#### Scenario: a completion targets a different repository

- **WHEN** a completion carries a request identity known to Catalog but names a different repository
  identity or source revision
- **THEN** Catalog does not resolve any pending request or link the result to either repository
