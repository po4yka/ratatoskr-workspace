# Web operational integration profile

This is one executable acceptance profile, not the planned workspace harness. It builds Platform
Edge and the Web production bundle from explicit local checkouts, then starts isolated PostgreSQL
and NATS dependencies with synthetic data.

## Prerequisites

- Docker with Compose and BuildKit
- `build-gate`, `curl`, `jq`, Node.js, and `rg`
- clean local checkouts at commits already contained by each repository's `origin/main`
- Web dependencies and Playwright Chromium installed in the Web checkout

## Validate the profile contract

```sh
bash integration/tests/web_operational_profile_test.sh
```

## Run the composed smoke

Set these inputs to absolute checkout paths and full commit IDs:

```sh
export RATATOSKR_TASK_NAMESPACE=web012
export RATATOSKR_CONTRACTS_CONTEXT=/absolute/path/to/ratatoskr-contracts
export RATATOSKR_CONTRACTS_REVISION=<full-contracts-sha>
export RATATOSKR_PLATFORM_CONTEXT=/absolute/path/to/ratatoskr-platform
export RATATOSKR_PLATFORM_REVISION=<full-platform-sha>
export RATATOSKR_WEB_CONTEXT=/absolute/path/to/ratatoskr-web
export RATATOSKR_WEB_REVISION=<full-web-sha>

build-gate -- integration/run-web-operational.sh
```

The runner refuses a context whose `HEAD` differs from the requested revision or whose revision is
not contained by `origin/main`. Host ports are assigned dynamically. Raw logs and JSON responses go
only to `evidence/<namespace>/`, which Git ignores; the fleet changeset records the reviewed result.

The smoke checks healthy status, member refusal, owner operational reads, real-page keyboard and axe
results, NATS degradation, recovery, and namespaced teardown. Fixture credentials are fixed,
non-secret values used only by the disposable database and are never printed.

## Telegram notification profile (TG-010)

Validate the port/deployment and Compose contracts against an exact Telegram checkout:

```sh
RATATOSKR_TELEGRAM_CONTEXT=/absolute/path/to/ratatoskr-telegram \
RATATOSKR_TELEGRAM_REVISION=<full-telegram-sha> \
  integration/tests/telegram_deployment_profile_test.sh
integration/tests/telegram_notification_profile_test.sh
```

Run the composed profile with clean child checkouts already contained by their `origin/main`:

```sh
export RATATOSKR_TASK_NAMESPACE=tg010-local
export RATATOSKR_CONTRACTS_CONTEXT=/absolute/path/to/ratatoskr-contracts
export RATATOSKR_CONTRACTS_REVISION=<full-contracts-sha>
export RATATOSKR_PLATFORM_CONTEXT=/absolute/path/to/ratatoskr-platform
export RATATOSKR_PLATFORM_REVISION=<full-platform-sha>
export RATATOSKR_TELEGRAM_CONTEXT=/absolute/path/to/ratatoskr-telegram
export RATATOSKR_TELEGRAM_REVISION=<full-telegram-sha>

build-gate -- integration/run-telegram-notification.sh
```

The runner uses fresh PostgreSQL 17 and JetStream state, runtime-generated credentials, a fake Bot
API, dynamic loopback host ports, and the exact `ratatoskr-<namespace>` Compose project. It proves
the article flow reaches its final Telegram projection, enabled/suppressed/duplicate notification
decisions are enforced, and dispatcher readiness fails closed for absent or mismatched Platform
durables. `evidence/<namespace>/` is ignored raw evidence; `TG-010` records the reviewed bounded
summary. This is synthetic integration evidence, not hosted-CI, live-provider, or deployment proof.

## Telegram library profile (TG-011)

Validate the task namespace, service topology, dynamic ports, fixture boundary, runner assertions,
reviewed evidence shape, and exact teardown plan:

```sh
integration/tests/telegram_library_profile_test.sh
```

Run the composed profile with clean child checkouts already contained by their `origin/main`:

```sh
export RATATOSKR_TASK_NAMESPACE=tg011-local
export RATATOSKR_KNOWLEDGE_CONTEXT=/absolute/path/to/ratatoskr-knowledge
export RATATOSKR_KNOWLEDGE_REVISION=<full-knowledge-sha>
export RATATOSKR_PLATFORM_CONTEXT=/absolute/path/to/ratatoskr-platform
export RATATOSKR_PLATFORM_REVISION=<full-platform-sha>
export RATATOSKR_TELEGRAM_CONTEXT=/absolute/path/to/ratatoskr-telegram
export RATATOSKR_TELEGRAM_REVISION=<full-telegram-sha>

build-gate -- integration/run-telegram-library.sh
```

The runner builds real Knowledge, Platform, webhook, and dispatcher processes, creates disposable
Platform/Knowledge/Telegram databases from their current schemas, and uses a recording synthetic
Bot API. It proves owner-scoped `/search`, filtered `/unread`, token-bound `/read`, replay and
foreign-scope refusal, favorite preservation, and health-backed capability disappearance/recovery.
Raw output remains under ignored `evidence/<namespace>/`; the reviewed boundary is
[`evidence/TG-011.md`](evidence/TG-011.md).

The workspace harness and generated `workspace.lock` are still unimplemented by repository
decision (`DEVELOPMENT.md`). TG-011 therefore pins its inputs through required full revision
variables and refuses dirty, mismatched, or unpublished revisions instead of fabricating lockfile
metadata. `RATATOSKR_ALLOW_DIRTY_SOURCES=1` and `RATATOSKR_ALLOW_UNPUBLISHED=1` exist only for a
clearly labelled pre-publication smoke; their output cannot satisfy the exact-revision evidence row.
