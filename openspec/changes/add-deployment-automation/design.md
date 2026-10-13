# Design

## Context

See `proposal.md` for the motivation. The constraints that shape the approach:

- **One host.** A Raspberry Pi 5, `aarch64`, Debian 12, glibc 2.36, 16 KiB pages, 15 GiB RAM.
  ADR-0013 in Platform chooses systemd units, one per role, and rejects Kubernetes and Compose.
- **Two containers already exist on the host:** `shared-postgres` and `ratatoskr-nats`. There is no
  host `psql` and no `postgres` user, so every SQL statement goes through `docker exec`.
- **Each repository owns its deploy files.** `postgres-provisioning` says that a role file that does
  not run as written is a defect of its owner, and that the provisioner does not patch it.
- **The workspace already pins commits** (`workspace.lock`) and already shares workflows that the
  repositories call by SHA (`reusable-fleet.yml` and others).
- **Only three repositories ship systemd units today:** Platform (edge, ingest, scheduler), the
  extractor, and Telegram (webhook, dispatcher). Only Platform has a Dockerfile, and only Platform's
  CI builds an arm64 binary, which it then discards.
- **The host is frozen,** and nothing in this change may touch it.

## Goals / Non-Goals

**Goals:**

- One command converges a clean Debian 12 arm64 machine to the documented deployment, and a second
  run changes nothing.
- The binary on the host is traceable to one commit, one workflow run and one checksum.
- The whole mechanism is exercised in CI without the real host.

**Non-Goals:**

- Zero-downtime or rolling updates. One replica per service is the design, and a restart is
  acceptable.
- Any provisioning of the operator's controller machine beyond the tools `deploy/ansible/README.md` lists.
- Managing the monitoring stack's lifecycle. The playbook edits three named lines and does not own
  the stack.

## Decisions

### D1. Ansible, not Kubernetes, Helm or Compose

Ansible pushes over SSH, needs only Python on the host (Debian 12 has it), and leaves no agent or
control plane running. That keeps the host's whole budget for the services. Its modules map one to
one onto the runbook steps (`user`, `file`, `copy`, `systemd_service`, `uri`), and the runbook's
`docker exec`, `docker compose` and `ufw` commands stay commands. Four small host-side modules in
`library/` handle secrets, so that no secret value is ever a module argument or a return value.

Alternatives:
- **k3s with Helm:** about 500 MB of RAM and a constant CPU cost for a control plane that schedules
  one replica on one node. It would also replace the per-unit hardening (`ProtectSystem=`,
  `IPAddressAllow=`, per-service users) with pod security settings. Rejected, because it costs a
  lot and gives nothing on one node.
- **Compose for the services:** ADR-0013 already rejected it. Named volumes also conflict with the
  "absolute path, never a named volume" rule.
- **A shell script:** the same steps without idempotence, check mode or a diff. Rejected.
- **NixOS or cloud-init:** both replace the operating system or its first boot, and the host keeps
  Debian with other tenants on it. Rejected.

ADR-0009 in this repository records this decision.

### D2. Layout: one generic service role and data-driven enrolment

```text
deploy/ansible/
├── ansible.cfg
├── inventories/
│   ├── production/hosts.yml      the Pi; secrets_file points outside the repo
│   └── molecule/                 test target, marks ratatoskr_test_target: true
├── group_vars/all/
│   ├── services.json             the enrolment list (see below)
│   └── host.yml                  paths, ports, subnets from DEPLOYMENT_TARGET.md
├── site.yml                      beside group_vars/, so Ansible loads them
├── library/                      ratatoskr_secret, ratatoskr_render, ratatoskr_nkey, ratatoskr_sql
├── filter_plugins/               ratatoskr_lock (workspace.lock)
├── roles/
│   ├── preflight/                freeze guard, lock parse, artifact fetch and verify (controller)
│   ├── host/                     users, groups, directories, tmpfiles, ufw, logrotate, target
│   ├── postgres/                 01-database-and-roles.sql, 02-grants.sql, each role.sql
│   ├── nats/                     config, nkeys generated on the host, container
│   ├── ratatoskr_service/        binary, unit, config, enable, readiness wait
│   └── monitoring/               scrape target, rule file, extra_hosts line
└── molecule/default/
```

`services.json` lists each enrolled service as data. It is JSON, which Ansible loads as a vars file and which the harness reads with `serde_json` without a YAML parser. Per service it holds the repository id, the unit file name, the
binary, the config example, the role name in PostgreSQL, the operator port, and the nkey identity.
Enrolling a new service is one entry, once its repository ships a unit.

`site.yml` runs `preflight` on localhost, then `host`, `nats`, `postgres` (step 01 only),
`ratatoskr_service` for Edge, `postgres` (02-grants), then `ratatoskr_service` for every other
service, each after its `role.sql`, then `monitoring`. That order encodes the
`postgres-provisioning` sequence as code, not prose.

### D3. Child files are fetched at the pinned commit, never copied

`preflight` reads each repository's `commit` from `workspace.lock`. It then reads the needed files
from the initialised submodule at `repos/<path>` and checks that each submodule's HEAD equals the
lock. The files are units, config examples, SQL, `ratatoskr.target`, logrotate and tmpfiles files.
A submodule that is missing or at another commit stops the run. Units, SQL and `ratatoskr.target`
are installed unchanged, and only config examples are rendered with host values. This is why
`deploy_inventory.rs` can say that the workspace holds no copy of them.

Alternative: vendor the files into the role's `files/`. Rejected, because the copy drifts from the
owner and breaks "not patched by whoever provisions".

### D4. Artifacts are OCI artifacts on GHCR, keyed by commit

The reusable workflow `reusable-release-artifact.yml` runs on `ubuntu-24.04-arm`. It builds with
the repository's Dockerfile (`docker buildx build --target export --output type=local`), checks
the ELF machine and the highest `GLIBC_` symbol version, writes `SHA256SUMS` and an SPDX SBOM
(`anchore/sbom-action`), then pushes a tarball with `oras push ghcr.io/po4yka/<repo>:sha-<sha>`.
Finally it attests the digest with `actions/attest-build-provenance` and `push-to-registry: true`.
It refuses to overwrite an existing tag.

Alternatives:
- **GitHub Releases:** these need a tag per commit, which clutters each repository's release list,
  and the Development status allows no versioning scheme. Rejected.
- **Workflow artifacts:** these expire after at most 90 days, so an old pin would become
  undeployable. Rejected.
- **Runtime container images:** the services run under systemd, not in containers, so the binary
  and not an image is the deployable unit. Rejected.

The checks that decide whether to publish (`ExecStart=` coverage, ELF machine, `GLIBC_` ceiling, `SHA256SUMS`) are one Python block in the workflow between two marker comments. That way `release_artifact_check.rs` can run the exact block against generated fixtures, because a reusable workflow cannot be called in a way that is expected to fail.

The playbook verifies on the controller, not on the Pi: `oras pull`, then
`gh attestation verify --repo po4yka/<repo> --signer-workflow
po4yka/ratatoskr-workspace/.github/workflows/reusable-release-artifact.yml --source-digest <commit>`,
then `sha256sum -c`. The signer is the reusable workflow, not the source repository, so
`--signer-workflow` is required: without it `gh` refuses a valid attestation. Only then does it copy the
binaries to the host. The Pi needs no `gh`, no `oras` and no network access to GHCR.

### D5. Dockerfiles: cache mounts and an export stage, with the base image unchanged

Each deployable repository's Dockerfile gets three stages:
- `builder` on `rust:<pinned>-slim-bookworm`, which is bookworm and therefore glibc 2.36, pinned by
  digest, with `--mount=type=cache` for the cargo registry and `target/`;
- `export`, `FROM scratch`, holding only the binaries;
- `runtime` on `debian:12-slim`, which stays, because each repository's CI smoke test runs the
  binary in it.

cargo-chef was considered. It adds a tool and a stage, and on the native arm64 runner cache mounts
give most of the benefit, so it is not used.

### D6. Secrets

- **Generated on the host, never transmitted:** the PostgreSQL role passwords (`openssl rand`,
  set through `psql` stdin as the runbook does), the nkey seeds (`nk -gen user -pubout`, as
  Platform's `deploy/nats/README.md` does, with `nk` run from the pinned `natsio/nats-box` image so
  the host gets no new package), and the Telegram assertion key (`ratatoskr-telegram-webhook
  assertion-key generate`). Each task first checks whether the secret already exists and skips if
  it does, which is how the idempotence requirement holds. Only the public halves are read back: the
  nkey public keys go into the NATS config, and the assertion public key into `edge.conf`. Both
  files are on the same host, so no secret crosses the SSH connection.
- **Supplied by the operator:** the bot token, provider keys, OpenRouter key, and S3 and age
  credentials. They live in an `ansible-vault` file whose path the production inventory names and
  `.gitignore` excludes.
- **Every task that handles a secret sets `no_log: true`.** No secret is passed as a command-line
  argument.

### D7. The freeze guard is the document itself

`preflight` reads `docs/DEPLOYMENT_TARGET.md` from the controller's checkout. If the document
contains the freeze statement and the inventory does not set `ratatoskr_test_target: true`, the run
fails before any task that changes the host. The owner lifts the freeze by editing that document,
as `DEPLOYMENT_TARGET.md` already says. That keeps one source for the fact, and an operator cannot
lift the freeze by passing a command-line flag.

### D8. Test strategy

- **Molecule, `docker` driver, on `ubuntu-24.04-arm`.** The target is a systemd-enabled Debian 12
  arm64 container, privileged, so that systemd and ufw work, with its own Docker CE daemon
  (`/var/lib/docker` and `/var/lib/containerd` are volumes, so the inner overlays work). The
  `shared-postgres` and `ratatoskr-nats` containers therefore run inside the stand-in, beside the
  services, as on the Pi, and their bind mounts resolve there. Mounting the runner's socket instead
  was rejected, because the bind-mount paths would then resolve on the runner. The scenario creates
  `shared-postgres` itself (pgvector, which Knowledge's `role.sql` needs), because on the real host
  it already exists, and the playbook only checks for it.
- **Phases:** converge, idempotence (zero changes), then verify. Verify covers byte-identical
  units, users, modes, the ufw rule, `ratatoskr.target` enabled, every enrolled service ready, the
  order log, and a secret scan of the recorded output.
- **The harness test `deploy_inventory.rs`** runs in the existing workspace CI with no containers.
  It checks enrolment against the pinned units, the target lines, and the absence of copied or
  secret files.

## Risks / Trade-offs

- **[Risk]** systemd and ufw inside a container on a GitHub runner can be fragile.
  → Mitigation: a privileged container with cgroup v2 mounted read-write. If ufw cannot load its
  netfilter modules there, verify asserts the rendered ufw rule file and not the live netfilter
  state, and the design says so in the scenario.
- **[Risk]** Docker inside the stand-in needs disk: one run takes about 8 GB for the image, the
  inner images and the artifacts.
  → Mitigation: the CI job runs on a GitHub arm64 runner. A developer machine needs that much free.
- **[Risk]** A GHCR outage blocks a deploy.
  → Mitigation: the controller keeps the verified artifacts it has downloaded, so a re-run with the
  same pins needs no network access.
- **[Trade-off]** Only Platform, the extractor and Telegram are deployable through this until the
  other repositories ship units. The playbook provisions the other roles' database roles anyway, so
  that enrolling a service later is one inventory entry.
- **[Trade-off]** Rebuilding with an export stage changes Platform's CI build step. The smoke test
  keeps running against the `runtime` stage, so the evidence it produces does not change.

## Migration Plan

1. Workspace: add `reusable-release-artifact.yml`. Nothing calls it yet.
2. Platform, then the extractor and Telegram: Dockerfile and caller. Each publishes its first
   artifact on its next merge to `main`.
3. Workspace: advance the pins to those merges, then add the playbook, Molecule, the harness test,
   ADR-0009 and the documentation updates (`DEPLOYMENT_TARGET.md`, `ARCHITECTURE.md` `deploy/`).
4. The real host: nothing, until the owner lifts the freeze.

**Rollback:** revert each repository's commit. Published artifacts stay where they are and harm
nothing. The manual runbooks stay valid at every step.

## Open Questions

- The GHCR retention policy for artifacts whose commit no `workspace.lock` has ever pinned. This
  can be decided after the first months of artifacts, without changing anything above.
