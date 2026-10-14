# Spec Delta

## Purpose

A template unit (`*@.service`) does not make a repository deployable. The playbook copies it from
the pinned repository, and its `ExecStart=` lines start no binary that the repository builds: the
notes cleanup unit starts `/usr/bin/ob`, which npm installs, and `/bin/rm`.

## MODIFIED Requirements

### Requirement: Every commit on main of a deployable repository has an artifact

A repository that ships a systemd unit other than a template unit (`*@.service`) SHALL publish, for every commit that reaches `main`, one `linux/arm64` artifact at `ghcr.io/po4yka/<repository>` tagged `sha-<full commit SHA>`. The artifact SHALL hold every binary that the repository's units other than template units start, a `SHA256SUMS` file and an SPDX SBOM. A template unit SHALL start only a program of a reviewed allow-list of exact paths, never a binary that the repository builds. The allow-list holds the programs that the notes template units start: `/usr/bin/ob`, `/bin/rm`, and `/bin/sh` with `-c`.

#### Scenario: The artifact of a pinned commit is located

- **WHEN** a consumer reads a commit from `workspace.lock` for a repository that ships a unit other than a template unit, and requests `ghcr.io/po4yka/<repository>:sha-<commit>`
- **THEN** the artifact exists and lists every binary that any `ExecStart=` of that repository's units other than template units names

#### Scenario: A unit starts a binary that the artifact lacks

- **WHEN** the artifact check finds an `ExecStart=` binary in a unit of `deploy/systemd/` other than a template unit that the build did not produce, or a built file that no such unit starts
- **THEN** the workflow fails and does not publish, which `release_artifact_check.rs` proves against generated fixtures

#### Scenario: A template unit starts a binary that the repository builds

- **WHEN** a command setting (`ExecStart=`, `ExecStartPre=`, `ExecStartPost=`, `ExecCondition=`, `ExecReload=`, `ExecStop=` or `ExecStopPost=`) of a pinned `deploy/systemd/*@.service` starts a program that is not on the allow-list by its exact path, such as a bare name, `/usr/local/bin/ratatoskr-notes`, or a host program that starts the program in its arguments, such as `/usr/bin/timeout`, `/usr/bin/env` or `/bin/bash`
- **THEN** `release_artifact_callers.rs` fails and names the repository, the unit and the program

#### Scenario: A template unit starts a binary that the repository builds through a shell

- **WHEN** such a command setting starts `/bin/sh -c`, and a command word of the string, also inside `$(...)`, a backtick substitution or a nested `/bin/sh -c`, is not a builtin of dash, `cat`, or a program on the allow-list by its exact path
- **THEN** `release_artifact_callers.rs` fails and names the command. `cat` passes while no binary in `services.json` has its name, because systemd puts `/usr/local/bin/` first in PATH. No binary in `services.json` may be named `node` either, because `/usr/bin/ob` starts `#!/usr/bin/env node`

#### Scenario: A template unit holds a form that the check cannot read

- **WHEN** a command setting holds a backslash, a `$` variable or a `;` word; `/bin/sh` has no `-c` or an option other than `-c`, `-e`, `-u` and `-x`; the string names PATH, holds a process substitution or a specifier other than `%i`; a line continues on the next line; `EnvironmentFile=` or `ExecSearchPath=` is set; an `Environment=` or `PassEnvironment=` sets a variable other than `HOME` and `XDG_CONFIG_HOME`, such as PATH, ENV, `BASH_ENV`, `NODE_OPTIONS`, `NODE_PATH`, `NODE_ENV` or `LD_PRELOAD`, or holds a word that the check cannot read; or `BindPaths=`, `BindReadOnlyPaths=`, `RootDirectory=`, `RootImage=`, `RootImageOptions=`, `MountImages=`, `ExtensionImages=`, `ExtensionDirectories=` or `TemporaryFileSystem=` is set
- **THEN** `release_artifact_callers.rs` fails, because systemd or the shell could start a program that the check does not see

### Requirement: The publishing workflow is defined once

The build, ABI check, SBOM, attestation and push SHALL be one reusable workflow in `ratatoskr-workspace`. Each deployable repository SHALL call it pinned to a full commit SHA, and SHALL NOT copy its steps.

#### Scenario: A deployable repository is checked

- **WHEN** `release_artifact_callers.rs` in `ratatoskr-workspace` reads the workflows of every pinned repository that ships a systemd unit other than a template unit
- **THEN** each has exactly one job that calls `po4yka/ratatoskr-workspace/.github/workflows/reusable-release-artifact.yml@<40-hex SHA>`, or the test fails and names the repository

#### Scenario: A repository ships only template units

- **WHEN** a pinned repository's `deploy/systemd/` holds only `*@.service` units, as `ratatoskr-notes` does at its first pin
- **THEN** `release_artifact_callers.rs` does not ask it to call the reusable workflow
