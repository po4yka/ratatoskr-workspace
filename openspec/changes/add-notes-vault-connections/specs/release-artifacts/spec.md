# Spec Delta

## Purpose

A template unit (`*@.service`) does not make a repository deployable. The playbook copies it from
the pinned repository, and its `ExecStart=` lines start no binary that the repository builds: the
notes cleanup unit starts `/usr/bin/ob`, which npm installs, and `/bin/rm`.

## MODIFIED Requirements

### Requirement: Every commit on main of a deployable repository has an artifact

A repository that ships a systemd unit other than a template unit (`*@.service`) SHALL publish, for every commit that reaches `main`, one `linux/arm64` artifact at `ghcr.io/po4yka/<repository>` tagged `sha-<full commit SHA>`. The artifact SHALL hold every binary that the repository's units other than template units start, a `SHA256SUMS` file and an SPDX SBOM.

#### Scenario: The artifact of a pinned commit is located

- **WHEN** a consumer reads a commit from `workspace.lock` for a repository that ships a unit other than a template unit, and requests `ghcr.io/po4yka/<repository>:sha-<commit>`
- **THEN** the artifact exists and lists every binary that any `ExecStart=` of that repository's units other than template units names

#### Scenario: A unit starts a binary that the artifact lacks

- **WHEN** the artifact check finds an `ExecStart=` binary in a unit of `deploy/systemd/` other than a template unit that the build did not produce, or a built file that no such unit starts
- **THEN** the workflow fails and does not publish, which `release_artifact_check.rs` proves against generated fixtures

### Requirement: The publishing workflow is defined once

The build, ABI check, SBOM, attestation and push SHALL be one reusable workflow in `ratatoskr-workspace`. Each deployable repository SHALL call it pinned to a full commit SHA, and SHALL NOT copy its steps.

#### Scenario: A deployable repository is checked

- **WHEN** `release_artifact_callers.rs` in `ratatoskr-workspace` reads the workflows of every pinned repository that ships a systemd unit other than a template unit
- **THEN** each has exactly one job that calls `po4yka/ratatoskr-workspace/.github/workflows/reusable-release-artifact.yml@<40-hex SHA>`, or the test fails and names the repository

#### Scenario: A repository ships only template units

- **WHEN** a pinned repository's `deploy/systemd/` holds only `*@.service` units, as `ratatoskr-notes` does at its first pin
- **THEN** `release_artifact_callers.rs` does not ask it to call the reusable workflow
