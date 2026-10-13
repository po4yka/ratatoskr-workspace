# Spec Delta

## Purpose

Defines what each deployable Ratatoskr repository publishes for a commit, so that the host runs a
`linux/arm64` binary that CI built and smoke-tested, that a consumer can locate by commit, and that
it can verify before installing.

## ADDED Requirements

### Requirement: Every commit on main of a deployable repository has an artifact

A repository that ships a systemd unit SHALL publish, for every commit that reaches `main`, one `linux/arm64` artifact at `ghcr.io/po4yka/<repository>` tagged `sha-<full commit SHA>`. The artifact SHALL hold every binary that the repository's units start, a `SHA256SUMS` file and an SPDX SBOM.

#### Scenario: The artifact of a pinned commit is located

- **WHEN** a consumer reads a commit from `workspace.lock` for a repository that ships a unit, and requests `ghcr.io/po4yka/<repository>:sha-<commit>`
- **THEN** the artifact exists and lists every binary that any `ExecStart=` of that repository's units names

#### Scenario: A unit starts a binary that the artifact lacks

- **WHEN** the artifact check finds an `ExecStart=` binary in `deploy/systemd/` that the build did not produce, or a built file that no unit starts
- **THEN** the workflow fails and does not publish, which `release_artifact_check.rs` proves against generated fixtures

### Requirement: A published binary runs on the target ABI

Each published binary SHALL be built natively on `aarch64` against glibc 2.36 or older. It SHALL be published only after its own repository's smoke test has started it, answered readiness, taken SIGTERM and exited 0 on that architecture.

#### Scenario: The artifact is inspected for its ABI

- **WHEN** the publishing workflow reads each binary's ELF header and its highest required `GLIBC_` symbol version
- **THEN** the machine is `aarch64` and no required version is newer than `GLIBC_2.36`, or the workflow fails without publishing

### Requirement: An artifact carries verifiable provenance

Each artifact SHALL carry a GitHub build-provenance attestation that binds its digest to the repository, the workflow and the commit that built it. A tag, once published, SHALL NOT be moved to a different digest.

#### Scenario: A consumer verifies an artifact

- **WHEN** a consumer runs `gh attestation verify` on the artifact with `--repo po4yka/<repository>`, `--signer-workflow po4yka/ratatoskr-workspace/.github/workflows/reusable-release-artifact.yml` and `--source-digest <commit>`, then checks every binary against `SHA256SUMS`
- **THEN** both checks pass for an artifact that the workflow published, and either one fails for an artifact changed after publication

#### Scenario: A commit is built twice

- **WHEN** the publishing workflow runs again for a commit whose tag already exists
- **THEN** it leaves the existing tag and digest unchanged and reports that the artifact exists

### Requirement: The publishing workflow is defined once

The build, ABI check, SBOM, attestation and push SHALL be one reusable workflow in `ratatoskr-workspace`. Each deployable repository SHALL call it pinned to a full commit SHA, and SHALL NOT copy its steps.

#### Scenario: A deployable repository is checked

- **WHEN** `release_artifact_callers.rs` in `ratatoskr-workspace` reads the workflows of every pinned repository that ships a systemd unit
- **THEN** each has exactly one job that calls `po4yka/ratatoskr-workspace/.github/workflows/reusable-release-artifact.yml@<40-hex SHA>`, or the test fails and names the repository
