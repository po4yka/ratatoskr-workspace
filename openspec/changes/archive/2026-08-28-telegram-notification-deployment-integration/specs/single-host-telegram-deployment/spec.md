## Purpose

Defines the single-host allocations and cross-repository compatibility facts required to deploy Telegram's webhook and dispatcher roles without colliding with existing Ratatoskr or host services.

## ADDED Requirements

### Requirement: Telegram owns three fixed single-host ports

The single-host contract SHALL allocate public port `8182` to the Telegram webhook listener, operator port `9467` to the Telegram webhook role, and operator port `9468` to the Telegram dispatcher role. No Telegram deploy artifact SHALL claim another allocated or known-occupied host port.

#### Scenario: Deployment artifacts are compared with the workspace contract

- **WHEN** structural validation reads the Telegram systemd units and the workspace deployment target
- **THEN** the listener addresses match `8182`, `9467`, and `9468` exactly and no allocation has more than one owner

### Requirement: Exposure follows role boundaries

The webhook public listener SHALL be reachable only through the trusted `cloudflared` path. Operator listeners SHALL remain non-public and SHALL be reachable only from the bounded host, monitoring bridge, and operator network paths named by the deployment contract. The dispatcher SHALL expose no public application listener.

#### Scenario: Dispatcher unit is inspected

- **WHEN** structural validation examines the dispatcher service definition
- **THEN** it finds only the `9468` operator allocation and no public-listener allocation

### Requirement: The deployment fits the one-host supervision contract

Telegram SHALL ship one systemd unit per runtime role with explicit resource ceilings, `Type=exec`, `TimeoutStopSec=130s`, bounded restart policy, dependency ordering, hardened filesystem/process privileges, and NVMe-backed service logging. Secret values SHALL remain outside unit files and repository content.

#### Scenario: Unit structure is validated without systemd as PID 1

- **WHEN** the deployment validation runs in a development or CI environment
- **THEN** both units parse structurally and every required supervision, resource, hardening, log, secret, and ordering property is present

### Requirement: Port reservation does not authorize host mutation

Updating the canonical allocation and shipping deploy artifacts SHALL NOT register a webhook, open a firewall, install a unit, rotate a credential, or start a process on the frozen target.

#### Scenario: TG-010 completes while target is frozen

- **WHEN** repository gates and the composed profile pass
- **THEN** the changeset can record implementation readiness while live deployment remains explicitly unperformed
