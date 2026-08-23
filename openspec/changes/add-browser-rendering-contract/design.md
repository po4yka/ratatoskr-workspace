## Context

The extractor today terminates hydration-required pages through the ordinary HTML quality gates.
Chromium is a high-cost, high-risk fallback, so the contract must make isolation, credential
denial, resource blocking, and budgets structural rather than optional call-site flags. NATS
messages are size-capped well below rendered page sizes, which forces BlobRef evidence instead of
inline DOM. No shared Rust contract crate change is needed: subjects and payload schemas live in
this store, and each deployable implements them against its own types.

## Goals / Non-Goals

Goals: one navigation per job; fresh contexts; denied credentials; blocked heavy resources;
worker-side SSRF revalidation; finite budgets; deterministic, bounded escalation; reuse of the
extractor's parser, evaluator, provenance, and events on the returned DOM.

Non-Goals: general-purpose browser automation for logging into user accounts; stealth or
anti-bot-bypass capability; OCR of rendered images; screenshots or PDF printing; parallel
multi-tab rendering; a blob storage service.

## Decisions

### Subjects follow the existing fleet vocabulary

`cmd.content.render.requested.v1`, `evt.content.render.completed.v1`,
`evt.content.render.failed.v1`. The command stream is JetStream work-queue semantics with a durable
consumer named for the browser worker; at-least-once delivery plus `render_id` idempotency gives
exactly-once effect without new transport machinery.

### Evidence is owned bytes plus a summary

The worker stores rendered DOM under its own content-addressed root (same deployment device,
separate path from the extractor's blobs) and announces it with a `BlobRef` whose media type is
`text/html`. The network-evidence summary records redirect hops, statuses, media types, and
blocked-request counts — never bodies. This reuses the stored-bytes capability unchanged.

### Failure classes are stable strings

`policy_blocked`, `navigation_timeout`, `total_timeout`, `size_limit`, `navigation_failed`,
`browser_unavailable`. The extractor maps them onto its terminal failure classes verbatim so
diagnostics survive the hop.

### Escalation trigger is deterministic

Escalate only when the direct attempt produced a low-quality rejection whose evidence matches an
empty-shell shape (near-zero text with hydration markers such as a single script bundle and empty
mount nodes), capped per host by configuration. The escalated document comes from the same
`from_html` path, so candidate competition, thresholds, provenance naming the rendered artifact,
and completion events stay identical to direct extraction.

## Risks / Trade-offs

[Chromium supply chain] → the worker pins a Chromium build per deployment image; the contract does
not depend on a specific CDP client library.
[Rendered DOM still fails quality] → explicit degraded termination, no loop; escalation budget per
host bounds cost.
[Worker compromise surface] → no credentials exist in the schema to steal; heavy subresources and
downloads are denied; memory/process caps belong to the deployment unit, noted as a requirement on
the deployment, not the message.

## Migration Plan

Contract lands first (this change). Then the browser-worker deployable implements consumption and
evidence publication behind its own tests. Last, the extractor gains escalation wiring that is
inert until the worker is deployed. Each step deploys independently; nothing reads render events
until escalation ships.

## Open Questions

None blocking; per-host strategy tables and OCR remain future changes.
