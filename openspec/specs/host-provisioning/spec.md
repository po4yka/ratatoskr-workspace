# host-provisioning Specification

## Purpose

Defines how the single Ratatoskr host is brought from a clean install to a running deployment from
pinned, verified sources, in the order the services require, and when provisioning must refuse to
run.

## Requirements

### Requirement: Provisioning installs exactly the pinned files of each repository

Provisioning SHALL install each service from the files its own repository ships at the commit `workspace.lock` pins: the systemd unit, the config example, `deploy/postgres/role.sql` and the release artifact of that commit. It SHALL install those files unchanged, except that it fills in host-specific values in a config file. The workspace SHALL NOT hold a copy of any of them.

#### Scenario: A unit on the host is compared with its pinned source

- **WHEN** Molecule converges the playbook and then compares each installed `/etc/systemd/system/ratatoskr-*.service` with the file at the pinned commit of its repository
- **THEN** every installed unit is byte-identical to its pinned source

#### Scenario: The workspace holds a copy of a child deploy file

- **WHEN** `deploy_inventory.rs` searches `deploy/ansible/` for a `.service`, `.target` or `role.sql` file, or a file whose content equals a pinned child deploy file
- **THEN** the test fails and names the file

### Requirement: The inventory and the pinned units agree

Every service in the provisioning inventory SHALL have a systemd unit in its pinned repository, and every `ratatoskr-*.service` that a pinned repository ships SHALL be in the inventory. Each enrolled unit SHALL carry `PartOf=ratatoskr.target` and `WantedBy=ratatoskr.target`.

#### Scenario: A repository ships a unit that the inventory omits

- **WHEN** a pinned repository holds `deploy/systemd/ratatoskr-<role>.service` and the inventory has no entry for that role
- **THEN** `deploy_inventory.rs` fails and names the repository and the unit

#### Scenario: An enrolled unit does not join the target

- **WHEN** an enrolled unit lacks `PartOf=ratatoskr.target` or `WantedBy=ratatoskr.target`
- **THEN** `deploy_inventory.rs` fails and names the unit and the missing line

### Requirement: Database provisioning follows the fixed order

Provisioning SHALL run Platform's `01-database-and-roles.sql`, then start Edge and wait until its readiness endpoint answers 200, then run `02-grants.sql`, and only then, for each other service, run its `role.sql` before that service's first start. No service other than Edge SHALL start before `02-grants.sql` has run.

#### Scenario: A fresh database is provisioned

- **WHEN** Molecule converges the playbook against an empty PostgreSQL 17 cluster
- **THEN** the recorded start times show Edge ready before `02-grants.sql` ran, and every other service's role existed before that service's first start

#### Scenario: A role file fails as written

- **WHEN** a service's `role.sql` exits non-zero
- **THEN** provisioning stops before that service starts, reports the repository and the file, and does not edit or retry the file

### Requirement: Provisioning is idempotent

A second run of provisioning against a converged host SHALL change nothing. It SHALL NOT regenerate an existing password, nkey seed or assertion key, and SHALL NOT restart a service whose binary, unit and config did not change.

#### Scenario: The playbook runs twice

- **WHEN** Molecule runs the playbook a second time against the converged target
- **THEN** the run reports zero changed tasks, and every service's start time is the same as before the second run

### Requirement: Secrets stay out of the repository and out of logs

Database passwords, nkey seeds and the Telegram assertion key SHALL be generated on the host and SHALL NOT leave it. Operator-supplied secrets SHALL come from an encrypted file outside the repository. No secret value SHALL appear in the repository, in the inventory, in a command line or in provisioning output.

#### Scenario: Provisioning output is searched for secrets

- **WHEN** Molecule converges with verbose output, and the test then searches that output and the process list it recorded for every generated password, seed and key
- **THEN** none of them is found

#### Scenario: A secret enters the repository

- **WHEN** a file under `deploy/ansible/` holds a value that the credential check classifies as a secret, or an unencrypted vault file
- **THEN** the pre-commit credential check and `deploy_inventory.rs` fail

### Requirement: Provisioning refuses a frozen host

Provisioning SHALL refuse to change the real host while `docs/DEPLOYMENT_TARGET.md` at the controller's checkout states that the host is frozen. It SHALL refuse before its first change, and SHALL say why. Only a target that the inventory marks as a test target is exempt.

#### Scenario: The real host is targeted while frozen

- **WHEN** the playbook runs against the production inventory and `DEPLOYMENT_TARGET.md` contains the freeze statement
- **THEN** it exits non-zero before any task that changes the host, and its message names the freeze and the document

#### Scenario: The Molecule target is converged while the host is frozen

- **WHEN** the playbook runs against the Molecule inventory, which marks its target as a test target
- **THEN** the freeze check passes and the run converges

### Requirement: Provisioning restores what a reflash resets

From a clean Debian 12 arm64 install, provisioning SHALL recreate every host fact that `DEPLOYMENT_TARGET.md` lists as reset by a reflash and that Ratatoskr depends on: the service users and groups, the NVMe directories and their modes, the Telegram blob group, the ufw rule for the monitoring bridge, the log location, and `ratatoskr.target`.

#### Scenario: A clean target is converged

- **WHEN** Molecule converges a fresh Debian 12 arm64 container
- **THEN** the verify step finds every user, group, directory mode, ufw rule and unit that `DEPLOYMENT_TARGET.md` and the services' deploy guides require, and `ratatoskr.target` is enabled and active, so that `systemctl stop ratatoskr.target` stops every enrolled service
