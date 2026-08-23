## Context

See `proposal.md` for motivation. The existing v1 contracts already carry the required operation report data. The two defects are independent consumer-side durability failures in Platform and Telegram. Both databases are development-only and are created from current schema definitions.

## Goals / Non-Goals

**Goals:**

- Keep the existing producer and HTTP contracts compatible.
- Make acknowledged work recoverable and public operation snapshots truthful.
- Verify both fixes at the repository boundary and record exact child commits.

**Non-Goals:**

- No new contract version, migration, workspace harness, deployment, or integration of Knowledge, Web, or Telegram dispatcher.
- No change to Extractor publication or Telegram Bot API registration.

## Decisions

### Consumers repair existing v1 handling

Platform and Telegram change independently because the wire inputs are already sufficient. Changing producers or introducing a new event would create a coordinated cutover without solving the consumer data loss.

### Child repositories own implementation detail

The workspace delta states only observable cross-repository behavior. Platform owns operation persistence; Telegram owns update persistence and privacy. Their local changes define schema and worker mechanics.

### Rollout order is Platform, Telegram, then workspace evidence

Platform is a backward-compatible consumer correction and requires no producer rollout. Telegram changes only private state and can follow independently. The workspace record lands last with both child SHAs and observed checks.

## Risks / Trade-offs

- [Structured payloads use more PostgreSQL storage while pending] → Keep Platform data bounded by existing contract limits and remove Telegram payloads on terminal settlement.
- [A schema edit requires a fresh development database] → Validate schema creation and explicitly avoid the frozen host.
- [Repository-local tests do not prove the full fleet] → Record focused integration tests now; the absent workspace harness remains outside this change.

## Migration Plan

1. Merge and push the Platform consumer fix after its local gate passes.
2. Merge and push the Telegram durability fix after its local gate passes.
3. Record both SHAs and verification in this workspace change and push the workspace commit.

Rollback each child by reverting its commit and recreating the development database from the previous schema. No deployed database or provider state is modified.

## Observed verification

- `ratatoskr-platform` commit `c533ad7f0b4621070cec9075d933d0e2725e01d2` is on remote `main`. Its complete documented local gate and all four GitHub workflows passed.
- `ratatoskr-telegram` commit `69ea5d3b04c438ca4cefee69c7ce833ac4aa79e5` is on remote `main`. Dependency policy, formatting, source-size limit, debug and release builds, the complete workspace test suite, and the focused persistence and restart suites passed.
- Telegram's complete Clippy gate remains blocked by pre-existing lints already present in base commit `ee3e462d8efbe516e3b18e5480a654efbb3c0985` and its failed CI run `32573155310`. This change adds no lint suppression; its affected persistence crate passes Clippy, and the runtime behavior is covered by the green database-backed tests above.
- No frozen-host deployment, provider registration, database migration, contract version, or workspace pin changed.
