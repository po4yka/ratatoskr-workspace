# Workspace testing strategy

> Status: Proposed  
> Last reviewed: 2026-08-17

## Required layers

- Manifest schema, repository catalog, and dependency-cycle tests.
- Gitlink/remote/lock consistency and drift tests.
- Idempotent task preparation, recovery, and cleanup tests.
- One-writer and writable-path enforcement.
- Changeset lifecycle, rollout, rollback, and PR reconciliation.
- Agent runner timeout, cancellation, result, and secret-redaction tests.
- Task-namespaced Compose integration profiles.
- Release snapshot and rollback metadata validation.

## Failure matrix

Test interrupted fetch/worktree creation, dirty repositories, missing remotes, child command failure, agent crash, stale PR state, partial merge, integration startup failure, and lock/pin mismatch.

## CI gates

Formatting/linting, unit tests, Git integration tests, generated-config drift, fixture validation, security/dependency checks, and at least one end-to-end task flow. Workspace CI supplements rather than replaces child CI.

Fixtures must use synthetic repositories and credentials. Never use personal exports or production tokens.
