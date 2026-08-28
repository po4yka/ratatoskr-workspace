# Workspace testing strategy

> Status: Proposed  
> Last reviewed: 2026-08-27

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

## Implemented integration smoke

`integration/tests/web_operational_profile_test.sh` checks the static isolation and phase contract
for the first profile. `integration/run-web-operational.sh` then builds exact published Contracts,
Platform, and Web revisions and observes:

- anonymous public status through Platform and the Web production bundle;
- member refusal and owner access to operations, schedules, and audit history;
- keyboard and axe checks on the real `/status` and `/ops` pages;
- NATS loss as a truthful degraded/stale state, followed by recovery; and
- project-only teardown with unrelated container state unchanged.

This smoke does not implement or validate the planned `ws` commands, manifest, lockfile, or general
profile generation. Run it with the inputs documented in `integration/README.md`.

The TG-010 Telegram profile is independently checked by
`integration/tests/telegram_deployment_profile_test.sh` and
`integration/tests/telegram_notification_profile_test.sh`. Its composed runner builds exact
published Contracts, Platform, and Telegram revisions and observes the item-5 article path,
notification preference/deduplication decisions, notification-durable readiness failures and
recovery, and project-only cleanup. It uses no production bot token or real chat and therefore does
not establish live delivery. Run it with the inputs documented in `integration/README.md`.

The TG-011 library-command profile is statically checked by
`integration/tests/telegram_library_profile_test.sh`. The check pins the Knowledge/Platform/
Telegram topology, allocated loopback and dynamic host ports, deterministic two-tenant fixtures,
the complete search/unread/read/scope/recovery assertion sequence, reviewed evidence fields, and a
namespaced teardown dry run. `build-gate -- integration/run-telegram-library.sh` is the heavier
composed proof and must use exact clean revisions for final evidence. Its Bot API is synthetic and
content-bounded; it does not prove a live Telegram account or deployment.

## Test-first

A change is planned before it is built, and the plan is a task list in which behaviour arrives in
pairs: one task adds a failing test, the next makes it pass. `openspec/config.yaml` carries that
rule, which is what puts it into every planning and implementation request rather than only into this
document.

The loop:

1. Write the test the scenario names. Run it. Confirm it fails, and read the failure — a test that
   fails because it does not compile has proved nothing about the behaviour.
2. Write the smallest change that makes it pass. Run it again.
3. Refactor only once it is green, adding no test and changing no behaviour.

Two checks stand behind this, and neither of them can see the order:

- `openspec validate --archived`, in `.github/workflows/openspec.yml`, fails when a change was
  archived with a task left unticked.
- A step in `.github/workflows/fleet.yml` fails when this repository holds a manifest and a `ci.yml`
  that never runs a test.

`ratatoskr-workspace/docs/QUALITY_GATES.md` records why the order itself is not checkable, rather
than leaving the gap to be discovered.
