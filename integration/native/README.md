# Native multi-service smoke

This directory drives each cross-repository flow of the Ratatoskr fleet through Platform Edge's HTTP API on one machine, with no Docker. It exists because the Docker profiles under `integration/compose/` cannot run on the machines the fleet is developed on, and because those profiles never exercised the services together under the deployed bus authorization with the checked-in PostgreSQL provisioning. It is the only end-to-end evidence the XR-021 change can produce, so its honesty rules are part of it: a flow that was not run, or a hop that was stubbed, is written down as such and never reported as passed.

It is a manual, machine-dependent run. It is not a CI gate, and nothing in CI runs it. `integration/tests/native_smoke_contract_test.sh` checks the scripts themselves (the prerequisite check, `--list`, `--prune`, the safety rules, the fixtures and the fakes) without building or starting any service.

## What it runs

Services are built natively with `cargo build --release --locked` from the pinned submodules under `repos/` (read only; every flow ends with a check that each repository it used is still clean), configured only through the `RATATOSKR__*` keys of each repository's `deploy/systemd/*.conf.example`, and started with `lib/envrun.py`, which behaves like the `EnvironmentFile` of the shipped unit files. NATS is `nats-server` under the deployed ACL of Platform's `deploy/nats/ratatoskr.conf` with fresh nkeys from Platform's own `render-nats-config`. PostgreSQL is a private cluster under the state directory, provisioned only with the checked-in files in the order Platform's `deploy/README.md` documents: `01-database-and-roles.sql`, the first Edge start, `02-grants.sql`, then each service's `deploy/postgres/role.sql` before that service's first start.

A flow that needs Edge's routes runs on the production loopback ports of `docs/DEPLOYMENT_TARGET.md` (Edge 8080 and 9464, Knowledge 8091 and 9081, GitHub 8092 and 9095, ChatGPT 8096 and 9085, Claude 8097 and 9086, channel-digests 8098, 9469 and 9470, X 9087, Instagram 9082 and 9083, Threads 9084, extractor 9088, Telegram 8182, 9467 and 9468, NATS 4222 and 8222), because Edge's validation of those routes is a contract (R3-17). The one exception is PostgreSQL on `127.0.0.1:54329`. Because the ports are fixed, only one flow can run on the machine at a time: `run.sh` takes `$RATATOSKR_SMOKE_DIR/lock` and refuses to start when a port of the flow is held by another process, printing the holder's pid and command and exiting 3. It never stops a process it did not start.

## Usage

```sh
integration/native/run.sh --list              # the flows, their binaries and ports
integration/native/run.sh --dry-run f1        # exit 0, or exit 3 with one MISSING line per missing prerequisite
integration/native/run.sh f0 f1 f2            # run flows one at a time, in the order given
integration/native/run.sh --prune             # remove what earlier runs left under the state directory
```

The state directory is `$RATATOSKR_SMOKE_DIR`, default `$HOME/.cache/ratatoskr-smoke/XR-021-r4`. It must be an absolute path outside the workspace checkout, and `--prune` only touches a directory that carries the `.ratatoskr-smoke-dir` marker the smoke wrote. The evidence summary of each flow goes to the gitignored `evidence/XR-021-r4/<flow>/`: `asserts.txt`, `result.txt` with the verdict, the hops that were stubbed, seeded or not exercised, and every configuration deviation from the shipped examples, plus redacted request and response records. Databases, blobs, staging, keys and rendered configs hold secrets and are deleted when a flow ends; logs and the redacted evidence stay. F1 keeps its databases, blobs, keys and the NATS store for F6, which needs the facts F1 produced.

Prerequisites: `nats-server` 2.10 or later, `initdb`, `pg_ctl`, `psql` and `pg_config` for PostgreSQL 17 with the pgvector files installed (the extension is not trusted, so Knowledge's `role.sql` creates it as the administrator), `cargo` with the toolchains the repositories pin, `python3` with the `cryptography` package, `jq`, `curl`, `lsof`, `rg` and `git`, at least 12 GiB free on the volume that holds the state directory, and every port of the flow free. Docker is not needed.

Builds use each repository's shipped release profile. `CARGO_PROFILE_RELEASE_DEBUG=0` is never set, because it makes the sqlx proc-macro dylib fail to load on macOS 27 (`mis-aligned LINKEDIT string pool`); `lib/build.sh` retries a build once with `CARGO_PROFILE_RELEASE_STRIP=none` when it sees that error and records the retry. A target directory is deleted right after its build, and a build is refused below 6 GiB free.

## Flows

| Flow | What it shows | Run through `run.sh` as committed |
| --- | --- | --- |
| F0 | Provisioning: every `role.sql` as written, every role connects unprivileged, the durables of S04, the 8 MiB limit (and the broker's refusal of a declared 9 MiB publish), the inbox ACL probes of R3-01 with the real seeds, the dispatcher's `check-config` for the notification ack wait of 31 and 30 seconds, the idle notification subject | not run |
| F1 | AI-archive upload through Edge to the real ChatGPT and Claude receivers: sessions, ceilings, restart and resume, the 403 for an unmapped user, a receiver that is down, the cumulative series F6 needs | not run |
| F2 | Knowledge ingestion: a PDF blob capture and a ChatGPT archive fact, searched through Edge; the negatives, a NATS outage and the size legs | not run |
| F3 | Telegram to Platform with the real webhook and dispatcher binaries against a fake Bot API: the assertion-key command, the session exchange, the static replies, the same PDF plain and then forwarded, a redelivered update, the loss of the Platform session | not run |
| F4 | Channel digests: subscription set, run deadline, recap with a faulted acquisition hop, the read hop through Edge, the schedule owner check | not run |
| F5 | Social captures for X, Instagram and Threads, the lane each operation was dispatched to, cross-lane report authority, public-resolution outcomes, a Threads permalink with an escaped query | not run |
| F6 | Privacy deletion and tombstone delivery over F1's data, for both providers, with tombstone resilience and a concurrency leg | not run |
| F7 | The GitHub analysis loop: the track action, the request on the bus, the README fetch, a COMPLETED fact consumed by GitHub, a failed closure when the provider refuses, PAT registration against the fake GitHub, the observer, bounded provider calls | not run |

The recorded Round 3 smoke results (changeset `XR-021-fleet-cross-repo-fixes`, block `round_3`) came from by-hand scripts kept outside the repository, under `.workspaces/XR-021/smoke/`. The flows here are ported from those scripts where they existed (F0 to F2 and F4, and parts of F3, F5 and F6) and written new where they did not (the inbox probes, the Telegram webhook and dispatcher, the lane-authority legs, Claude's deletion, the resilience and concurrency legs of F6, and F7). Each flow file says which. None has been run through `run.sh`; the first run is where its assertions meet the services for the first time, and a failed assertion there is either a defect in the owning repository, to be reported with the file and line, or a mistake in the flow, to be fixed here.

## Round 4

Round 4 fixed what the first honest read of the harness found (the shadowed `name` in `assert`, the `getMe` fields of the fake Bot API, the F3 assertions that a single two-line message could satisfy, the F7 closure that accepted a failed fact) and added legs for the Round 4 fixes. Each fix has a check in `native_smoke_contract_test.sh`. The round 4 state directory and evidence root are `XR-021-r4`.

The Round 4 smoke runs recorded in the changeset (`round_4.native_smoke`) were by-hand runs from scripts kept under `.workspaces/XR-021/smoke/`, as in Round 3. No flow has been run through `run.sh` as committed, so every row of the table above still says not run, and a leg below that is written here has never met a service.

Legs in the flow files, written and not yet run: F0 (the declared 9 MiB publish, `check-config` of the dispatcher with an ack wait of 31 and of 30, nothing on `evt.platform.notification.>` and nothing pending on the dispatcher's durable), F3 (the same PDF plain and then forwarded, the status of every capture call read from the tap, replies counted by Bot API method, a redelivered update, the loss of the Platform session), F5 (the escaped Threads query and a non-ASCII query byte), F7 (the completed closure, the failed closure, the PAT registration).

Legs in the Round 4 plan that are NOT in the flow files: F1 (the Claude knowledge file, the corrupt archive, the repeated key, the 401 stand-in on 8097, the Swift client), F2 (the Claude fact, the large facts, the Knowledge outage, the non-envelope message), F3 (a bare URL then forwarded, which needs a loopback page the extractor may fetch), F4 (the scheduler occurrence), F5 (the browser extension's client module, the Knowledge leg for a deleted post), F6 (survivor content, the owner after a mapping change, the crash window, the ordering). The RED runs against the Round 3 heads of claude, knowledge, telegram and threads were not made; the legs name the expected failure in a comment.

## What is faked, seeded or not exercised

The fakes are `fixtures/fake_openrouter.py`, `fake_bot_api.py`, `fake_x_api.py` (HTTPS behind a throwaway CA from `make_pki.py`), `fake_github.py` and the recording `tap_proxy.py`. Each is labelled in the `result.txt` of every flow that uses it, and nothing a fake produced is reported as a live provider result. Principals are seeded by SQL (`fixtures/platform-seed.sql`) where a flow only needs one to exist, and labelled so; F1 pairs devices through the real pairing API. Configuration deviations from the shipped examples are limited to addresses, paths under the state directory, the CHANGE-ME secrets, `PLATFORM_ACCOUNTS` user ids and the per-flow keys a flow names, and every one is listed in the flow's `result.txt`.

The smoke cannot show: real MTProto acquisition (so the partial-acquisition path of channel-digests), live X, Meta, Threads and OpenRouter responses (the success legs of Instagram and Threads, the quality of a recap), the Export Agent's macOS keychain pairing and Swift client (an owner-run step: `swift test` of that repository is its evidence), TLS termination by `cloudflared`, systemd sandboxing and the host's group permissions on the Telegram blob root, the Raspberry Pi's glibc and 16 KiB page-size behaviour, and anything that needs more than single-machine loopback. Process lifetime and restart behaviour are exercised only where a flow stops a process on purpose.

## Safety rules the contract test checks

No script writes outside `$RATATOSKR_SMOKE_DIR` and the gitignored `evidence/`. No script contains `pkill`, `killall` or a `kill` of a pid it did not record: processes are stopped through pid files with SIGTERM, a 15 second wait and then SIGKILL of that pid. `--prune` removes only paths under the state directory. A busy port is reported with its holder and never freed.
