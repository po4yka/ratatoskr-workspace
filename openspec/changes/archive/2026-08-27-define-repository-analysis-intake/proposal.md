## Why

`ratatoskr-github` must request repository analyses when a watched repository changes, but
`ratatoskr-knowledge` has not implemented its repository family and no published contract says
which immutable revision it may analyse or how a completion resolves Catalog's visible pending
state. Implementing either service now would make one side invent the other's wire contract.

## What Changes

- Define the `repository-analysis-intake` cross-repository contract for an immutable GitHub
  repository revision, a deduplicated analysis request, and a terminal result linkage fact.
- Require every request to name the Catalog repository identity, GitHub's stable numeric identity,
  the exact metadata revision and README/content reference or digest, the owner, and an
  idempotency key derived from that immutable input.
- Require completions and failures to echo the request identity and immutable revision identity so
  Catalog can resolve only the matching pending request without storing a Knowledge-owned run or
  result body.
- Keep admission, cost budgets, model choice, analysis output, and requeue policy inside
  `ratatoskr-knowledge`; Catalog rate-shapes only its outbound requests.

## Capabilities

### New Capabilities

- `repository-analysis-intake`: Contractual request, idempotency, terminal linkage, supersession,
  and privacy guarantees between GitHub Catalog and Knowledge repository analysis.

### Modified Capabilities

- None.

## Repositories, in dependency order

| # | Repository | Deliverable | Merges |
|---|---|---|---|
| 1 | `ratatoskr-workspace/repos/contracts` | Typed request/completion/failure payloads, fixtures, generated schemas, and package publication | first |
| 2 | this store | This change's ratified `repository-analysis-intake` specification | second |
| 3 | `ratatoskr-knowledge` | Repository-analysis family consumes requests, owns budgets and result bodies, then emits terminal linkage facts | third |
| 4 | `ratatoskr-github` | Plan item 9 watch producer, outbound rate shaping, and pending/result linkage projection | last |

## What stays outside

Knowledge's prompt, model policy, budget ledger, output schema, embeddings, and search projection;
GitHub's watch storage and metadata-refresh mechanics; broker topology; and notification delivery.

## Rollback

No runtime behaviour ships with this contract definition. Before a producer is deployed, the change
can be reverted as one store/contracts change. After deployment, consumers must remain tolerant of
already-recorded terminal facts until their own retained inbox and pending projections have drained.

## Impact

This introduces an internal contract shared by `ratatoskr-contracts`, `ratatoskr-knowledge`, and
`ratatoskr-github`. It deliberately does not expose GitHub credentials, raw private README content,
Knowledge prompts, model output, or Knowledge database identifiers on the event boundary.
