## Context

See `proposal.md`. The current root Git tree does not track `repos/`; local operator clones happen to occupy the intended paths and can be stale or dirty independently. The target architecture already assigns distinct authority to semantic metadata, Git gitlinks, and a generated lock, and requires the harness to use the system Git CLI. The first implementation must make that model true without changing child histories or making a child depend on the workspace.

WS-013 starts from workspace commit `8f305f056bca06abe46c031797359f0118d5e0a4` and pins the audited child commits below. Each SHA was the successful hosted-CI `origin/main` head during the 2026-08-30 fleet audit:

| Repository ID | Path | Initial pin |
|---|---|---|
| contracts | `repos/contracts` | `d43b62a402f47984c95037c158ec29c5ee62ee5c` |
| platform | `repos/platform` | `070b718238c4e6e45a5b7fc08ebe719ed5374e33` |
| extractor | `repos/extractor` | `e380202073190bd6e21e0ea36f236fc150732ebc` |
| knowledge | `repos/knowledge` | `25fb4a92d8b9ebcc3f15c4f2c9bfd8ee6b027ba1` |
| github | `repos/github` | `fd60dd37e22b30056d2153ef22b271f75659e654` |
| vault | `repos/vault` | `27843706b7bfad46c9d263740bf8da9f75772d65` |
| x | `repos/social/x` | `a16b50b4425fe92c789f326fdac2a26712b18e7b` |
| instagram | `repos/social/instagram` | `4161a83db86335637e234737024687ff79e2095e` |
| threads | `repos/social/threads` | `1b69c3f6e6d89116981b9bd629cdec25d65a9756` |
| chatgpt | `repos/ai-archive/chatgpt` | `875e99abd6d0d550ac6d05040f31f6ba3e42c422` |
| claude | `repos/ai-archive/claude` | `39985a18a9200ce07bb927a8ebbeb7d1530c2c59` |
| telegram | `repos/integrations/telegram` | `f814cdde49cd76000b7a20bb497a840b52fa99e0` |
| web | `repos/clients/web` | `48b21c5fdcf9b85705ab2942b4b2db57a61728b2` |
| mobile | `repos/clients/mobile` | `c496046fb0718b727e54e14071d61f2ed148e3d4` |
| browser-extension | `repos/clients/browser-extension` | `79bcba985135c4a71a0c7734adb9d855cedbdb53` |
| export-agent | `repos/clients/export-agent` | `fcb1397372bda0608316cb80b200bd2bd86e36f4` |

## Goals / Non-Goals

**Goals:**

- Make one workspace commit sufficient to identify all sixteen child revisions.
- Make the semantic catalogue and generated snapshot machine-validated rather than documentation-only.
- Support both human-readable diagnostics and a stable machine-readable failure result.
- Verify the same behavior in fixtures, the real checked-out fleet, and hosted CI.
- Keep verification read-only and safe around dirty or uninitialized submodules.

**Non-Goals:**

- Implement task worktree lifecycle, PR orchestration, MCP, deployment, release tagging, or automatic pin advancement.
- Change, rebuild, or republish a child repository.
- Infer undeclared dependencies or scan arbitrary child content heuristically.
- Claim runtime or provider end-to-end correctness from snapshot consistency.

## Decisions

### Use Git submodules and public HTTPS remotes

The existing paths become sixteen gitlinks with `.gitmodules` entries using canonical `https://github.com/po4yka/<repo>.git` URLs and `branch = main` as informational branch metadata. Gitlinks, not branch tips, remain authoritative. HTTPS permits a fresh read-only checkout and CI without SSH credentials.

Alternatives rejected:

- Keeping independent ignored clones cannot bind a child revision to a workspace commit.
- A lock-only design duplicates Git's pin without making normal clone/checkout semantics materialize it.
- Git subtree or copied sources destroys independent repository history and ownership boundaries.

### Implement a narrow permanent Rust harness slice

Add `harness/Cargo.toml` with `workspace-core` and `workspace-cli`; expose a root `./ws` launcher for `ws manifest check`, `ws lock generate`, `ws lock check`, `ws status`, and `ws doctor`. Core owns parsing, validation, Git inspection, dependency sorting, digesting, and canonical lock rendering. CLI owns arguments, diagnostics, exit codes, and atomic explicit lock updates. All Git semantics use bounded `git` subprocesses with argument arrays and no shell evaluation.

The production dependency set is intentionally narrow: `serde` for typed data, `toml` for the committed manifest and lock formats, and `sha2` for portable content digests. Their transitive versions are pinned in `harness/Cargo.lock`; all use the standard Rust MIT/Apache-2.0 ecosystem licensing and will be covered by the repository's cargo-deny/advisory gates. Hand-written TOML parsing was rejected as a permanent correctness and security liability; a Python or shell harness was rejected because the accepted architecture chooses Rust and replacing a bootstrap script later would create a stopgap contract.

### Keep three authorities non-overlapping

- `workspace.toml` contains stable semantic identity and no commit SHA.
- `.gitmodules` contains materialization paths and public remotes.
- Gitlinks contain exact child SHAs.
- `workspace.lock` is derived evidence and never an input for selecting a commit.

Validation joins these sources by repository ID/path and reports all mismatches in one pass. It never silently repairs them. `ws lock generate --output workspace.lock` is the sole write path and uses a same-directory temporary file plus rename; `ws lock check` writes nothing.

### Use canonical TOML for both manifest and lock

Both files use format version `1`. The manifest represents repositories as a lexically ordered array of tables with explicit dependency-edge kind and purpose, command names, contract identifiers, profile membership, and a list of exact digest inputs. The lock contains a lexically ordered repository array and lexically ordered digest entries.

Canonical rendering is implemented rather than relying on map serialization order. It uses LF endings, UTF-8, lower-case hexadecimal SHA-256, full forty-character Git SHAs, normalized HTTPS remotes, and no generated timestamp or workspace absolute path. `manifest_sha256` and `gitmodules_sha256` cover normalized committed bytes. The workspace commit is excluded because embedding it would create an impossible self-reference.

### Digest declared Git objects, not ambient files

Each manifest repository declares exact file or directory paths whose content is part of compatibility evidence. A file digest is SHA-256 over its Git blob bytes. A directory digest is SHA-256 over a canonical sequence of relative path, mode, blob object ID, size, and blob bytes for every entry beneath it. Paths are read from the pinned child commit, not from an uncommitted working-tree file. Missing paths, symlinks where a regular file/tree is required, submodule entries inside a digest tree, and path escape attempts fail closed.

Initial digest inputs cover available public contracts, schemas, generated API/client locks, deployment-target declarations, and OpenSpec linkage. The manifest stays explicit so adding a new compatibility-bearing artifact produces a reviewable manifest and lock diff.

### Separate metadata validity from materialized baseline health

`ws manifest check` validates syntax, uniqueness, `.gitmodules`, gitlinks, remotes, dependency references, and cycles using the superproject index. `ws lock check` additionally requires initialized child repositories and checks derived content. `ws status` reports initialization, HEAD drift, and dirty state without failing solely because a child is ahead; `ws doctor` is the strict gate and fails on uninitialized, drifted, dirty, unreachable, or stale-lock state.

No command initializes, fetches, checks out, resets, or cleans a child implicitly. Documentation gives the explicit bootstrap command `git submodule update --init --recursive`. This prevents a read-only check from becoming a surprising network or destructive operation.

### Test the failure modes before materializing the real fleet

Core tests create isolated temporary superprojects and bare child remotes, then exercise duplicate IDs, missing entries, remote/path mismatch, detached gitlink pins, dirty/untracked baseline state, missing digest inputs, stable lock rendering, stale lock diffs, unknown dependencies, complete cycles, and command non-mutation. Each behavior test is run red against the missing implementation before its paired implementation task.

After fixture tests are green, the actual manifest/submodules/lock are added and the same `ws doctor` is run on the real sixteen-repository snapshot. CI checks out recursively, runs format/clippy/test/deny/advisories through the workspace's `ci.yml`, and runs `ws doctor` on the exact commit.

## Risks / Trade-offs

- [Sixteen submodules increase clone time and network surface] → Use public HTTPS, shallow checkout only where Git can still fetch the exact gitlink, cache Cargo rather than child build outputs, and keep CI snapshot verification free of child compilation.
- [A child can delete or force-rewrite a pinned public commit] → `ws doctor` verifies reachability from the declared remote; pin advancement is refused until the exact commit is fetchable. This cannot prevent upstream history rewriting, but makes it observable.
- [Digest declarations can omit a compatibility-bearing file] → Require explicit contract/schema/generated-client lists in review and validate that every declared produced/consumed contract has at least one digest input.
- [Dirty local baseline currently exists in operator clones] → Never convert or clean those clones in place. The implementation worktree starts empty at `repos/`; existing user-owned clones in the primary checkout remain untouched. After merge, the operator can move or reconcile them deliberately before initializing submodules there.
- [Adding a root Cargo manifest changes fleet-gate behavior] → Add `.github/workflows/ci.yml`, Rust lint/security configuration, toolchain pin, and Cargo lock in the same commit.
- [Snapshot consistency can be mistaken for runtime correctness] → CLI output, docs, and changeset evidence state that the gate proves composition and declared artifact integrity only; integration profiles remain separate evidence.

## Migration Plan

1. Create WS-013 planning artifacts in the isolated workspace worktree.
2. Add red fixture tests for manifest semantics, Git topology, lock determinism/content, drift detection, and strict doctor behavior.
3. Implement the Rust harness until those tests pass, then run its repository-local gates.
4. Add `workspace.toml`, `.gitmodules`, and the sixteen exact gitlinks without touching child histories; generate `workspace.lock` through the harness.
5. Run `ws doctor`, OpenSpec validation, existing integration static/smoke tests, secret/drift checks, and the full gated Rust suite.
6. Update WS-013 changeset and documentation, review the staged diff and gitlink modes, commit the coherent change, and push the task branch explicitly authorized by the user.
7. Verify hosted checks on the exact pushed SHA before reporting publication complete.

Rollback before merge removes only the isolated worktree/branch after confirmation. Rollback after merge is a normal revert of the coherent workspace commit. Child repositories and their published commits are unchanged in both cases.
