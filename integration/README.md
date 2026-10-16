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

## NATS authorization

Every profile that starts a broker renders its NATS file from Platform's deployed
`deploy/nats/ratatoskr.conf` with `integration/lib/nats-conf.sh` (`render_nats_conf`), at the Platform
revision under test, so a profile runs under the same ACL as production. The library needs `go` once
for the nkeys module. Check it with:

```sh
bash integration/tests/nats_conf_test.sh
```

The profile contract tests (`export_agent_product_profile_test.sh`, `telegram_library_profile_test.sh`,
`telegram_notification_profile_test.sh`) end with a step that starts a sentinel container, so they need
a reachable Docker daemon; without one only their static assertions can be exercised.

`web-operational` joined the other profiles in XR-021 round 3: its broker used to start from
command-line flags with no authorization, and it now runs the rendered file for the Edge identity.
`tests/no_unauthenticated_broker_test.sh` fails when any compose profile starts a NATS broker
without one.

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

## Native smoke (no Docker)

`integration/native/` drives the cross-repository flows through Edge on one machine without Docker,
with the deployed NATS ACL and the checked-in PostgreSQL provisioning, on the production loopback
ports. It is a manual run and not a CI gate. Read [`native/README.md`](native/README.md) before
running it: it states what each flow does, what is faked or seeded, what it cannot show, and that
none of the committed flows has been run through `run.sh` yet. `tests/native_smoke_contract_test.sh`
checks the scripts without starting a service.

## Site owner editing and notes write-back

`run-site-owner-editing.sh` builds and composes the real Platform, Sites, Notes and Knowledge
services with PostgreSQL/pgvector and NATS. Domain listeners keep their loopback-only peer rules:
all containers share one task network namespace. Only Edge's public and operator ports are exposed,
on dynamically assigned loopback ports. NATS uses Platform's deployed ACL with new task-only nkeys.
The PostgreSQL trust setting is confined to that private network; PostgreSQL has no host port.

Set a unique `RATATOSKR_TASK_NAMESPACE`, plus `RATATOSKR_<REPO>_CONTEXT` and
`RATATOSKR_<REPO>_REVISION` for `PLATFORM`, `SITES`, `NOTES` and `KNOWLEDGE`. Each revision must be
the context's clean HEAD and belong to its `origin/main`. The runner refuses an existing Compose
project of that name. `--validate` renders the profile and does not start services. A normal run
builds one service at a time and removes only its own project and volumes on exit.

The HTTP scenario signs in through the consent protocol, checks a stale edit conflict, then checks
that a current edit becomes one revision and one event only after the fake device acknowledges it.
A repeated acknowledgement must add nothing. The publication is manual: anonymous content must
stay on the old release until an explicit release request, whose new release id must arrive on a
real anonymous SSE stream. A seeded owner document and a second user's document share one search
term; both site search routes must return only the owner's document. Separate write-back legs use
a fake Sync working tree for rename/link rewrite and property writes, and a fake device for refusal
and a partially applied rename group with one conflict.

Only principals, the device/Sync peer and Knowledge input rows are fixtures. The services, HTTP
routes, blob transfers, command outboxes, deployed NATS permissions and event consumers are real.
The scenario does not test a browser UI, a real Obsidian Sync server, an LLM provider, TLS termination
or production host permissions. Containers use a disposable root identity to read private generated
keys and their own volumes; the Molecule checks cover service users and host group permissions.

`RATATOSKR_SITE027_APT_HTTPS=1` is an explicit build workaround for networks that refuse Debian's
HTTP mirror. It makes private copies of the pinned child Dockerfiles, changes the mirror scheme to
HTTPS, copies the builder's verified CA bundle before runtime package installation, and selects the
already installed Rust 1.97.0 toolchain without downloading optional components. It changes no child
source or lockfile and weakens no TLS or package verification. Evidence records this deviation in
`build-deviations.txt`. `result.json` records the exact revisions, assertions and fixture boundaries.

The same run includes [the SITE-025 privacy scenario](sites-privacy/README.md). It uploads the
committed privacy vault through Notes and requests the first release through Edge. Anonymous
requests read every release page and asset and search all private canaries. The workspace
`sites-integration` job runs this profile on arm64 against the exact committed child pins.
`result.json` is published only after source validation and successful teardown.
