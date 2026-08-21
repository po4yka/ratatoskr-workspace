## Why

Extractor now publishes stable Document IR, but no service can turn it into a validated, reproducible
analysis. Knowledge needs its first bounded article-analysis slice before a real model provider or
search index is introduced.

## What Changes

- Establish the first article-analysis result contract, source identity rules, prompt and context
  versioning, durable execution states, raw-response evidence, and bounded validation repair.
- Implement the slice in `ratatoskr-knowledge` with a deterministic fake provider and no production
  inference credentials.
- Use the existing Document IR and `BlobRef` contracts without changing their wire shape.
- Roll out `ratatoskr-knowledge` after the already published contracts. Roll back by stopping the new
  service and deleting its disposable development schema and owned blobs; no prior production data
  or consumer exists.
- Keep real providers, events, search, embeddings, indexing, backfill, and deployment outside this
  change.

## Capabilities

### New Capabilities

- `article-analysis`: Cross-repository expectations for consuming immutable Document IR and producing
  a versioned, validated, provenance-preserving article analysis.

### Modified Capabilities

None.

## Impact

`ratatoskr-knowledge` is the only repository changed by implementation. It consumes the existing
`ratatoskr-contracts` Document IR and identifier packages at their published commit; contracts merge
first only as an already satisfied dependency. There is no database migration, public event, client
consumer, reanalysis, or cost impact in this fake-provider slice.
