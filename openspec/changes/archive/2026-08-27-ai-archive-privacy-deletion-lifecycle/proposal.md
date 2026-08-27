## Why

The shared AI-archive tombstone can express provider, compliance, and reconciliation deletions but cannot truthfully represent an owner-requested privacy erasure. Plan item 9 needs that authority before ChatGPT Archive can atomically request downstream Knowledge deletion.

## What Changes

- Extend the existing v1 AI-archive tombstone reason vocabulary additively with `user_requested`; no new major or parallel event is introduced.
- Require Knowledge to accept and idempotently erase derived state for that reason before any archive producer enables it.
- Require ChatGPT Archive to emit user-requested tombstones only from an authorized completed privacy-deletion inventory and to use non-sensitive immutable audit evidence.
- Record changeset `AIARCH-009` with dependency order: `ratatoskr-contracts` first, `ratatoskr-knowledge` second, `ratatoskr-chatgpt` third, and `ratatoskr-workspace` validation last.
- Keep account-erasure coordination, Claude Archive producers, Platform implementation changes, clients, real provider fixtures, Compliance acquisition, and database migration tooling outside this cross-repository change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `ai-archive-event-lifecycle`: Define owner-requested tombstone authority, consumer behavior, producer evidence, and rollout/rollback ordering.

## Impact

- Affected repositories in dependency order: `ratatoskr-contracts` (wire vocabulary and fixtures), `ratatoskr-knowledge` (compatibility and deletion proof), `ratatoskr-chatgpt` (producer plus lifecycle implementation), then `ratatoskr-workspace` (integrated spec and verification record).
- Adding a reason token is additive because consumers receive a bounded string newtype and Knowledge does not branch exhaustively on reason; compatibility fixtures must prove this before producer rollout.
- Before ChatGPT producer rollout, rollback is a normal revert in reverse order. After a `user_requested` tombstone is published, derived deletion is intentionally irreversible; rollback disables new production but does not recreate deleted source or Knowledge data.
