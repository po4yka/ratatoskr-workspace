# ADR-0009: Ansible provisions the single host

> Status: Accepted  
> Date: 2026-10-13  
> Change: `openspec/changes/add-deployment-automation`, changeset `DPL-022`

## Context

Ratatoskr runs on one Raspberry Pi 5 (`docs/DEPLOYMENT_TARGET.md`). Platform's ADR-0013 runs each
service as a systemd unit and rejects Kubernetes and Compose for the services. Until this decision
the deployment was a set of manual runbooks, one per repository, whose step order is load-bearing,
and a reflash reset every host fact that those runbooks had created.

## Decision drivers

- The whole host budget belongs to the services: four cores and 15 GiB, shared with other tenants.
- Each repository owns its deploy files, and the provisioner runs them as written
  (`postgres-provisioning`).
- A run must be repeatable after a reflash, and a second run must change nothing.
- The binary on the host must be traceable to one commit and one verified build.

## Considered options

1. **Ansible over SSH.** It needs only Python on the host, leaves no agent behind, and has modules
   for every runbook step.
2. **k3s with Helm.** It needs about 500 MB of RAM and a constant CPU cost for a control plane that
   schedules one replica on one node. It would also replace the per-unit systemd hardening with pod
   security settings.
3. **Compose for the services.** ADR-0013 already rejected it, and its named volumes conflict with
   the absolute-path storage rule.
4. **A shell script.** The same steps, without idempotence, check mode or a diff.
5. **NixOS or cloud-init.** Both replace the operating system or its first boot. The host keeps
   Debian and its other tenants.

## Decision

Option 1. The playbook lives in `deploy/ansible/` in this repository. It reads every child file
from the submodule at the commit that `workspace.lock` pins, and installs binaries only from the
attested `linux/arm64` artifact that each repository publishes for that commit
(`ghcr.io/po4yka/<repository>:sha-<commit>`).

This agrees with ADR-0013 and does not replace it: the units, `ratatoskr.target` and the storage
layout stay as they are. Platform's existing tag-triggered image release continues beside the
per-commit artifacts. The two use different tags and different media types in the same package.

## Consequences

- Enrolling a service is one entry in `deploy/ansible/group_vars/all/services.json`, once its
  repository ships a unit. `deploy_inventory.rs` fails when the enrolment and the pinned units
  disagree.
- The controller needs Python 3.11+, `ansible-core`, `oras` and `gh`; the Molecule test also needs
  the `community.docker` collection for its connection, and `ansible.posix`, which the Docker
  driver's `create` playbook uses. The host needs nothing new: PostgreSQL and NATS are reached
  through `docker exec` and `docker compose`, as the deploy guides do.
- The playbook refuses the real host while `DEPLOYMENT_TARGET.md` states the freeze. The owner lifts
  the freeze by editing that document, not by passing a flag.

## Security and privacy

Database passwords, nkey seeds and the Telegram assertion key are generated on the host and never
read back to the controller. Operator-supplied secrets come from an `ansible-vault` file outside the
repository. Every task that handles a secret sets `no_log`.

## Compatibility and migration

Additive. The manual runbooks stay valid, and the playbook performs their steps in their order.

## Validation

- Molecule converges a systemd Debian 12 arm64 container, runs it a second time with zero changes,
  and verifies the result on a native arm64 runner.
- `deploy_inventory.rs`, `release_artifact_check.rs` and `release_artifact_callers.rs` in the
  harness.

## Follow-up

- Units for the services that do not ship one yet. Each owning repository adds its unit, and then
  one enrolment entry follows.
- A retention policy for artifacts whose commit no `workspace.lock` has pinned.
