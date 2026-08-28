## Context

See `proposal.md` for motivation. Knowledge already has `search_documents`, hybrid/lexical retrieval, `analysis_user_states`, and a loopback-only search/user-content adapter. Platform authenticates public sessions and owns the generated OpenAPI surface, while Telegram already exchanges an owner binding for a Platform session, processes commands after webhook acknowledgement, stores opaque interaction authority, and sends through a durable outbound queue. The existing Platform generic domain proxy cannot be the library API because Knowledge's current loopback routes accept an explicit tenant and do not emit the public error contract.

The target is one process per role on one host. Calls are synchronous bounded queries or idempotent small writes; they do not create long-running operations or bus messages.

## Goals / Non-Goals

**Goals:**

- Establish one client-safe contract that web/mobile can also consume later without Telegram-specific fields.
- Keep authentication and public error/OpenAPI behavior in Platform, search/read-state ownership in Knowledge, and interaction authority/rendering in Telegram.
- Make read-state replacement safe under retry and incapable of resetting favorite.
- Permit additive deployment and reverse-order rollback on the single host.

**Non-Goals:**

- Moving Document IR, full article bodies, tags, collections, highlights, or favorite state into Platform or Telegram.
- Adding a generic search event family, search-history persistence, semantic-mode selection, or a long-running operation.
- Turning opaque Telegram tokens into a fleet contract; they remain Telegram-owned presentation authority.

## Decisions

### D1: Platform owns a dedicated library façade

Clients use `GET /v1/library/search` and `PUT /v1/library/items/{analysis_id}/read-state`. Platform authenticates the session, derives `user:<internal-user-uuid>` for Knowledge, validates public bounds, maps errors, and emits only public fields.

The alternative was routing `/v1/k/internal/*` through the generic proxy. That would publish loopback paths, let callers attempt tenant selection, expose service-private response/error shapes, and keep the API absent from generated OpenAPI. A Platform read model was also rejected because it would duplicate Knowledge state and require synchronization.

### D2: The public item identity is the accepted analysis output

`analysis_id` is the identifier of the accepted output whose search document and read state are being shown; `document_id` remains provenance identity. Read state is therefore version-specific, matching the implemented Knowledge model. A newer accepted output with no state is unread even if an older output was read.

Using `document_id` as the mutation target was rejected because it is not the state table's authority and would require an undocumented latest-output resolution at mutation time.

### D3: Search uses bounded offset pagination and effective-state filtering

The first-version API retains Knowledge's current deterministic order and offset model: `limit` 1..100, non-negative `offset`, optional `q`, optional `read_state`, plus `has_more`. Knowledge fetches one extra row after applying tenant and state predicates to calculate `has_more`. A missing state row is `unread` through an outer join and closed-value coalescing.

Cursor pagination was considered, but no immutable search snapshot or cursor contract exists. Introducing one only for a five-result Telegram page would create new state and compatibility work without solving a current acceptance need.

### D4: Read state is replaced with PUT and preserves adjacent state

The body is exactly `{ "read_state": "read" | "unread" }`. Knowledge inserts a missing state row or updates only `read_state` and `updated_at`; the conflict update never writes `favorite`. PUT makes retry semantics explicit and avoids an idempotency ledger for this complete, small resource.

Reusing the existing whole `AnalysisState` command was rejected because callers that do not know favorite could reset it.

### D5: Capability discovery reflects last observed Knowledge health

Platform adds `library.search` and `library.read_state` to its closed vocabulary. Their requirement combines session/database availability with the existing background observation of the configured Knowledge service. A public request never performs a health probe; a race after a healthy observation returns a retryable dependency error.

### D6: Telegram renders command-scoped opaque authority

Telegram requests five items and renders one bounded direct reply. For each unread result it stores an action record containing `analysis_id` and exposes only a 64-character `/read` command token. The record is bound to bot, Telegram actor, internal user, and chat, expires after 15 minutes, and is consumed once before the external call. Platform PUT retry safety covers transient duplicate delivery inside the winning worker; a response-unknown terminal outcome is reported without claiming success.

Raw result fields are not retained as Telegram domain state. The existing outbound queue necessarily holds the bounded escaped message until its normal delivery retention completes; no separate search-history or result projection is added.

### D7: Integration proves the authority chain, not live Telegram delivery

The workspace profile runs real Knowledge, Platform, Telegram webhook/dispatcher, PostgreSQL, and the existing infrastructure with a synthetic Bot API recorder. It seeds two tenants and mixed read/favorite state, drives updates through the webhook, presents one emitted read token, and queries Knowledge afterward. This proves service and persistence boundaries; it is not evidence of production Bot API delivery or a real account.

## Risks / Trade-offs

- [Offset pages can shift while indexing or state changes] -> deterministic ordering and explicit `has_more` make behavior testable; cursor snapshots remain a later fleet-wide API decision.
- [Search replies contain private snippets in durable outbound payloads] -> private chats only, strict result/text bounds, no separate projection/history, no content telemetry, and existing outbound retention apply.
- [A consumed token can end with an uncertain Platform response] -> PUT is idempotent, the worker retries within finite bounds, then reports unknown and directs `/unread` reconciliation.
- [Capability state can be briefly stale] -> request failures remain explicit and retryable; no stale data or success is synthesized.
- [New accepted analysis outputs default unread] -> this matches the implemented per-output ownership model and is documented rather than silently inheriting state across evidence versions.

## Migration Plan

1. Merge and deploy Knowledge's additive internal fields, filter, `has_more`, and read-only-state command. Existing callers ignore additive JSON fields and may omit the new filter.
2. Merge and deploy Platform's dedicated client, public routes, OpenAPI, and capability names. Keep capabilities absent until the Knowledge observation is healthy.
3. Regenerate affected clients, then merge and deploy Telegram command support.
4. Run the composed workspace profile and record exact repository revisions and synthetic-provider evidence before advancing pins.
5. Roll back in reverse order. Existing Knowledge state rows need no conversion or deletion.
