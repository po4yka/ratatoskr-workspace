# Spec Delta

## Purpose

Adds template units to the provisioning inventory. `ratatoskr-notes` starts one instance of a
template unit per connection through the systemd D-Bus API (design D3), so the playbook installs a
template unit and never starts it, unlike a service.

## MODIFIED Requirements

### Requirement: The inventory and the pinned units agree

Every service in the provisioning inventory SHALL have a systemd unit in its pinned repository, and every `ratatoskr-*.service` that a pinned repository ships SHALL be in the inventory. A template unit (`ratatoskr-*@.service`) SHALL be listed in `ratatoskr_template_units` with the service user that manages its instances, which SHALL be a user of `ratatoskr_users`, and never in `ratatoskr_services`; a unit that is not a template SHALL NOT be listed in `ratatoskr_template_units`; and every listed template unit SHALL ship at its pin. Each enrolled service unit SHALL carry `PartOf=ratatoskr.target` and `WantedBy=ratatoskr.target`.

#### Scenario: A repository ships a unit that the inventory omits

- **WHEN** a pinned repository holds `deploy/systemd/ratatoskr-<role>.service` and the inventory has no entry for that role
- **THEN** `deploy_inventory.rs` fails and names the repository and the unit

#### Scenario: An enrolled unit does not join the target

- **WHEN** an enrolled service unit lacks `PartOf=ratatoskr.target` or `WantedBy=ratatoskr.target`
- **THEN** `deploy_inventory.rs` fails and names the unit and the missing line

#### Scenario: A template unit is listed as a service, or a service as a template

- **WHEN** `ratatoskr_services` lists a `*@.service`, or `ratatoskr_template_units` lists a unit that is not a template or that its pinned repository does not ship
- **THEN** `deploy_inventory.rs` fails and names the repository and the unit

#### Scenario: A template unit names a manager that the playbook does not create

- **WHEN** the `manager` of a `ratatoskr_template_units` entry is not the `name` of an entry of `ratatoskr_users` in `host.yml`
- **THEN** `deploy_inventory.rs` fails and names the unit and the manager

## ADDED Requirements

### Requirement: A template unit is installed and never started

The playbook SHALL install each unit of `ratatoskr_template_units` byte-identical to its pinned file and reload systemd. It SHALL NOT start or enable a template unit. One polkit rule SHALL let the listed manager start and stop an instance of the unit whose instance name is a lowercase UUID, and SHALL allow nothing else.

#### Scenario: The notes template units on the stand-in

- **WHEN** Molecule runs the verify case `notes_sync_unit` on the converged stand-in
- **THEN** every notes template unit in the inventory is installed, byte-identical, not enabled and with no instance loaded, and `pkcheck` allows `ratatoskr-notes` to start and stop exactly those units with a UUID instance, and refuses another instance name, an unlisted unit, a unit-file change and another user

### Requirement: The npm tree of ob is pinned and checked before use

The playbook SHALL install `obsidian-headless` and its dependencies from a committed lockfile with a sha512 integrity for each package, into a prefix that only root writes, with no lifecycle script. The native module of `better-sqlite3` SHALL be the release prebuilt for the Node.js ABI and host architecture, checked against its recorded sha256 before use. `/usr/bin/ob` SHALL link to the `cli.js` of that prefix.

#### Scenario: The ob tree on the stand-in

- **WHEN** Molecule runs the verify case `notes_sync_unit` on the converged stand-in
- **THEN** the tree in `/opt/ratatoskr-ob` equals the committed lockfile package by package, the native module has the recorded sha256, npm keeps no prebuilt download in its cache, and no file of the prefix is another user's or writable by group or other

#### Scenario: No prebuilt is recorded for the host

- **WHEN** the playbook runs on a host whose Node.js ABI and architecture have no recorded prebuilt
- **THEN** the playbook stops before it downloads a native module
