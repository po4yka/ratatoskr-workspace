# Tasks

## 1. Implementation by repository

Dependency order. Each item closes only after its pull request merges, and carries the link.

- [ ] 1.1 `ratatoskr-workspace`: the planning records and `reusable-release-artifact.yml` (groups 2 and 3). It merges first, because the three callers pin its SHA. PR: _link_
- [ ] 1.2 `ratatoskr-platform`: Dockerfile export stage and the workflow caller (group 4). It merges first among the services, because it owns `ratatoskr.target` and the schema. PR: _link_
- [ ] 1.3 `ratatoskr-extractor`: Dockerfile and the workflow caller (group 4). PR: _link_
- [ ] 1.4 `ratatoskr-telegram`: Dockerfile and the workflow caller (group 4). PR: _link_
- [ ] 1.5 `ratatoskr-workspace`, last: pins advanced to 1.2–1.4, then the playbook, Molecule, `deploy_inventory.rs`, ADR-0009 and the documentation (groups 5–9). PR: _link_

## 2. Planning records

- [x] 2.1 Write the changeset under `changesets/` with the next free id: affected repositories, merge order, rollout and rollback as in `design.md`. No test: a planning record. Verify with `./ws manifest check` and `openspec validate add-deployment-automation --strict`.
- [x] 2.2 Write `docs/adr/0009-ansible-for-the-single-host.md` from design D1, and say that it agrees with Platform's ADR-0013. No test: documentation. Verify that `docs/adr/README.md` lists it.

## 3. The reusable publishing workflow (ratatoskr-workspace)

- [x] 3.1 RED: add `harness/crates/workspace-core/tests/release_artifact_check.rs`. It extracts the artifact check from `.github/workflows/reusable-release-artifact.yml` (the lines between `# BEGIN artifact-check` and `# END artifact-check`) and runs it against fixtures that the test generates: a unit whose `ExecStart=` binary is missing from the export, an `x86-64` ELF, a binary that requires `GLIBC_2.38`, an extra file, and a complete `aarch64` export that requires at most `GLIBC_2.36`. The first four must be refused and the last accepted with a correct `SHA256SUMS`. Confirm that the test fails because the workflow file does not exist.
- [x] 3.2 GREEN: write `.github/workflows/reusable-release-artifact.yml`: native `ubuntu-24.04-arm` runner, `buildx --target export`, the artifact check, an SPDX SBOM, `oras push` to `sha-<sha>` that refuses an existing tag, and `actions/attest-build-provenance` with `push-to-registry`. Every action is pinned by SHA. Verify that 3.1 passes and that `zizmor` passes on the new file.
- [ ] 3.3 Add the job `release-artifact-selftest` to the workspace `ci.yml`. It calls the workflow with `publish: false` against `harness/fixtures/release-artifact/`, whose Dockerfile exports a real `aarch64` binary. No failing test first: CI configuration, proven by its own run. Verify that the job passes on the push.
- [x] 3.4 Record the publishing workflow and its checks in `docs/QUALITY_GATES.md`, including what they cannot see: the attestation proves where a binary was built, not that it is correct. No test: documentation.

## 4. Dockerfiles and callers (ratatoskr-platform, then extractor, then telegram)

- [ ] 4.1 Platform RED: in `ci.yml`, change the `linux/arm64 artifact` job to call `docker buildx build --target export --output type=local,dest=out`, then assert that `out/` holds exactly `ratatoskr-edge`, `ratatoskr-ingest` and `ratatoskr-scheduler`. Confirm that it fails because the Dockerfile has no `export` stage.
- [ ] 4.2 Platform GREEN: add cache mounts to `builder`, pin both base images by digest, add the `FROM scratch AS export` stage, and keep `runtime` for the existing smoke test. Verify that 4.1 passes and that the existing smoke steps still pass on the `runtime` target.
- [ ] 4.3 Platform: add `.github/workflows/release-artifact.yml`, which calls the workspace workflow on push to `main`. No failing test first: CI configuration, proven by its own run. Verify with `gh api` that the push of the merge publishes `ghcr.io/po4yka/ratatoskr-platform:sha-<sha>`, and that `gh attestation verify` passes on it.
- [ ] 4.4 Extractor RED: add the `linux/arm64 artifact` job (`ubuntu-24.04-arm`): build `--target export` and assert that `out/ratatoskr-extractor` exists and is `aarch64`. Confirm that it fails because there is no Dockerfile.
- [ ] 4.5 Extractor GREEN: add a Dockerfile with the same three stages, and verify that 4.4 passes. Then repeat 4.3 for the extractor and verify its published artifact and attestation.
- [ ] 4.6 Telegram RED: as 4.4, asserting `ratatoskr-telegram-webhook` and `ratatoskr-telegram-dispatcher`.
- [ ] 4.7 Telegram GREEN: as 4.5, and repeat 4.3 for Telegram.
- [ ] 4.8 In each of the three `deploy/README.md` files, replace "build on the host" or "copy out of the image" with "the playbook installs the published artifact", and keep the manual path as the fallback. No test: documentation.

## 5. Inventory checks (ratatoskr-workspace)

- [ ] 5.1 Pin advance: move `platform`, `extractor` and `telegram` to the merges of 1.2–1.4 with `./ws lock generate`, and verify with `./ws doctor`. No failing test first: generated files.
- [ ] 5.2 RED: add `harness/crates/workspace-core/tests/release_artifact_callers.rs`: every pinned repository that ships `deploy/systemd/*.service` has exactly one job that calls `po4yka/ratatoskr-workspace/.github/workflows/reusable-release-artifact.yml@<40-hex SHA>`. It has a mutation case. Run it against the pins before 5.1, and confirm that it fails and names `platform`, `extractor` and `telegram`.
- [ ] 5.3 GREEN: after the pin advance in 5.1, verify that 5.2 passes with `cargo test -p workspace-core --test release_artifact_callers`.
- [ ] 5.4 RED: add `harness/crates/workspace-core/tests/deploy_inventory.rs` with four tests: `every_pinned_unit_is_enrolled`, `every_enrolled_service_has_a_pinned_unit`, `every_enrolled_unit_joins_ratatoskr_target` and `the_ansible_tree_holds_no_child_deploy_file_or_plain_secret`. Each test has a mutation case. Confirm that the first two fail because `deploy/ansible/group_vars/all/services.json` does not exist.
- [ ] 5.5 GREEN: write `deploy/ansible/group_vars/all/services.json` (JSON, which Ansible loads as vars and the harness reads with `serde_json` as a dev-dependency), which enrolls edge, ingest, scheduler, extractor, telegram-webhook and telegram-dispatcher, plus the database roles of the services that do not ship a unit yet. Verify that all four tests pass with `cargo test -p workspace-core --test deploy_inventory`.

## 6. The playbook skeleton and the freeze guard

- [ ] 6.1 Scaffolding: `ansible.cfg`, `requirements.yml` (pinned `community.docker`), both inventories, `playbooks/site.yml`, empty roles, and `molecule/default/` with the systemd Debian 12 arm64 platform and the mounted Docker socket. No test: scaffolding. Verify that `ansible-playbook --syntax-check` and `molecule create` succeed.
- [ ] 6.2 RED: add the Molecule verify case `freeze_guard`: it runs `site.yml` against an inventory without `ratatoskr_test_target`, and asserts a non-zero exit with a message that names `DEPLOYMENT_TARGET.md`, and zero changed tasks. Confirm that it fails because the run succeeds.
- [ ] 6.3 GREEN: implement the `preflight` freeze check (design D7). Verify 6.2, and verify that the Molecule inventory still converges.
- [ ] 6.4 RED: verify case `pins_match_lock`: move one submodule off its locked commit, and assert that preflight stops and names it. Confirm that it fails.
- [ ] 6.5 GREEN: implement the lock parse and the submodule HEAD check in `preflight` (D3). Verify 6.4.
- [ ] 6.6 RED: verify case `artifact_tamper`: replace one byte of a fetched binary in the controller cache, and assert that preflight stops on `sha256sum -c`. Confirm that it fails.
- [ ] 6.7 GREEN: implement the fetch (`oras pull`), `gh attestation verify` and checksum steps in `preflight` (D4), with a controller-side cache. Verify 6.6, and verify that an untampered cache converges without network access.

## 7. Host, NATS and PostgreSQL roles

- [ ] 7.1 RED: verify cases `host_facts`: every service user and group, `/mnt/nvme/ratatoskr/{logs,nats,archive-staging}` and the Telegram blob root with their owners and modes, the tmpfiles and logrotate files, the ufw rule for `9464:9468`, and `ratatoskr.target` installed byte-identical and enabled. Confirm that they fail against the empty `host` role.
- [ ] 7.2 GREEN: implement the `host` role, and verify 7.1.
- [ ] 7.3 RED: verify cases `nats_up` (the container answers on `127.0.0.1:8222/healthz`; the config holds one public key per enrolled identity and no `SU` seed) and `seed_modes` (each seed file is `0640 root:<service group>`). Confirm that they fail.
- [ ] 7.4 GREEN: implement the `nats` role, with seeds generated on the host through `natsio/nats-box` and `no_log` (D6). Verify 7.3.
- [ ] 7.5 RED: verify case `provision_order`: read the recorded timestamps, and assert that `01` ran before Edge started, that Edge was ready before `02-grants` ran, and that each `role.sql` ran before its service first started. Add the case `role_file_failure`: a fixture `role.sql` that exits non-zero stops the run before its service starts, and names the file. Confirm that both fail.
- [ ] 7.6 GREEN: implement the `postgres` role and the ordering in `site.yml` (D2). The SQL goes through `docker exec -i shared-postgres psql` on stdin, and passwords through stdin with `no_log`. Verify 7.5.

## 8. Services and monitoring

- [ ] 8.1 RED: verify cases `units_identical` (each installed unit is byte-identical to the pinned source), `services_ready` (every enrolled operator port answers `/health/ready` 200) and `stop_as_one` (`systemctl stop ratatoskr.target` stops every enrolled unit, while `shared-postgres` and `ratatoskr-nats` keep running). Confirm that they fail.
- [ ] 8.2 GREEN: implement the `ratatoskr_service` role: verified binary, unchanged unit, rendered config, `check-config` run as the service user, enable, and wait for readiness. Generate the Telegram assertion key on the host and write its public key into `edge.conf` (D6). Verify 8.1.
- [ ] 8.3 RED: verify case `monitoring_lines`: the scrape file holds the Ratatoskr job, the rule file is in place, and the `victoriametrics` service declares `extra_hosts: host.docker.internal:host-gateway`. Use a fixture monitoring compose file in the Molecule target. Confirm that it fails.
- [ ] 8.4 GREEN: implement the `monitoring` role, which edits only those three lines. Verify 8.3.

## 9. Whole-run properties and documentation

- [ ] 9.1 RED: enable Molecule's `idempotence` step, and add the verify case `no_restart_on_rerun` (every unit's `ActiveEnterTimestamp` is unchanged after the second run). Confirm that it fails if any task reports a change.
- [ ] 9.2 GREEN: fix every non-idempotent task that 9.1 reports, until the second run reports zero changes. Verify 9.1.
- [ ] 9.3 RED: verify case `no_secret_in_output`: search the recorded verbose converge log and the process snapshots for every generated password, seed and key. Confirm that it fails if any secret task lacks `no_log`.
- [ ] 9.4 GREEN: correct every task that 9.3 finds. Verify 9.3.
- [ ] 9.5 Add the job `molecule` (`ubuntu-24.04-arm`) to the workspace CI, and add it to the required checks. No failing test first: CI configuration, proven by its own run on the pull request.
- [ ] 9.6 Documentation: `deploy/ansible/README.md` (controller setup, vault file location, the one command, and how a new service enrolls), and in `DEPLOYMENT_TARGET.md` a "Provisioning" section that points to it. Also keep the freeze statement unchanged, update `ARCHITECTURE.md` (`deploy/` now exists), and add the Molecule and `deploy_inventory.rs` gates to `docs/QUALITY_GATES.md` with what they cannot see. No test: documentation. Verify that every command in the README runs as written against the Molecule target.

## Workflow follow-up

- Archive this change after the pull requests in group 1 have merged and their links are recorded.
- Running the playbook against the real host is not part of this change. It waits for the owner to lift the freeze in `DEPLOYMENT_TARGET.md`.
