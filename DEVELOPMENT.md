# Developing Ratatoskr Workspace

> Status: Proposed  
> Owner: `ratatoskr-workspace`  
> Last reviewed: 2026-08-20  
> Related: `README.md`, `AGENTS.md`, `docs/ARCHITECTURE.md`

## Current stage

The repository is in architecture bootstrap. The `ws` harness, manifests, submodules, agent runners, and integration environments are not implemented yet. Do not claim executable checks were run until the corresponding scaffold exists.

## Intended toolchain

Rust, system Git, Docker Compose, GitHub APIs, and adapters for Claude Code and Codex. Toolchain versions must be pinned and used consistently by local development and CI.

## Expected commands

- `ws bootstrap`, `ws status`, `ws doctor`, `ws drift`
- `ws task prepare <id>`, `ws task verify <id>`
- `ws env up <id> --profile <profile>`, `ws env test <id>`
- `ws lock check`, `ws release snapshot`

The first implementation PR must replace these expectations with exact prerequisites, commands, ports, environment variables, and troubleshooting.

## Workflow

1. Read `AGENTS.md` and identify the changeset.
2. Never edit pinned submodule baselines directly.
3. Work only in task-specific worktrees.
4. Keep one writer per repository and task.
5. Run repository-local checks before workspace integration checks.
6. Update requirements, interfaces, threat model, tests, and ADRs when behavior changes.

## Quality gates

Formatting, linting, tests, generated artifacts, manifest/lock consistency, contract compatibility, integration profiles, and secret scanning must pass before a release snapshot advances `main`.

`docs/QUALITY_GATES.md` records which of those gates exist today, in which repository, and what each one measured before it was accepted. It also lists the checks that were rejected, with the reason, so that a later reader does not add them again.

Code size limits are part of that set. A function, a signature, a block and a file each have a maximum, the numbers live in the linter configuration of the repository they govern, and `docs/QUALITY_GATES.md` records each number with the command that measured it. The 13 repositories that hold no code yet enforce nothing today, and `fleet.yml` is what makes that safe: it fails the gate when a `Cargo.toml` arrives without a `clippy.toml`, or a `package.json` without an `eslint.config.js`, so the first code commit cannot land without the file that carries its limits.

Every repository carries `.githooks/pre-commit`. It is inert until a clone runs `git config core.hooksPath .githooks`, and `git commit --no-verify` skips it. Run the command in each clone you work in, and treat the hook as a convenience rather than a control: the gate is CI and the branch ruleset.

## What a clone needs before you plan a change

A change is planned with OpenSpec, which is a CLI a clone installs for itself. Use the version
`.github/workflows/openspec.yml` pins, so your terminal and the gate answer the same:

```bash
npm install --global @fission-ai/openspec@1.10.0
```

This repository is the store. Registering it is per-machine state that no repository can turn on
for you — the same kind of step as `git config core.hooksPath .githooks` above:

```bash
openspec store register . --id ratatoskr-workspace
```

`openspec doctor` reports whether both are in place.
