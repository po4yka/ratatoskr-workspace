## Why

Two implemented runtime boundaries can acknowledge work while losing the state needed to complete or explain it. Platform discards result and diagnostic fields from domain reports, and Telegram can acknowledge an update whose recoverable payload exists only in process memory.

## What Changes

- Make Platform preserve the complete v1 result and diagnostic data carried by `OperationReported` and return it in the operation snapshot.
- Make Telegram persist enough authenticated update data before HTTP success for deterministic processing after a process restart, then remove that data after settlement.
- Add repository-local regression tests for successful and failed operation reports and for a crash between Telegram admission and processing.
- Keep the existing v1 wire contracts unchanged; no producer change is required.

## Capabilities

### New Capabilities

- `telegram-update-recovery`: Accepted Telegram updates remain processable after a webhook process restart without retaining their payload after terminal settlement.

### Modified Capabilities

- `operation-progress`: Platform preserves and projects every result, error, and warning field that a domain service reports through the existing v1 contract.

## Impact

Repositories, in dependency order:

1. `ratatoskr-platform` consumes the existing contract and must merge first because no producer change is required.
2. `ratatoskr-telegram` changes only its private persistence and webhook worker boundary and can merge independently.
3. `ratatoskr-workspace` records the coordinated verification evidence after both child commits are known.

Affected surfaces are Platform's operations schema/projection/public snapshot and Telegram's private schema/admission/worker. Extractor, Contracts, Knowledge, clients, deployment, and provider APIs stay outside this change.

Nothing has shipped to the frozen host. Rollback is a revert of each child commit and recreation of the development database from the prior schema definition; there is no data migration or deployed-state rollback.
