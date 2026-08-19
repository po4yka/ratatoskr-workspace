# Deployment target

> Status: Accepted  
> Owner: `ratatoskr-workspace`  
> Last reviewed: 2026-08-19 (revised the same day, from installing on the machine)

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
is not stable across a network recreation. **`extra_hosts` is not a Docker default and the metrics
stack does not set it**, so `host.docker.internal` does not currently resolve inside
`victoriametrics`; one line on that service in its own compose file fixes it.

## PostgreSQL

**It is a container**, `shared-postgres`, image `imresamu/postgis`, published on `127.0.0.1:5432`
with its data directory at `/mnt/nvme/shared-postgres/data`. This document said "the existing 17.7
cluster" without saying how it runs, and the difference is not cosmetic: there is no `postgres` user
on the host, `systemctl status postgresql` reports nothing, and there is no host `psql` of a matching
major version. Every administrative command enters the container, and a unit that orders itself
`After=postgresql.service` orders itself after a unit that does not exist. Found by installing.

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

Roles are provisioned once, by hand, from a checked-in SQL file, fed to `docker exec -i
shared-postgres psql -U postgres`. A container's `docker-entrypoint-initdb.d` never runs again
against a non-empty data directory, so it is not a provisioning mechanism for a cluster that already
exists.

Re-verified at milestone 10: one login role (`postgres`, superuser), and no tenant database other
than the templates and `template_postgis`. The safety gate that permits sharing still holds.

## Metrics and alerting

The host already runs VictoriaMetrics, vmalert, Grafana, Alertmanager and a node-exporter. Ratatoskr
serves Prometheus text on its operator listener, so it fits without adding anything — but only in one
arrangement, and the obvious one does not work.

The collector is a container on the `monitoring_default` bridge. A Ratatoskr process on the host
loopback is not reachable from there, and the bridge gateway address that would reach it is not
stable across a network recreation. **The arrangement is: bind the operator listener to `0.0.0.0`, and reach it from the collector across
the bridge.** `0.0.0.0` there is not an exposure by itself; what bounds it is `IPAddressAllow=` in
each unit and the host firewall below.

**There is a host firewall, and it drops this path by default.** `ufw` is active with
`INPUT policy DROP`. A container reaching a host port crosses `INPUT`, so without an explicit rule
the scrape TIMES OUT rather than being refused — which reads like a service that is down rather than
like a firewall. The rule Ratatoskr needs is narrow, and the host already carries two of the same
shape (`27124/tcp ALLOW 172.16.0.0/12`, `6333/tcp ALLOW 172.0.0.0/8`):

```bash
sudo ufw allow proto tcp from 172.19.0.0/16 to any port 9464:9466 \
  comment 'ratatoskr operator listeners, from the monitoring bridge'
```

An earlier version of this section said the arrangement was verified end to end, and it was — with a
Ratatoskr **container** joined to `monitoring_default`, where the traffic never crosses the host
firewall at all. The deployment profile then chose systemd units (ADR-0013), which puts the services
on the host side of that boundary, and nobody re-checked. At milestone 10 the collector could not
reach any of the three until the rule above existed. A verification is only evidence for the
arrangement it was performed on.

With the rule in place, verified from inside the collector's own namespace: all three
`/health/ready` answered, and `platform_readiness`, `platform_capability_available`,
`platform_operations{status}`, `platform_auth_decisions_total` and the rest arrived.

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

`borgmatic` runs at 03:00 from **root's crontab**, not from a systemd timer, so
`systemctl list-timers` does not show it. Anything that must be copied off the NVMe the same night
has to finish before then; Ratatoskr's dump is scheduled at 02:30 for that reason.

**Alerts go to Telegram.** Alertmanager's only receiver, `local-only`, was empty — no webhook, no
email, nothing — so every alert on this box resolved into its own UI and notified nobody. That was
true before Ratatoskr and independent of it, and alert rules are worth writing only behind a receiver
that reaches a person.

The bot token is read from a file, never inlined: Alertmanager 0.32 supports `bot_token_file`, the
configuration is world-readable in the repository sense, and a token in it would be a credential in
a mounted config.

```yaml
# /home/po4yka/monitoring/alertmanager.yml
receivers:
  - name: local-only
    telegram_configs:
      - bot_token_file: /etc/alertmanager/telegram_token
        chat_id: <numeric chat id>
        parse_mode: ""            # alert text is not markup and must not be parsed as any
        send_resolved: true
```

The token file needs a second read-only mount on the Alertmanager service, at mode `0600`:

```yaml
      - /home/po4yka/monitoring/telegram_token:/etc/alertmanager/telegram_token:ro
```

`parse_mode` is emptied deliberately. Alertmanager's default is HTML, and an alert body carries
labels and annotations that come from the metric — an underscore or an angle bracket in one of them
makes Telegram reject the whole message, which loses the alert at exactly the moment it matters.

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
| 4222 | NATS — a container, `ratatoskr-nats`, config in `platform/deploy/nats/` | host only |
| 5432 | PostgreSQL | host only |

Already held by other software at the time of writing, and not available: 22, 3001, 3003, 4318,
6060, 6333, 6334, **8081**, 8090, 8428, 9093, 20241. `8081` is why `ratatoskr-ingest` does not use it:
it is **crowdsec**, identified at milestone 10 with `ss -ltnp` as root — the earlier survey ran
without privilege, which is why the listener showed with no owner. It is a local API that stays.

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
with no hardening, on the machine that will hold `identity.sessions` — **is removed**. This paragraph
claimed that before it was true, so the claim now carries its evidence.

Verified on 2026-08-19. Before: `gh api repos/po4yka/RIPDPI/actions/runners` reported one runner,
`raspi-ripdpi-evidence`, id 21, Linux, ARM64, online, with the custom labels
`ripdpi-network-evidence` and `physical-android`. The registration was deleted, and the same command
now reports `total_count=0`; so does every one of the sixteen Ratatoskr repositories.

Removing it cost nothing measurable. One workflow of the twenty-four in `RIPDPI` referenced that
label, `phase16-matrix.yml`, and it is `workflow_dispatch` only. No job had run on the runner across
the last forty workflow runs, and no pull request from a fork had ever run a workflow in that
repository.

**The host-side service is removed too**, reported by the repository owner on 2026-08-19. That half is
not observable through the GitHub API — deleting a registration stops GitHub handing the runner work
and does not stop the process — so this line records what was done rather than what was measured. To
re-check it, look on the host: no `Runner.Listener` process, and no `actions-runner` service. The
commands are `sudo ./svc.sh stop && sudo ./svc.sh uninstall` in the `actions-runner` directory. This
mattered because the service ran as a user in both `sudo` and `docker`.

One thing still follows, and it is a decision rather than a step.

**Re-registering a runner is a decision.** `RIPDPI` is public, and for a `pull_request` event GitHub reads
the workflow definitions from the pull request head, so a fork can propose a workflow that targets a
self-hosted label. That repository's approval policy is `first_time_contributors`, which stops a
first-time contributor and not a returning one. If a runner is ever needed there again, set the policy
to `all_external_contributors` in the same change:

```bash
gh api -X PUT repos/po4yka/RIPDPI/actions/permissions/fork-pr-contributor-approval \
  -f approval_policy=all_external_contributors
```

`phase16-matrix.yml` is left in place and will queue without a runner if it is dispatched against a
self-hosted matrix entry. That is the honest failure: it waits visibly rather than silently doing
nothing.

## What the reflash resets

Every host-side fact outside this document is a property of the current installation and returns to
its default on a clean install: `DockerRootDir`, the `noatime,discard,commit=60` mount options,
log2ram, the Docker log caps, the crowdsec and cloudflared configuration, and the metrics stack's
network name. That is precisely why the storage layout and the port table are written down here
rather than left as host state — and it also means any observation elsewhere that begins "already
correct on this host" expires on reflash and must be re-verified.

## What milestone 10 established

Platform was installed here on 2026-08-19 and the first end-to-end slice ran on the machine. What
that changed in this document is marked above; what it proved is:

- the `aarch64` artifact built in a `debian:12` container runs on the 16 KiB-page kernel — three
  binaries, `check-config` clean, migrations applied, no page-size or `ring`/rustls problem;
- one command shape from two doors: a client through `POST /v2/captures` and a webhook source
  through `POST /v2/ingest/webhooks/{id}` both produced `cmd.content.capture.requested.v1`, and the
  scheduler produced its own, all three published to `ratatoskr_commands`;
- the three least-privilege database roles hold, on this cluster: neither ingest nor scheduler can
  read anything in `identity`;
- the dump restores, on this cluster, into an ICU-collated scratch database with every constraint
  and index intact.

Two things it corrected in the software rather than in a document: a startup rule that checked
whether the bus credential EXISTS rather than whether the process could read it, and a database
grant written from reading a request handler instead of everything the handler calls.
