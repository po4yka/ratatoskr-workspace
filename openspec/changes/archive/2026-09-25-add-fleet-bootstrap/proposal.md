## Why

A repository joins the fleet by receiving the same files every other repository carries: the three fleet workflows, the pre-commit hook, the editor and attribute files, the licence, the thirty-one files `openspec init` generates and, for a Rust repository, the vendored Rust skill catalogue with its lockfile and the advisory workflow. `drift.yml` fails when any of those differs from the rest of the fleet. Today they are copied by hand, so the joining commit is the one most likely to carry a stale copy, a lost executable bit or a symlink flattened into a file — exactly what `drift.yml` then reports a week later.

## What Changes

- Add `ws fleet init <target-dir> [--from <fleet-repo-dir>] [--force]` to the harness. It copies the committed fleet files from `--from` (default: the workspace root) into the target, byte for byte, keeping mode `100755` and symbolic links.
- Choose the class-specific set from the target: a root `Cargo.toml` makes it the Rust class. Refuse a source of the other class, and name `--from` in the refusal.
- Refuse to replace a differing file unless `--force` is given, and list every conflict before writing anything.
- Report the fleet files the source does not have, and the files `fleet.yml` requires that cannot be copied because each repository writes its own.
- Document the command beside the other `ws` commands.

## Capabilities

### New Capabilities

- `fleet-bootstrap`: how a repository receives the files every fleet repository must carry identically, and what it is told about the ones it still has to write.

### Modified Capabilities

None.

## Impact

Only `ratatoskr-workspace` changes: a new `fleet` module in `harness/crates/workspace-core`, a `fleet init` command in `harness/crates/workspace-cli`, tests, and documentation. The command writes into a repository the operator names; it never commits, pushes or touches `repos/`. No product repository changes in this change, so it merges alone.

Outside this change: running the command against a real repository, changing `fleet.yml` or `drift.yml`, and generating the per-repository files (`README.md`, `AGENTS.md`, `openspec/config.yaml` and the rest), which carry that repository's own content.

Rollback: revert the workspace commit. Nothing has shipped that depends on the command.
