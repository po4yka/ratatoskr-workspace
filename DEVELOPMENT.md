# Developing Ratatoskr Workspace

> Status: Proposed  
> Owner: `ratatoskr-workspace`  
> Last reviewed: 2026-08-17  
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
