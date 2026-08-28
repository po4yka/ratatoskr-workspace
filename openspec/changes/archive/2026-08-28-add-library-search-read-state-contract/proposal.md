## Why

Knowledge already owns tenant-scoped search and read state, but clients have no authenticated Platform contract that joins those capabilities safely. The missing boundary blocks Telegram's reserved `search`, `unread`, and `read` commands and leaves existing fixture-only client behavior unable to become authoritative.

## What Changes

- Define a session-authenticated Platform library API for bounded search/recency browsing, an optional `read`/`unread` filter, and idempotent read-state replacement.
- Define one public item summary carrying the accepted analysis identifier, document identifier, bounded title/snippet, optional relevance score, and effective read state; a missing state row means `unread`.
- Require Platform to derive the tenant from the authenticated principal and to hide foreign and missing items identically. Client-supplied tenant selectors are forbidden.
- Require read-state updates to preserve favorite and every other Knowledge-owned user-content field.
- Add `library.search` and `library.read_state` capability names whose availability reflects the last observed Knowledge dependency health.
- Define Telegram's private-chat command contract: `/search <query>`, `/unread`, and `/read <opaque-token>`, including bounded output, opaque owner/chat-bound authority, idempotent mutation, and truthful unavailable/uncertain outcomes.
- Coordinate `ratatoskr-knowledge` first, then `ratatoskr-platform`, then `ratatoskr-telegram`, followed by workspace integration and pins.
- Keep semantic/vector mode selection, saved searches/history, favorites, tags, collections, highlights, bulk mark-read, mark-unread command UX, natural-language command inference, channel digests, and reader UI outside this change.

## Capabilities

### New Capabilities

- `library-search-read-state`: Cross-repository public query, read-state mutation, capability-discovery, Telegram command, authorization, compatibility, and rollout behavior.

### Modified Capabilities

- None.

## Impact

- Repositories in merge order: `ratatoskr-knowledge` (backward-compatible internal query/state support), `ratatoskr-platform` (public Edge/OpenAPI façade and capability discovery), `ratatoskr-telegram` (command adapter and opaque action authority), then `ratatoskr-workspace` (composed integration evidence and compatible pins).
- Public API: new first-version `GET /v1/library/search` and `PUT /v1/library/items/{analysis_id}/read-state` operations; generated clients gain additive types and methods.
- Persistence: no new fleet-wide schema and no migration. Knowledge reuses its current `analysis_user_states`; Telegram extends its current schema definition for a new opaque action kind.
- Security/privacy: Platform authentication is the only public tenant authority; Telegram result tokens carry no analysis identifier or private text; logs and metrics retain only safe classes and correlation identifiers.
- Rollout: Knowledge merges/deploys first, Platform second, Telegram third. An older consumer ignores the additive Knowledge response fields; Platform with an unavailable/older Knowledge dependency withholds both library capabilities; Telegram hides/refuses commands while the capabilities are absent.
- Rollback: roll Telegram back first, then Platform, then Knowledge. Read-state rows written before rollback remain valid Knowledge-owned state. No destructive rollback or data conversion is required; if nothing has shipped, deleting the unmerged changes is the complete rollback.
