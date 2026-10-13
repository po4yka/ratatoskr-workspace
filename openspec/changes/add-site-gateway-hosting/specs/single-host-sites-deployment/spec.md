# Spec Delta

## Purpose

Defines the single-host allocations, storage, permissions and tunnel facts that the sites gateway
needs, and keeps the rule that recording them does not change the frozen host.

## ADDED Requirements

### Requirement: The gateway owns two fixed ports

The single-host contract SHALL allocate public port `8183` to `ratatoskr-sites-gateway`, bound to `127.0.0.1` and reached only through `cloudflared`, and operator port `9473` to the same role, reachable from the host only. No other deploy artifact SHALL claim either port.

#### Scenario: The gateway example is compared with the port table

- **WHEN** `harness/crates/workspace-core/tests/port_allocation.rs::no_two_deploy_examples_bind_the_same_port_and_every_bind_is_allocated` reads the gateway's `deploy/systemd/*.conf.example` and the port table of `DEPLOYMENT_TARGET.md`
- **THEN** the public bind is `127.0.0.1:8183`, the operator bind uses `9473`, and no port has two owners

### Requirement: Bundles live on NVMe under one owner

Site bundles SHALL be stored under `/mnt/nvme/ratatoskr/sites/<site id>/bundles/<commit>`. The tree SHALL be owned by the sites service user with group `ratatoskr-sites-bundles` and mode `2750`. The gateway unit SHALL join that group and hold the path read-only, and SHALL hold no writable path in it.

#### Scenario: The gateway unit is inspected

- **WHEN** `ratatoskr-sites` `tests/unit_structure.rs::the_gateway_unit_has_the_supervision_and_hardening_properties` reads the gateway unit
- **THEN** it has `SupplementaryGroups=ratatoskr-sites-bundles`, the bundle path in `ReadOnlyPaths`, and no bundle path in `ReadWritePaths`

#### Scenario: The provisioned tree is inspected

- **WHEN** the Molecule verify case `sites_tree_and_ingress` inspects `/mnt/nvme/ratatoskr/sites` after converge
- **THEN** the owner is the sites service user, the group is `ratatoskr-sites-bundles` and the mode is `2750`

### Requirement: The gateway fits the one-host supervision contract

The gateway SHALL ship one systemd unit with `Type=exec`, `PartOf=ratatoskr.target`, `WantedBy=ratatoskr.target`, explicit `MemoryMax` and `CPUQuota` ceilings, a bounded restart policy and the hardening that the other units use. The unit SHALL hold no secret, because the gateway needs none.

#### Scenario: The unit is validated without systemd as PID 1

- **WHEN** `harness/crates/workspace-core/tests/deploy_inventory.rs::every_pinned_unit_is_enrolled` and `the_ansible_tree_holds_no_child_deploy_file_or_plain_secret` read the enrolled gateway unit
- **THEN** every listed property is present, and the unit and its example contain no credential

### Requirement: The tunnel reaches the gateway only for listed hostnames

The workspace SHALL manage one marked block in the `cloudflared` configuration that maps each site hostname in the inventory to `http://127.0.0.1:8183`. The block SHALL be generated from the inventory only, and no rule outside the block SHALL point to port 8183. A listed hostname without an approved site still gets 404 from the gateway.

#### Scenario: A hostname is removed from the inventory

- **WHEN** `harness/crates/workspace-core/tests/sites_ingress.rs::every_listed_hostname_has_one_rule_inside_the_block` renders the block after a site hostname is removed from `group_vars/all/sites.json`
- **THEN** the managed block has no rule for that hostname, and every rule outside the block is unchanged

#### Scenario: A rule to the gateway exists outside the block

- **WHEN** `harness/crates/workspace-core/tests/sites_ingress.rs::no_rule_outside_the_block_points_to_the_gateway` reads a rendered configuration with a rule to port 8183 outside the markers
- **THEN** the test fails and names the rule

### Requirement: Recording the allocation does not change the frozen host

Adding the port rows, the storage rows, the enrolment and the ingress block SHALL NOT install a unit, edit the `cloudflared` configuration, create a directory or create a DNS record on the host while `DEPLOYMENT_TARGET.md` states the freeze.

#### Scenario: The playbook runs against the real host during the freeze

- **WHEN** the Molecule verify case `freeze_guard` runs the playbook against the production inventory while the freeze statement is present
- **THEN** the run stops in preflight with a message that names `DEPLOYMENT_TARGET.md`, and zero tasks report a change
