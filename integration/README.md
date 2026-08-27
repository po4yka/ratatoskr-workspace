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
