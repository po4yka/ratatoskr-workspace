# Proposal

## Why

The deployment of Ratatoskr is a manual runbook. Platform's `deploy/README.md` has nine steps, and
each of the extractor and Telegram has its own. The order of those steps is load-bearing (Edge
applies `schema.sql` before `02-grants.sql`, and each `role.sql` runs before its service starts), and
the only record of that order is prose. `docs/DEPLOYMENT_TARGET.md` also says that a reflash resets
every host fact outside the repositories, so after a reflash the host must be rebuilt by hand from
several documents.

The binaries are not published either. Platform's CI builds and smoke-tests a native `linux/arm64`
binary and then discards it. The other repositories tell the operator to run `cargo build` on the
host. So nothing records which binary runs on the host, and nothing verifies it before it is
installed.

The host is frozen, so this is the time to do this work: the automation can be written and tested
against a disposable Debian 12 arm64 target without touching the machine.

## What Changes

- Add an Ansible playbook in `ratatoskr-workspace/deploy/ansible/`, with the roles `host`,
  `postgres`, `nats`, `ratatoskr_service` (one generic role, parameterised per service) and
  `monitoring`. It does what the runbooks do today, idempotently, in the documented order.
- The playbook installs each service from the files that service's repository ships at the commit
  `workspace.lock` pins: the unit, the config example, `role.sql`, and the binary. It copies none of
  them into this repository and edits none of them as it installs them.
- Each Rust repository that ships a systemd unit publishes, for every commit on `main`, a
  `linux/arm64` artifact: its binaries, a `SHA256SUMS` file, an SBOM and a build-provenance
  attestation. A reusable workflow in this repository builds it, as the shared checks are built
  today.
- The playbook verifies the checksum and the attestation on the controller before it copies a
  binary to the host, and it never compiles on the host.
- Each of those repositories gets a Dockerfile with BuildKit cache mounts and an `export` stage that
  writes only the binaries. Platform's Dockerfile is changed in the same way.
- The playbook refuses to run against the real host while `docs/DEPLOYMENT_TARGET.md` says the host
  is frozen. Molecule tests it against a Debian 12 arm64 container in CI.
- Secrets never enter the repository. Passwords and nkey seeds are generated on the host and stay
  there. Operator-supplied secrets (bot token, provider keys, off-host backup credentials) come from
  an `ansible-vault` file outside the repository.
- ADR-0009 in this repository records Ansible over Kubernetes, Helm and Compose for this one host.
  It agrees with Platform's ADR-0013 and does not replace it.

No item is **BREAKING**: nothing has been deployed with this mechanism, and the manual runbooks stay
valid.

## Capabilities

### New Capabilities

- `host-provisioning`: how the single host is brought from a clean install to a running
  deployment: what the playbook installs, in which order, from which pinned sources, how it treats
  secrets, and when it refuses to run.
- `release-artifacts`: what each deployable repository publishes for a commit, how the artifact is
  built and attested, and how a consumer verifies it before use.

### Modified Capabilities

None. `postgres-provisioning` already fixes the order and the files. The playbook follows that
order and runs those files as written, so no requirement there changes.
`single-host-telegram-deployment` already says that port reservation does not authorise host
mutation, and the frozen-host guard in `host-provisioning` keeps to that.

## Repositories, in merge order

1. `ratatoskr-workspace`: the reusable `release-artifact` workflow first, because the repositories
   below call it.
2. `ratatoskr-platform`, `ratatoskr-extractor`, `ratatoskr-telegram`: each calls the workflow and
   gets the reworked Dockerfile. Platform merges first among them because it owns
   `ratatoskr.target` and the schema. The other two can merge in either order.
3. `ratatoskr-workspace`: the playbook, the Molecule scenario, the harness test that checks the
   inventory against the pinned repositories, ADR-0009, and the documentation. It merges last,
   because it consumes artifacts that step 2 publishes.

## Outside this change

- Kubernetes, Helm, k3s and Compose as a way to run the services. ADR-0013 stands.
- Running the playbook against the real host. The freeze lifts only when the owner edits
  `DEPLOYMENT_TARGET.md`, and that is a separate decision.
- Systemd units for the services that do not ship one yet: knowledge, github, vault,
  channel-digests, chatgpt, claude, x, instagram and threads. Each owning repository adds its unit,
  and then one inventory entry enrolls it. Until then the playbook only provisions their database
  roles.
- Where the web client's bundle is served. This is still an open decision in
  `DEPLOYMENT_TARGET.md`.
- The monitoring stack's own compose file. The `monitoring` role edits only the Ratatoskr scrape
  target, the alert rule file and the `extra_hosts` line that `DEPLOYMENT_TARGET.md` names.

## Rollback

Nothing has shipped with this mechanism, so there is nothing to roll back on a host. Each
repository change is reverted with a normal `git revert`. A reverted publishing workflow stops new
artifacts and leaves the published ones in place. The manual runbooks stay correct throughout.

## Impact

- New: `deploy/ansible/` and `.github/workflows/reusable-release-artifact.yml` in this repository,
  plus a harness test `deploy_inventory.rs` and `docs/adr/0009-ansible-for-the-single-host.md`.
- Changed: `Dockerfile` and `.github/workflows/` in Platform. New `Dockerfile` and workflow
  callers in the extractor and Telegram.
- New dependencies on the controller only: `ansible-core`, the `community.docker` collection,
  Molecule for tests, `oras` to pull artifacts, and `gh` to verify attestations. PostgreSQL is
  reached through `docker exec`, as the runbook does, so no PostgreSQL collection is needed. The
  host gains nothing new.
- GHCR stores one artifact per commit per repository.
