## Why

Plan item 8 of the extractor's implementation plan calls for an isolated browser worker and a
strict escalation policy, and the extractor's design names Chromium behind a BrowserRenderer. The
contract between the two deployables is behaviour both can see, so it belongs in this store before
either side implements it.

## What Changes

- Define `browser-rendering`: durable render commands (`cmd.content.render.requested.v1`), owned
  BlobRef evidence on completion or a typed failure event, per-job context isolation with denied
  credentials and blocked heavy subresources, worker-side SSRF revalidation of every navigation
  hop, end-to-end budgets, and a deterministic extractor-side escalation policy that reuses the
  ordinary HTML path on the returned DOM.
- Fix rollout order: this contract first, then the browser-worker deployable, then extractor
  escalation wiring.

## Capabilities

### New Capabilities

- `browser-rendering`

## Impact

Consumers: ratatoskr-extractor (escalation producer, result consumer) and the browser-worker
deployable (command consumer, evidence producer). No existing capability changes; blob-references
governs how the rendered DOM bytes are announced.
