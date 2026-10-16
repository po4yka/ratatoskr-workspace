# Deployment target

> Status: Accepted  
> Owner: `ratatoskr-workspace`  
> Last reviewed: 2026-10-13 (PostgreSQL data path in the storage table, operator-port reachability, `ratatoskr.target` and the Clients section; no host fact re-verified)

> **The host is frozen as of 2026-08-21.** Nothing is deployed to it, nothing on it is changed, and
> the drift between it and `main` is not tracked. The machine remains in scope for exactly one
> purpose: it is the performance budget every service must fit. Read the table below as a
> constraint on code being written, not as an environment to operate. The freeze lifts only when
> the owner says so.

Ratatoskr runs on **one machine**, and there will not be a second one. This document is the
canonical description of that machine and the contracts that depend on it: the storage layout, the
port allocations, and who supervises what. Every repository's `AGENTS.md` carries a short
`## Deployment target` section stating the same constraints in the form an agent needs while working
inside that repository alone; this file is where the detail lives, and it is the one to change first.

Before this file existed, the only place in the workspace that named the machine was a `pi-deploy`
skill in the retired `ratatoskr` backend, an archive that has since been deleted. Sixteen live repositories describe PostgreSQL, NATS, Chromium, pgvector, S3 and
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
| PostgreSQL data | `/mnt/nvme/shared-postgres/data` (the `shared-postgres` container, see [PostgreSQL](#postgresql)) | NVMe, 466 GB |
| `JetStream` store | `/mnt/nvme/ratatoskr/nats` | NVMe |
| Service logs | `/mnt/nvme/ratatoskr/logs` | NVMe |
| Database dumps | `/mnt/nvme/backups/ratatoskr` | NVMe |
| Off-host copies | `/mnt/backup/borg` | SATA SSD, 954 GB |
| Telegram blobs | `/mnt/nvme/ratatoskr/blobs/ratatoskr-telegram` | NVMe |
| Notes blobs | `/mnt/nvme/ratatoskr/blobs/ratatoskr-notes`, owner `ratatoskr-notes:ratatoskr-notes-blobs`, mode 2750 (setgid) | NVMe |
| Site bundles | `/mnt/nvme/ratatoskr/sites`, owner `ratatoskr-sites:ratatoskr-sites-bundles`, mode 2750; gateway reads through the group | NVMe |
| Sites blobs | `/mnt/nvme/ratatoskr/blobs/ratatoskr-sites`, owner `ratatoskr-sites:ratatoskr-sites`, mode 0700 | NVMe |
| Notes working trees | `/mnt/nvme/ratatoskr/notes/trees`, owner `ratatoskr-notes-sync:ratatoskr-notes-trees`, mode 2770 (setgid); one `<id>` for each `sync` connection, folders 2770, files 0660 | NVMe |
| Notes `ob` client state | `/mnt/nvme/ratatoskr/notes/clients`, owner `ratatoskr-notes-sync:ratatoskr-notes-sync`, mode 0700; one `<id>` for each `sync` connection, mode 0700 | NVMe |
| Notes sync journal | `/var/log/journal/<machine id>.ratatoskr-notes-sync` (`LogNamespace=ratatoskr-notes-sync` of the sync unit), owner `root:systemd-journal`, mode 2755, with an ACL and a default ACL that name the group `ratatoskr-notes` (`r-x`) and no other group; at most 8 MiB (`journald@ratatoskr-notes-sync.conf`) | `/var/log` (log2ram tmpfs) |
| Notes login credentials | `/run/ratatoskr-notes` (`RuntimeDirectory=` of the notes service unit, owner `ratatoskr-notes`), with `credentials/<id>/` (directory 0700, files 0600) only while a login runs | tmpfs (`/run`); never written to a disk |
| Obsidian Headless client | `/opt/ratatoskr-ob` (owner root; no file writable by group or other), and `/usr/bin/ob`, a link to its `cli.js` | root filesystem |

Two rules follow, and both are contracts rather than advice:

- **An absolute path, never a named volume.** A named Docker volume lands wherever `DockerRootDir`
  points, which is host state no repository owns and which a reflash resets to the boot device.
- **A service that reads another service's blobs does it through a group, read-only.** The Telegram
  webhook writes documents under `/mnt/nvme/ratatoskr/blobs/ratatoskr-telegram`, and the extractor
  reads them. The directory is created `install -d -o ratatoskr-telegram-webhook -g
  ratatoskr-telegram-blobs -m 2750 /mnt/nvme/ratatoskr/blobs/ratatoskr-telegram` (setgid, so new
  files inherit the group); the webhook unit has the path in `ReadWritePaths`, `UMask=0027` and
  `SupplementaryGroups=ratatoskr-telegram-blobs`; the extractor unit has
  `SupplementaryGroups=ratatoskr-telegram-blobs` and the path in `ReadOnlyPaths`. The extractor never
  writes there. If the group does not exist, extractor runs fail with `blob_unreadable`, which is host
  state no repository can repair. The group is a host prerequisite, not something a unit file creates.
  The notes blob root follows the same rule with the read group `ratatoskr-notes-blobs`:
  `ratatoskr-notes` writes it with `UMask=0027` (planned, notes task 6.8), so a blob is mode 0640 with that group, and
  `ratatoskr-knowledge` and `ratatoskr-sites` (SITE-025, design D3) are the only members of the
  group. The deploy role creates the group, the memberships and the root
  (`deploy/ansible/group_vars/all/host.yml`), and the Molecule verify case `notes_blob_read_group`
  checks them.
- **`/mnt/backup` is a second volume on the same machine.** It survives a disk failure and does not
  survive losing the Pi. Nothing may treat it as an off-host replica — `vault`'s policy of blocking
  `healthy` until a verified remote copy exists is not satisfied by it.

The notes units run `ob` as `ratatoskr-notes-sync`, which creates the working tree `trees/<id>` and
the client state `clients/<id>` of each `sync` connection (owner decision B of 2026-10-14). The
trees root is setgid with the group `ratatoskr-notes-trees`, mode 2770, and the sync and login
units have `UMask=0007` (OBS-024, decision 7.11). So each tree gets that
group, folders get mode 2770 and files mode 0660. `ratatoskr-notes` and `ratatoskr-notes-sync` are
the members of the group: the notes service reads the trees through it and writes the delivered
writes of the `sync` channel into them, and `ob` changes what the notes service wrote. The deploy
role migrates a tree made before OBS-024 (folders 2750, files 0640) once, to 2770 and 0660. The
migration runs as `ratatoskr-notes-sync`, never as root, and follows no link, because both service
users can write inside the trees; a root-owned marker file,
`/mnt/nvme/ratatoskr/notes/.trees-migrated-obs024-7.11`, records that it ran.
Each client state
holds the Obsidian Sync token and the derived end-to-end key in plain text, so only
`ratatoskr-notes-sync` may enter the clients root, and no other user is a member of its group. The
login and cleanup units have both roots in `ReadWritePaths=` with no `-` prefix, so systemd fails
the unit if a root does not exist. The deploy role creates `/mnt/nvme/ratatoskr/notes` (root,
0755) and the two roots, and the Molecule verify case `notes_trees_and_clients` checks them.
`/run/ratatoskr-notes` is on tmpfs, so the credential files of a login never reach a disk; at
start, the notes service removes `/run/ratatoskr-notes/credentials`.

The sync unit logs to the journal namespace `ratatoskr-notes-sync`, not to the system journal (owner
decision A of 2026-10-14). The notes service reads that namespace with `journalctl` and is not in
the group `systemd-journal`. The deploy role installs
`/etc/tmpfiles.d/ratatoskr-notes-journal.conf`, which creates the namespace directory and replaces
its ACL and default ACL, and those of its journal files, with entries for the group
`ratatoskr-notes` only. The replacement removes the group `adm`, which Debian puts in the default
ACL of `/var/log/journal`. When the service cannot read the namespace, it logs
`notes.sync.journal_unreadable` at its start.

The namespace directory is on the log2ram tmpfs of `/var/log` (see below), which has about 27 MiB
free. The deploy role installs `/etc/systemd/journald@ratatoskr-notes-sync.conf`: at most 8 MiB
(`SystemMaxUse=8M`) in files of 2 MiB (`SystemMaxFileSize=2M`), no write when less than 8 MiB of
`/var/log` is free (`SystemKeepFree=8M`), and 4 MiB in `/run` while `/var/log` is not writable.
The Molecule verify case `notes_journal_namespace` logs a line through the namespace and checks the
ACLs, the limit that journald reports, and that only `ratatoskr-notes` reads the line. Neither is
checked on the real host (systemd 252) yet.

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
- **Start ordering is load-bearing.** Only one process applies the schema; the others check it and
  refuse to start without it. An `After=`/`Requires=` chain is required, and
  `StartLimitIntervalSec=`/`StartLimitBurst=` must be loose enough that the first boot on a fresh
  database does not latch a dependent unit into `failed` with nothing to retry it.
- **`Type=exec`, never `Type=notify`.** No Ratatoskr binary calls `sd_notify`, so `notify` would time
  out and kill a healthy process, and `WatchdogSec=` would `SIGABRT` it on the first interval.

**Every unit joins `ratatoskr.target`.** Platform ships it in `deploy/systemd/ratatoskr.target`
because Platform is installed first. Each unit carries `PartOf=ratatoskr.target` and
`WantedBy=ratatoskr.target`, so `systemctl stop ratatoskr.target` stops the whole deployment and
boot starts it. The PostgreSQL and NATS containers are not members and stay up. A new unit in any
repository carries the same two lines.

**A template unit is installed and never started by the playbook.** `ratatoskr-notes` ships four
template units (`*@.service`). The instance name is the connection id, a lowercase UUID. Each unit
runs as `ratatoskr-notes-sync` and starts only `/usr/bin/ob`, `/bin/rm` or `/bin/sh -c`, with `HOME` and `XDG_CONFIG_HOME` set to the
client state `/mnt/nvme/ratatoskr/notes/clients/<id>` of the connection, and the working tree
`/mnt/nvme/ratatoskr/notes/trees/<id>`:

| Unit | Type | Started by | Does |
|---|---|---|---|
| `ratatoskr-notes-sync-pull@.service` | long-running | the Sync supervisor of the notes service, for each `sync` connection whose write mode is off | `ob sync-config` with the mode `pull-only` and `--conflict-strategy conflict`, then `ob sync --continuous` on the working tree of the connection; logs to the journal namespace `ratatoskr-notes-sync` |
| `ratatoskr-notes-sync-bidi@.service` | long-running | the Sync supervisor of the notes service, for each `sync` connection whose write mode is on | the same as the pull unit, with the mode `bidirectional` |
| `ratatoskr-notes-login@.service` | oneshot | the notes service, at the connect of a `sync` connection | `ob login`, then `ob sync-setup`; reads the secrets with `LoadCredential=` from `/run/ratatoskr-notes/credentials/<id>/` |
| `ratatoskr-notes-cleanup@.service` | oneshot | the notes service, at a disconnect and after a failed login | `ob sync-unlink`, then removes the working tree and the client state of the connection |

Each write mode has its own fixed sync unit, with the mode as a literal argument and no
`EnvironmentFile=` (OBS-024, design D5). The notes service stops the unit of the other mode before
it starts one, so at most one sync unit of a connection runs. The sync and login units run with
`UMask=0007`: the notes service and `ratatoskr-notes-sync` share the group `ratatoskr-notes-trees`,
the trees root is `2770`, and each folder of a tree is `2770` and each file `0660`, so the notes
service can write a delivered write into a tree and `ob` can change it (OBS-024, decision 7.11).

The playbook installs each unit that `ratatoskr_template_units` in `services.json` lists,
byte-identical to its pin, and reloads systemd. It does not enable or start a template unit. At the
current pin, notes ships the login, cleanup and the two sync units. One polkit rule,
`/etc/polkit-1/rules.d/60-ratatoskr-template-units.rules`, lets
`ratatoskr-notes` start and stop an instance of these units whose instance name is a lowercase
UUID, and allows nothing else: no other verb, unit, instance name or user, and no change to a unit
file. The Molecule verify case `notes_sync_unit` checks this with `pkcheck`. A template unit does not
join `ratatoskr.target`, and it starts only a program of a reviewed allow-list (`/usr/bin/ob`,
`/bin/rm`, `/bin/sh -c`), never a binary that the repository builds; so it needs no release
artifact (openspec `release-artifacts`).

**Memory budget of a `sync` connection: 512M (PROVISIONAL).** Each `sync` connection runs one
Node.js process, `ob sync --continuous`, in its own instance of `ratatoskr-notes-sync-pull@.service`
or `ratatoskr-notes-sync-bidi@.service`, so
the memory of the notes deployment grows by this budget for each connection. 512M is a placeholder
for `MemoryMax=` of the sync unit, not a measurement. Spike 3.1 of `add-notes-vault-connections`
measures the resident memory of one continuous sync with a 1 GiB fixture vault on a host of this
class, and the sync unit then sets `MemoryMax=` to that value plus 50 %. Replace this paragraph
with the measured budget when the spike is recorded. At most
`RATATOSKR__CONNECTIONS__MAX_LOGINS` (default 2) login units run at the same time.

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

**One database, one role per service, provisioned in a fixed order (R3-11).** Every service connects
to the single database `ratatoskr` on port 5432 as its own role, `ratatoskr_<service>` for
`chatgpt`, `claude`, `knowledge`, `channel_digests`, `telegram` (the webhook and the dispatcher share
it), `x`, `instagram`, `threads`, `vault`, `github` and `extractor`, and every schema is namespaced
by its service. The examples of GitHub, Vault, X, Instagram and Threads named other databases and the
development compose port 5435 before Round 3; they now name the shared database, and their own
compose files keep their development databases as a development convenience. The order is: Platform's
`deploy/postgres/01-database-and-roles.sql`, the first start of Edge (it applies `schema.sql`),
Platform's `02-grants.sql`, and then each service's `deploy/postgres/role.sql` before that service's
first start. Each role file creates the role without a password (set it with `\password`), withholds
every privilege except `connect` and `create` on the database, and revokes the rights on schema
`public`. Knowledge's file additionally runs `create extension if not exists vector`, which only a
PostgreSQL administrator may do because pgvector is not a trusted extension, and grants `usage` on
schema `public` because the `vector` type lives there; that extension is the reason its file is run
by an administrator and not by the service. The harness test `postgres_roles.rs` fails
when a deploy example names a role no checked-in file creates, or a host, port or database other than
`127.0.0.1:5432/ratatoskr`.

Re-verified at milestone 10: one login role (`postgres`, superuser), and no tenant database other
than the templates and `template_postgis`. The safety gate that permits sharing still holds.

## Notes and site bus consumers

The source pins define these consumers in Platform's stream table. Edge provisions the durables;
the owning service consumes them under its deployed NATS identity. The harness tests `bus_acl` and
`bus_durables` compare the filters, ownership and vendored service fragments. This source evidence
does not show that a durable exists on the frozen host.

| Durable | Consumer | Filters |
|---|---|---|
| `ratatoskr_notes_write_requests` | Notes (`NOTES`) | `cmd.notes.file.write_requested.v1` |
| `platform_notes_conflict_projection` | Edge (`EDGE`) | `evt.notes.conflict.>` (raised and resolved) |
| `platform_site_events` | Edge (`EDGE`) | `evt.sites.release.published.v1`, `evt.sites.draft.changed.v1` |

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
sudo ufw allow proto tcp from 172.19.0.0/16 to any port 9464:9468 \
  comment 'ratatoskr operator listeners, from the monitoring bridge'
```

An earlier version of this section said the arrangement was verified end to end, and it was — with a
Ratatoskr **container** joined to `monitoring_default`, where the traffic never crosses the host
firewall at all. The deployment profile then chose systemd units (ADR-0013), which puts the services
on the host side of that boundary, and nobody re-checked. At milestone 10 the collector could not
reach any of the three until the rule above existed. A verification is only evidence for the
arrangement it was performed on.

`9464:9468` are the only operator ports opened to the monitoring bridge. Every other operator port in
the table, including the new `9081` to `9088`, `9095`, `9469`, `9470` and `9570`, is host only until
someone deliberately opens it, and opening one means widening the rule above and this sentence
together.

One detail the rule depends on: `host-gateway` resolves to the address of the DEFAULT bridge,
172.17.0.1, not to the gateway of the network the collector is on. ufw matches on SOURCE, so the
rule names the subnet the collector lives on and not the address it dials — a rule written the other
way round looks right and matches nothing.

With both in place, verified end to end: all three targets report `up` in VictoriaMetrics, and
`platform_readiness` for each role, `platform_capability_available` for each capability, and the
outbox and operation gauges are in the time series database.

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
| 8080 | `ratatoskr-edge` public API; also the base URL Telegram's Platform client targets | `cloudflared` tunnel |
| 8181 | `ratatoskr-ingest` webhook adapter | `cloudflared` tunnel |
| 8183 | `ratatoskr-sites-gateway` public listener | `cloudflared` tunnel, loopback only |
| 9473 | `ratatoskr-sites-gateway` operator listener | Host only |
| 8182 | `ratatoskr-telegram-webhook` public listener | `cloudflared` tunnel |
| 8091 | `ratatoskr-knowledge` domain API (`/v1/k`, `/v1/capabilities`, `/internal/search`, `/internal/user-content/*`), a dedicated listener (`RATATOSKR__API__LISTEN_ADDRESS`) next to the operator listener `9081` | loopback; reached only through Edge and Platform's library client |
| 8092 | `ratatoskr-github` domain API (`/v1/gh`), plus its internal reader routes, which Edge never exposes | loopback; reached only through Edge |
| 8093 | `ratatoskr-vault` domain API (`/v1/vault`); no listener yet, so Edge reports its capability as stale, which is truthful | loopback; reached only through Edge |
| 8094 | `ratatoskr-social` domain API (`/v1/social`); no listener yet, same as `8093` | loopback; reached only through Edge |
| 8095 | `ratatoskr-ai-archive` domain API (`/v1/ai`); no listener yet, same as `8093` | loopback; reached only through Edge |
| 8096 | `ratatoskr-chatgpt` archive receipt (`/v1/ai-archives/receipt`, `/v1/capabilities`), a dedicated listener (`RATATOSKR__RECEIPT__LISTEN_ADDRESS`) next to the operator listener `9085` | loopback; reached only through Platform archive acceptance |
| 8097 | `ratatoskr-claude` archive receipt (`/v1/ai-archives/receipt`, `/v1/capabilities`), a dedicated listener (`RATATOSKR__RECEIPT__LISTEN_ADDRESS`) next to the operator listener `9086` | loopback; reached only through Platform archive acceptance |
| 8098 | `ratatoskr-channel-digests` API (`/v1/manifests`, `/v1/subscriptions`, `/v1/results`, `/ready`) | loopback; Platform and Knowledge only |
| 8099 | `ratatoskr-notes` domain API (`/v1/notes`), a dedicated listener (`RATATOSKR__API__LISTEN_ADDRESS`) next to the operator listener `9471` | loopback; reached only through Edge |
| 8100 | `ratatoskr-sites` domain API (`/v1/sites`, and the Content Delivery API), a dedicated listener (`RATATOSKR__API__LISTEN_ADDRESS`) next to the operator listener `9472` | loopback; reached only through Edge. Edge trusts `X-Ratatoskr-Client-IP` on the content routes only from `127.0.0.83`, the source address of the sites gateway (`RATATOSKR__SITES__GATEWAY_PEER`, SITE-026) |
| 9081 | `ratatoskr-knowledge` operator listener | host only |
| 9082 | `ratatoskr-instagram` operator listener | host only |
| 9083 | `ratatoskr-instagram` product API (`POST /v1/captures`, data exports) | host only |
| 9084 | `ratatoskr-threads` operator listener | host only |
| 9085 | `ratatoskr-chatgpt` operator listener (moved from 9084) | host only |
| 9086 | `ratatoskr-claude` operator listener (moved from 9084) | host only |
| 9087 | `ratatoskr-x` operator listener (moved from 8080) | host only |
| 9088 | `ratatoskr-extractor` operator listener (moved from 9467) | host only |
| 9095 | `ratatoskr-github` operator listener | host only |
| 9464 / 9465 / 9466 | edge / ingest / scheduler operator listener | host and monitoring bridge only |
| 9467 | `ratatoskr-telegram-webhook` operator listener | host and monitoring bridge only |
| 9468 | `ratatoskr-telegram-dispatcher` operator listener | host and monitoring bridge only |
| 9469 | `ratatoskr-channel-digests` API operator listener | host only |
| 9470 | `ratatoskr-channel-digests` worker operator listener | host only |
| 9471 | `ratatoskr-notes` operator listener | host only |
| 9472 | `ratatoskr-sites` operator listener | host only |
| 9570 | `ratatoskr-vault` operator listener | host only |
| 4222 | NATS client, a container, `ratatoskr-nats`, config in `platform/deploy/nats/`; the server binds `0.0.0.0` inside the container and the port is published on `127.0.0.1` only, and it requires an nkey; the largest message it accepts is 8 MiB (`max_payload: 8MB`, up from the 1 MiB default); every identity except Edge subscribes only to its own reply prefix, `_INBOX_telegram`, `_INBOX_chatgpt`, `_INBOX_claude`, `_INBOX_x`, `_INBOX_instagram`, `_INBOX_threads`, `_INBOX_extractor`, `_INBOX_extractor_browser_worker`, `_INBOX_knowledge`, `_INBOX_github`, `_INBOX_vault`, `_INBOX_channel_digests`, `_INBOX_notes` or `_INBOX_sites` (R3-01), so one service cannot read another's JetStream deliveries, and a service built before Round 3 times out under this ACL | host only |
| 8222 | NATS monitoring, the same container; bound inside the container as above and published on `127.0.0.1` only | host only |
| 5432 | PostgreSQL | host only |

Four compiled defaults moved in XR-021, because two services cannot bind one port: ChatGPT 9084 to
9085, Claude 9084 to 9086, X 8080 to 9087 (8080 is Edge's) and the extractor 9467 to 9088 (9467 is
the Telegram webhook's). Round 2 of XR-021 added two dedicated listeners rather than moving a
default: ChatGPT's receipt (8096) and Knowledge's API (8091) were served on their operator
listeners (9085 and 9081) before, so Edge's probe of the allocated port was refused; each now binds
its allocated port separately and the operator listener serves health, metrics and version only.
The harness test `port_allocation.rs` in this repository fails when this
table lists a port twice or omits a documented listener, and when a repository's deploy examples bind
a port that is not in the table or that another listener already holds.

The Telegram webhook (8182) signs its Platform identity assertions with an Ed25519 key that is
created once on the host: `ratatoskr-telegram-webhook assertion-key generate <path>` writes the seed
(mode 0600, `root:ratatoskr-telegram-secrets 0640` once installed at
`/etc/ratatoskr/secrets/telegram-platform-signing-key`) and prints the public key, which goes into
`RATATOSKR__IDENTITY__ASSERTION_KEY` of `/etc/ratatoskr/edge.conf` (R3-12). Without it
`telegram.mini_app` is unavailable and `/v1/sessions/telegram` refuses every exchange with 401. The
procedure is in `ratatoskr-telegram`'s `deploy/README.md` and Platform's `deploy/README.md`.

A smoke that needs Edge's routes must run on these production loopback ports, one flow at a time,
because Edge's validation of the allocated route ports is a deliberate contract and not a defect
(R3-17). The only exception is PostgreSQL: the native smoke under `integration/native/` runs its own
cluster on `127.0.0.1:54329`, because a database URL is configuration. The GitHub example binds its
database to 5432, not to the development compose port 5435.

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

The five domain API listeners above bind only to `127.0.0.1`. Their capability document is
`GET /v1/capabilities` on the same listener; Edge owns the public prefix, authenticates the client,
strips inbound `x-ratatoskr-*` headers, and mints the bounded identity claims before proxying.

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

## Clients

No client runs on this host. The mobile apps, the browser extension and the macOS export agent run
on the user's devices, and each one reaches Ratatoskr only through Edge's public API on 8080, through
the `cloudflared` tunnel. None of them needs a port in the table above.

The web client is the exception that is not decided yet. It builds to a static bundle, and **no
repository serves that bundle**: Platform has no static route, and the port table allocates no port
for it. Where the bundle is served is an open decision for the owner. Whatever is chosen gets a row
in the port table, or a route on Edge, before it is deployed.

Whatever serves the bundle must send `Content-Security-Policy: frame-ancestors 'none'` and
`X-Frame-Options: DENY` with every page. The web client holds the consent page of a site sign-in
(SITE-027), and a page that another site can frame lets that site make the owner click "Sign in"
without seeing it. `integration/nginx/web-operational.conf` sends both headers in the
`web-operational` profile; no Ansible role serves the bundle yet.

## Provisioning

`deploy/ansible/` in this repository provisions this host from a clean Debian 12 install (ADR-0009,
openspec `host-provisioning`). It installs each enrolled service from the files its own repository
ships at the commit `workspace.lock` pins, and from the attested `linux/arm64` artifact that
repository publishes for that commit. It runs the PostgreSQL files in the order above, generates
every host secret on the host, and recreates the host facts listed in the next section. A second
run changes nothing. Its README has the command and the operator's vault file.

For the notes template units, the role `nodejs` installs Node.js 22 from the NodeSource apt
repository, with a signing key checked against its recorded sha256, and `obsidian-headless` 0.0.14
(`ob`) in `/opt/ratatoskr-ob` (ADR-0010: from npm on the host, never in a published image). It runs
`npm ci --omit=dev --ignore-scripts` from the committed lockfile in
`deploy/ansible/roles/nodejs/files/obsidian-headless/`, which holds a sha512 integrity for each
package, so no lifecycle script runs. The native module of `better-sqlite3` is the release prebuilt
for the Node.js ABI and the host architecture, checked against its recorded sha256 before it is put
in place; the playbook stops when no prebuilt is recorded for the host. Only root writes the prefix.
`/usr/bin/ob` links to the `cli.js` of the package. The Molecule verify case `notes_sync_unit`
checks the tree package by package and runs `ob --help` as `ratatoskr-notes-sync`.

While the freeze statement at the top of this document stands, the playbook refuses this host
before its first change. Lifting the freeze is an edit to this document, and nothing else lifts it.

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

Two of those bullets name things that have changed since. The public paths are now `/v1`, and the
migration ledger is now one `schema.sql`. The bullets keep the names the run used, because this
evidence describes the arrangement as it stood on 2026-08-19 and not the one the repositories carry
today. A verification is only evidence for the arrangement it was performed on.

Measured while it ran, which closes a guess this document has carried since it was written: the
three services use **3, 2 and 2 MiB** of resident memory serving traffic, and NATS 7 MiB. The
`MemoryMax=` ceilings in the units — 768M, 512M and 256M — were sized by analogy to the host's other
containers, and are two orders of magnitude above what the processes actually take. They stay: a
ceiling exists to catch a leak, not to predict a working set, and one that has never been approached
is one that will only be noticed when something is wrong. The binaries are 127, 115 and 112 MB
because the release profile keeps line tables for backtraces; that is read-only after install.

Two things it corrected in the software rather than in a document: a startup rule that checked
whether the bus credential EXISTS rather than whether the process could read it, and a database
grant written from reading a request handler instead of everything the handler calls.
