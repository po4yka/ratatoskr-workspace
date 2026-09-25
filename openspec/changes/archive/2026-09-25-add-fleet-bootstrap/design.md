## Context

`drift.yml` defines the shared set: `fleet.yml`, `zizmor.yml`, `openspec.yml` and `.githooks/pre-commit` are one blob across the fleet; the paths under `.claude/commands/opsx/`, `.claude/skills/openspec-`, `.agents/skills/openspec-`, `.agents/skills/.openspec-target`, `.opencode/commands/opsx-` and `.opencode/skills/openspec-` are one blob each; the other `.agents/skills/` and `.claude/skills/` paths are one blob across the Rust repositories, with `skills-lock.json`; `dependabot.yml` has one form per class; `advisories.yml` is one blob across the repositories with a root `Cargo.toml`. `fleet.yml` requires a further set of files by presence. The harness already reads Git with system `git` plumbing in `workspace-core`, and reports failures as `ManifestDiagnostic` codes with exit status 2.

## Goals / Non-Goals

**Goals:**

- A joining repository gets the shared files exactly as `drift.yml` will compare them, including mode and symlinks.
- Nothing already in the target is lost without the operator asking for it.
- The operator is told what the command could not do for them.

**Non-Goals:**

- Committing, staging or pushing in the target.
- Writing repository-specific files, or templating them.
- Running `openspec init` or `npx skills`; the command copies what those tools already produced in a fleet repository.

## Decisions

- **Read the committed tree, not the working tree.** `git ls-tree -r -z HEAD` in the source lists every path with its mode and blob; `git cat-file blob` returns the bytes. That is the object `drift.yml` compares, so a copy is identical by the same definition, a `120000` entry becomes a symbolic link with the blob as its target, and an uncommitted edit or untracked file in the source cannot leak into another repository. The alternative, walking the file system, would copy editor litter and local edits and would have to re-derive modes.
- **Prefix rules are drift's rules.** The generated and vendored sets are selected with the same prefixes `drift.yml` uses, so the command and the check cannot disagree about membership. The code states that the required-file list must match `fleet.yml` and `drift.yml`.
- **Target class from a root `Cargo.toml`, source class from any `Cargo.toml`.** The target rule is the one the operator can see before the first commit; the source rule is `drift.yml`'s, which is what makes the workspace, whose Rust is under `harness/`, a Rust source.
- **`advisories.yml` only from a root-Rust source.** The workspace's copy runs in `harness/` and is deliberately different; copying it into a repository with a root `Cargo.toml` would create the drift the command exists to prevent. It is reported as not copied, with the reason, instead of failing the whole run.
- **Plan, then write.** Every planned path is compared first, and any conflict fails the run before the first write, so a refused run leaves the target exactly as it was. `--force` replaces files and links, never a directory.
- **Relative paths resolve against the workspace root**, the same rule `ws lock generate --output` follows, because `./ws` changes directory before running the binary.
- **Module placement.** The logic lives in a new `fleet` module of `workspace-core` so `lib.rs` does not grow further; the CLI only parses arguments and prints the report.

## Risks / Trade-offs

- [The source's `HEAD` is not what the fleet has] → The default source is the workspace, whose files `drift.yml` compares weekly; `--from` names any other fleet repository.
- [`CLAUDE.md` is one blob across the fleet in `drift.yml` but is in the hand-written list] → It follows the list this change was given; a follow-up may move it to the copied set.
- [Unix-only file modes and symlinks] → The harness already runs only on macOS and Linux.
