# Developing Ratatoskr Workspace

> Status: Implemented snapshot slice; later orchestration proposed
> Owner: `ratatoskr-workspace`  
> Last reviewed: 2026-08-30
> Related: `README.md`, `AGENTS.md`, `docs/ARCHITECTURE.md`

## Current stage

The repository implements the complete read-only snapshot slice: sixteen public gitlinks, semantic
manifest validation, deterministic content evidence, status/doctor commands, and hosted CI. One
manual, task-namespaced Web/Platform integration profile also exists under `integration/`; see
`integration/README.md`. Task-worktree lifecycle, generated profiles, PR/release automation, MCP,
and deterministic agent runners remain proposed.

## Intended toolchain

Rust, system Git, Docker Compose, GitHub APIs, and adapters for Claude Code and Codex. Toolchain versions must be pinned and used consistently by local development and CI.

## Snapshot commands

```bash
git submodule update --init --recursive
./ws manifest check
./ws lock check
./ws status
./ws doctor
```

Only `./ws lock generate --output workspace.lock` writes snapshot state. The four checks above are
read-only and never initialize or repair submodules. `ws bootstrap`, task, environment, PR, release,
drift, graph, and MCP commands remain planned and must not be documented as executable.

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

Code size limits are part of that set. A function, a signature, a block and a file each have a
maximum, the numbers live in the linter configuration of the repository they govern, and
`docs/QUALITY_GATES.md` records each number with the command that measured it. Eight repositories
currently have a product manifest and size-limit configuration; the other nine have no product
code. `fleet.yml` fails when a `Cargo.toml` arrives without `clippy.toml`, or a `package.json`
without `eslint.config.js`, so a first code commit cannot land without the file that carries its
limits.

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

## The Rust skills in this repository

`.agents/skills/` holds eighteen Rust skills vendored from `po4yka/rust-skills`, and
`.claude/skills/` symlinks to them. Unlike the steps above this needs nothing from your machine: the
files are in the tree, so a fresh clone already has them.

Update them with the catalogue and never by hand:

```bash
npx skills update
```

That rewrites `.agents/skills/` and `skills-lock.json` from the catalogue. Run it in one repository,
read the diff, then apply the same change to every Ratatoskr repository whose stack is Rust.
`ratatoskr-workspace/.github/workflows/drift.yml` fails when one copy differs from the others.
