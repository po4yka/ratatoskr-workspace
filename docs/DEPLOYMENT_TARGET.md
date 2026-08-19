# Deployment target

> Status: Accepted  
> Owner: `ratatoskr-workspace`  
> Last reviewed: 2026-08-19

Ratatoskr runs on **one machine**, and there will not be a second one. This document is the
canonical description of that machine and the contracts that depend on it: the storage layout, the
port allocations, and who supervises what. Every repository's `AGENTS.md` carries a short
`## Deployment target` section stating the same constraints in the form an agent needs while working
inside that repository alone; this file is where the detail lives, and it is the one to change first.

Before this file existed, the only place in the workspace that named the machine was
`legacy/ratatoskr/.claude/skills/pi-deploy/SKILL.md` — the retired archive that `README.md` tells
everyone to ignore. Sixteen live repositories describe PostgreSQL, NATS, Chromium, pgvector, S3 and
"horizontal instances" and name no machine at all, so the default inference was a cloud. That is the
gap this file closes.

## The host

| | |
|---|---|
| Board | Raspberry Pi 5 Model B Rev 1.1 |
| CPU | 4 × Cortex-A76, 2.4 GHz |
| Memory | 15 GiB usable. Swap is 4 GiB of zram; **there is no disk swap** |
| Architecture | `aarch64` |
| Kernel page size | **16 KiB** (`kernel_2712.img`). `kernel8.img` in `/boot/firmware` is the 4 KiB fallback, selectable with one `kernel=` line |
| Userland | Debian 12 (bookworm) class, **glibc 2.36**, arm64 |
| Release target triple | `aarch64-unknown-linux-gnu` |
| Boot | `BOOT_ORDER=0xf416`, `PCIE_PROBE=1` — the bootloader already prefers NVMe over the SD card |

Verified on the running machine, not inferred. A binary built in a `debian:12` arm64 container starts
and completes a full lifecycle here — bind, `/health/ready` 200, `/metrics`, SIGTERM, exit 0 — with
no page-size, glibc or `ring`/rustls problem. Re-run that check after the reflash; it is cheap and it
is the only thing that proves the ABI.

## Storage

The root filesystem is currently an SD card. **PostgreSQL and JetStream must never write to the boot
device**: their pattern is small synchronous fsyncs, which is the worst case for flash wear, and an
SD card that wears out takes the root filesystem with it.

The bootloader is already configured to prefer NVMe, so the reflash should put the root filesystem
there and retire the SD card from the write path entirely. Until it does, the layout below is what
keeps durable state off it either way.

| Purpose | Path | Device |
|---|---|---|
| PostgreSQL data | `/mnt/nvme/ratatoskr/postgres` | NVMe, 466 GB |
| `JetStream` store | `/mnt/nvme/ratatoskr/nats` | NVMe |
| Service logs | `/mnt/nvme/ratatoskr/logs` | NVMe |
| Database dumps | `/mnt/nvme/backups/ratatoskr` | NVMe |
| Off-host copies | `/mnt/backup/borg` | SATA SSD, 954 GB |

Two rules follow, and both are contracts rather than advice:

- **An absolute path, never a named volume.** A named Docker volume lands wherever `DockerRootDir`
  points, which is host state no repository owns and which a reflash resets to the boot device.
- **`/mnt/backup` is a second volume on the same machine.** It survives a disk failure and does not
  survive losing the Pi. Nothing may treat it as an off-host replica — `vault`'s policy of blocking
  `healthy` until a verified remote copy exists is not satisfied by it.

## Supervision

**systemd units, one per role.** Not Compose. The reasons that decide it:

- per-service Unix users and `ProtectSystem=`/`NoNewPrivileges=` are the isolation this host needs,
  and they become meaningful once the co-resident CI runner is gone;
- cgroup v2 is available (`cpuset cpu io memory pids`), so `MemoryMax=` and `CPUQuota=` are real.

Three consequences that must be written into every unit, because each is a live failure on this host
rather than a precaution:

- **`TimeoutStopSec=` must exceed the process's own shutdown ceiling.** Platform validates
  `drain + grace <= 120s`; systemd's default `TimeoutStopSec` is 90s, so a configuration the process
  accepts would be `SIGKILL`ed 30 seconds early. Set `130s`.
- **Journald is not a safe default here.** `/var/log` is a 128 MiB log2ram tmpfs, already ~79% full,
  and the two journald drop-ins disagree (`SystemMaxUse=500M` on a 128 MiB filesystem). A service
  writing JSON to stdout at volume either fills it or forces a flush onto the boot device. Write logs
  to `/mnt/nvme/ratatoskr/logs` and rotate them, or bound the unit's journald use explicitly.
- **Start ordering is load-bearing.** Only one process applies migrations; the others check the
  schema and refuse to start without it. An `After=`/`Requires=` chain is required, and
  `StartLimitIntervalSec=`/`StartLimitBurst=` must be loose enough that the first boot after a schema
  change does not latch a dependent unit into `failed` with nothing to retry it.
- **`Type=exec`, never `Type=notify`.** No Ratatoskr binary calls `sd_notify`, so `notify` would time
  out and kill a healthy process, and `WatchdogSec=` would `SIGABRT` it on the first interval.

A service that must be scraped by the container-resident metrics stack is reached from a container
through `host.docker.internal` with `extra_hosts: host-gateway` — the bridge gateway address itself
is not stable across a network recreation.

## PostgreSQL

Ratatoskr uses the **existing 17.7 cluster** on this host rather than its own instance. The check
that permits it: that cluster has exactly one superuser and one login role and holds no other
tenant's databases, so a database owned by a Ratatoskr role is as isolated as a separate instance
would be, and a second `shared_buffers`, WAL writer and checkpointer on four cores is avoided.

Two properties of that cluster are now contracts:

- **Major version 17.** Development and CI must pin the same major, or the only verification the SQL
  gets is against a version the deployment does not run.
- **Collation is stated, never inherited.** The cluster's existing databases use the libc provider
  (`datlocprovider=c`, glibc 2.36). Ratatoskr's database is **not** created that way: it is created
  explicitly with `template template0 locale_provider icu icu_locale 'und-x-icu'`, which the same
  cluster supports per database, and development and CI create theirs identically.

  The direction matters and is deliberate. A glibc collation changes silently across a distribution
  upgrade — and `apt-daily-upgrade.timer` is enabled on this host — while PostgreSQL tracks the ICU
  version and warns on a mismatch. A text btree index that no longer holds is not a performance
  problem: if `identities_provider_external_id_key` stops holding, one external account maps to two
  internal users, which is an authentication defect. Inheriting from `template1` is what produced
  three different collations across the three environments that are supposed to be checking each
  other, so no `create database` anywhere may omit the locale.

Roles are provisioned once, by hand, from a checked-in SQL file. A container's
`docker-entrypoint-initdb.d` never runs again against a non-empty data directory, so it is not a
provisioning mechanism for a cluster that already exists.

## Metrics and alerting

The host already runs VictoriaMetrics, vmalert, Grafana, Alertmanager and a node-exporter. Ratatoskr
serves Prometheus text on its operator listener, so it fits without adding anything — but only in one
arrangement, and the obvious one does not work.

The collector is a container on the `monitoring_default` bridge. A Ratatoskr process on the host
loopback is not reachable from there, and the bridge gateway address that would reach it is not
stable across a network recreation. **The arrangement is: bind the operator listener to `0.0.0.0`
inside the container or unit namespace, publish no host port for it, and scrape it by name from
`monitoring_default`** — exactly as vmalert already reaches `victoriametrics:8428`. `0.0.0.0` there
is not an exposure: nothing outside the host can route to it.

Verified end to end on this host, with the real artifact rather than a stand-in: a `ratatoskr-scheduler`
container joined to that network answered `/health/ready` by name from inside the collector's
namespace, VictoriaMetrics reported the target `up`, and `platform_readiness{role="scheduler"}` and
`platform_build_info` arrived in the time series database. The container and the scrape entry were
then removed, because a scrape target for a service that is not deployed is a permanently failing
target; the entry lands with the deployment units.

```yaml
# /home/po4yka/monitoring/promscrape.yml
  - job_name: ratatoskr
    scrape_interval: 15s
    scrape_timeout: 5s
    static_configs:
      - targets: ["ratatoskr-edge:9464", "ratatoskr-ingest:9465", "ratatoskr-scheduler:9466"]
        labels:
          site: terrace
          system: ratatoskr
```

VictoriaMetrics is started without `-promscrape.configCheckInterval`, so a change to that file takes
effect on `docker kill -s HUP victoriametrics` and not before.

**Alertmanager's only receiver, `local-only`, is empty** — no webhook, no email, nothing. Every alert
on this box already resolves into its own UI and notifies nobody, which is true today and has nothing
to do with Ratatoskr. Alert rules are worth writing only behind a receiver that reaches a person, so
that is a prerequisite rather than a follow-up.

The node-exporter runs with `--collector.disable-defaults`, so the host has no filesystem or disk
series at all: the two failure modes that matter most here — storage wear and a full `/var/log` —
have no expressible query.

## Ports

A port on this host is an **allocation**, not a default. Never answer a bind failure by widening a
bind to `0.0.0.0`.

| Port | Owner | Reachability |
|---|---|---|
| 8080 | `ratatoskr-edge` public API | `cloudflared` tunnel |
| 8181 | `ratatoskr-ingest` webhook adapter | `cloudflared` tunnel |
| 9464 / 9465 / 9466 | edge / ingest / scheduler operator listener | host only |
| 4222 | NATS | host only |
| 5432 | PostgreSQL | host only |

Already held by other software at the time of writing, and not available: 22, 3001, 3003, 4318,
6060, 6333, 6334, **8081**, 8090, 8428, 9093, 20241. `8081` is why `ratatoskr-ingest` does not use it:
it is held by a process that could not be attributed to an owner, and it must be identified during
the cleanup.

## Exposure

`cloudflared` is the only public path and it reaches the public listeners only. Operator surfaces —
`/health/*`, `/metrics`, `/version`, PostgreSQL, NATS — are never reachable from outside the host;
operators reach them over Tailscale.

Because the tunnel terminates TLS and adds its own headers, "internal headers are not trusted from
public ingress" means the header set arriving at a public listener is attacker-influenced up to
whatever the tunnel overwrites. A service may trust no inbound header it did not itself mint.

The trust boundary is the whole host: every Ratatoskr service shares one kernel, so OS-level
isolation between them defends against a compromised process, not against a compromised host. The
`po4yka-RIPDPI` self-hosted GitHub Actions runner — which ran as a user in both `sudo` and `docker`,
with no hardening, on the machine that will hold `identity.sessions` — is removed as part of the
cleanup. It is named here so that reintroducing one is a decision rather than an accident.

## What the reflash resets

Every host-side fact outside this document is a property of the current installation and returns to
its default on a clean install: `DockerRootDir`, the `noatime,discard,commit=60` mount options,
log2ram, the Docker log caps, the crowdsec and cloudflared configuration, and the metrics stack's
network name. That is precisely why the storage layout and the port table are written down here
rather than left as host state — and it also means any observation elsewhere that begins "already
correct on this host" expires on reflash and must be re-verified.
