# Quality gates

> Status: Implemented  
> Owner: `ratatoskr-workspace`  
> Last reviewed: 2026-08-20  
> Related: `DEVELOPMENT.md`, `TESTING.md`, `THREAT_MODEL.md`, `docs/ARCHITECTURE.md` section 11

## Scope

This document records the static analysis, the linters, the continuous integration and the Git hooks
that the 17 Ratatoskr repositories have today. It also records the checks that were measured and
then rejected, and it gives the reason for each rejection.

Workspace CI does not replace repository CI. Each repository owns its own gate. This document
describes the fleet, because the controls are identical in each repository and a reader must be able
to find the policy in one place.

Every number in this document comes from a command that was run. If you change a control, run the
command again and correct the number.

The fleet is 17 repositories, and that number is measured rather than asserted. On 2026-08-19
`users/po4yka/repos` lists exactly 17 non-archived, non-fork repositories whose name begins
`ratatoskr-`, all public and all with `main` as the default branch.

This paragraph was written twice on the same day, and the reason is worth keeping. `ratatoskr-web`
was created that afternoon, and a count taken between the two events read 16 and concluded the
repository did not exist. Both readings were correct when they were taken. What made the second one
wrong an hour later is that it was a count: the drift check below discovers the list instead, which
is why it needed no edit when the seventeenth repository appeared, and why this document is the only
thing here that did.

The retired first-generation client of the same name is a separate thing entirely — a local archive
with no Git remote, sharing no history with the repository counted above.

## What each repository has

All 17 repositories are public. The default branch of each repository is `main`.

| Control | Repositories | Notes |
|---|---|---|
| `.gitattributes` | 17 of 17 | One line: `* text=auto eol=lf` |
| `.editorconfig` | 17 of 17 | Editor defaults. No check enforces the file |
| `.githooks/pre-commit` | 17 of 17 | Identical file. See [Git hooks](#git-hooks) |
| Branch ruleset on `main` | 17 of 17 | `deletion`, `required_signatures` and `required_status_checks` |
| Dependabot alerts | 17 of 17 | GitHub reports a vulnerable dependency |
| `.github/dependabot.yml` | 17 of 17 | Version updates for the `github-actions` ecosystem, grouped, monthly, with a seven-day cooldown |
| Secret scanning and push protection | 17 of 17 | GitHub gives these to a public repository |
| `sha_pinning_required` for Actions | 17 of 17 | A workflow must pin each action to a commit SHA |
| The fleet gate, `.github/workflows/fleet.yml` | 17 of 17 | Identical file. See [The fleet gate](#the-fleet-gate) |
| The workflow gate, `.github/workflows/zizmor.yml` | 17 of 17 | Identical file. See [The workflow gate](#the-workflow-gate) |
| `specs` in `required_status_checks` | 17 of 17 | Added after the name had been published by a real run, and read back on each repository |
| `delete_branch_on_merge` | 17 of 17 | A merged branch is deleted by GitHub at the merge. See [A merged branch is deleted](#a-merged-branch-is-deleted) |
| The spec gate, `.github/workflows/openspec.yml` | 17 of 17 | Identical file. See [The spec gate](#the-spec-gate) |
| `openspec/config.yaml` | 17 of 17 | Present everywhere and deliberately NOT identical: its `context:` names one repository. See [The spec gate](#the-spec-gate) |
| `skills-lock.json` | 14 of 17 | The `skills` CLI lockfile. Identical in the 13 whose stack is Rust; `ratatoskr-web` has its own, for design skills |
| The Rust skill catalogue, `.agents/skills/` | 13 of 17 | 18 skills vendored from `po4yka/rust-skills`, identical in every repository whose stack is Rust. See [The Rust skill catalogue](#the-rust-skill-catalogue) |
| Size limits in a linter configuration | 3 of 17 | `clippy.toml` in the two with Rust, `eslint.config.js` in `ratatoskr-web`. See [Size limits](#size-limits) |
| A repository gate, `.github/workflows/ci.yml` | 3 of 17 | `ratatoskr-contracts`, `ratatoskr-platform` and `ratatoskr-web` |
| The advisory check, `.github/workflows/advisories.yml` | 2 of 17 | Identical file, in the two repositories with Rust. `ratatoskr-web` audits its own tree in `ci.yml` instead, because `npm audit` needs the lockfile and not a schedule. See [The advisory check](#the-advisory-check-that-runs-when-nothing-has-changed) |
| The drift check, `.github/workflows/drift.yml` | 1 of 17 | In `ratatoskr-workspace`, and it reads all 17. See [The drift check](#the-drift-check) |
| The release, `.github/workflows/release.yml` | 1 of 17 | In `ratatoskr-platform`. See [Deployment](#deployment) |

### What the ruleset requires, and what it cannot

The ruleset does not include the `non_fast_forward` rule. The account has one administrator, and
agents push with the same token. A bypass for that administrator makes the rule apply to nobody, and
a rule that applies to nobody is a control that protects nothing.

`required_status_checks` was added anyway, with a bypass for that same administrator, and the
difference from the paragraph above is worth stating exactly rather than leaving it to look like an
inconsistency.

A force-push is something only the administrator does here, so an administrator bypass empties that
rule completely. A required check is not like that. Three classes of actor are bound by it and none
of them holds the administrator role: a pull request from Dependabot, which this fleet now receives
every month; the `GITHUB_TOKEN` a workflow runs with; and any pull request from outside. For all of
those the rule is absolute — a red check blocks the merge and no bypass exists.

For the administrator's own direct push to `main` the check is advisory, and that is a real
limitation, not a solved problem. What makes it different from a silent hole is that GitHub prints
the bypass on the push itself:

```
remote: Bypassed rule violations for refs/heads/main:
remote: - 2 of 2 required status checks are expected.
```

So every push that skipped the gate says so, in the terminal, at the moment it happens. A
`non_fast_forward` bypass produces no such line, which is the other half of why that rule was left
out and this one was not.

Measured on `ratatoskr-vault` before the fleet-wide change, in this order:

| Configuration | A signed direct push to `main` |
|---|---|
| `deletion` only | accepted |
| `+ required_status_checks`, no bypass | rejected: `GH013 ... 2 of 2 required status checks are expected` |
| `+ bypass for the administrator role` | accepted, with the bypass printed |

The required check names are the names GitHub publishes for the jobs, not the workflow names:
`invariants` from `fleet.yml`, `audit` from `zizmor.yml`, `specs` from `openspec.yml`, and in the
two repositories with code
`gate` and, in `ratatoskr-platform`, `linux/arm64 artifact`. Each is pinned to integration 15368,
the GitHub Actions application, so a check of the same name from another application cannot satisfy
it. A wrong name here does not fail open — it blocks every pull request forever, which is why a
control pull request was opened on `ratatoskr-vault` to confirm that GitHub reported
`mergeStateStatus: CLEAN` against the names as written.

`specs` was added to the rule in all 17 after `openspec.yml` had run once and published the name, and
each ruleset was read back afterwards rather than trusted to the write. It is safe to require for the
reason the three below are not: `openspec.yml` triggers on `push` and `pull_request`, so every pull
request produces it. The pull request that added this paragraph was the control — GitHub reported
`mergeStateStatus: CLEAN` against the four names as written.

`advisories`, `drift` and `release` are deliberately NOT required. None of them runs on `push` or
`pull_request`, so requiring one would block every merge and never be satisfied.

`required_signatures` costs nothing here: every commit in the recent history of these repositories
already verifies, and GitHub signs the commits it makes itself, so Dependabot is unaffected.

The `deletion` rule works. A test confirmed this on a temporary branch: with the rule, the API
refuses the deletion and answers `422 Cannot delete this branch`. Without the rule, the same request
deletes the branch.

## The Rust gate

Two repositories contain Rust code. Each repository runs its gate in `.github/workflows/ci.yml`.

`ratatoskr-contracts` runs six commands:

```bash
cargo fetch --locked
cargo deny check
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo contracts check
cargo test --workspace --locked
```

`ratatoskr-platform` runs seven commands:

```bash
cargo fetch --locked
cargo deny check
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo build --workspace --locked
cargo test --workspace --locked
cargo build --workspace --locked --release
```

The debug build in `ratatoskr-platform` is necessary. `services/edge/tests/boot.rs` starts
`ratatoskr-ingest` and `ratatoskr-scheduler` as child processes. `cargo test` builds the binary of
the package under test only. It does not build the binary of a sibling package. Without the debug
build, three of the four boot tests fail on each clean checkout.

Each workflow has a final step that compares its own `- run:` lines with the command list in the
repository's `DEVELOPMENT.md`. The step fails if the two lists are different. `AGENTS.md` and
`DEVELOPMENT.md` both state that the two lists are one list. Before this step, no check enforced the
rule.

### `cargo deny`

`deny.toml` is in each of the two repositories. The files are the same, except for the `[sources]`
section.

`cargo deny` earns its place. It is the only tool in this project that found real defects. On its
first run against `ratatoskr-platform` it reported five advisories:

| Advisory | Defect |
|---|---|
| RUSTSEC-2026-0049 | A certificate revocation list is not authoritative for its distribution point |
| RUSTSEC-2026-0098 | A name constraint for a URI name is accepted incorrectly |
| RUSTSEC-2026-0099 | A name constraint is accepted for a certificate with a wildcard name |
| RUSTSEC-2026-0104 | A panic is reachable when the code parses a revocation list |
| RUSTSEC-2025-0134 | `rustls-pemfile` is unmaintained, and no safe upgrade exists |

Four advisories were in `rustls-webpki` 0.102.8. `async-nats` 0.42 supplied that version.
`ratatoskr-edge` binds the public listener, and the panic was in its TLS path. The crates deny
`panic`, `unwrap_used` and `expect_used` in their own code for this reason.

The remedy in each advisory does not work here. `cargo update -p rustls-webpki` cannot go from 0.102
to 0.103, because the minor version of a `0.x` crate is the incompatible part. `async-nats` 0.48 and
later need `rustls-webpki` 0.103.10 or later. `async-nats` 0.50 gives `rustls-webpki` 0.103.14, and
it removes `rustls-pemfile` from the graph. No source file needed a change.

`[sources] required-git-spec = "rev"` gives an exit code to a rule that `Cargo.toml` states in
prose: a branch moves, and a tag can be moved, so neither one pins. In `ratatoskr-contracts`,
`[sources] unknown-git = "deny"` is a publication requirement. Cargo refuses to publish a crate that
has a git dependency. Without the rule, that failure first appears at milestone 10.

### The advisory check that runs when nothing has changed

`cargo deny check` runs in `ci.yml`, on `push` and `pull_request`. That trigger can only answer one
question: does this change introduce a problem. It cannot answer the other one, because the thing
that changes is not the tree. RustSec publishes continuously, and a crate is yanked with no commit
here.

The five advisories in the table above are the measurement. They were in the graph for six
milestones. No commit in those six milestones would have turned the gate red, because the gate was
correct about every tree it was shown.

`.github/workflows/advisories.yml` asks the second question on a daily schedule, in both repositories
that have code. The file is identical in the two.

| Choice | Why |
|---|---|
| `advisories` only, not a full `cargo deny check` | `bans`, `licenses` and `sources` are functions of the tree alone. Running them on a timer can only repeat what the gate already said about the commit that produced that tree. `advisories` is the one section whose answer changes with no commit at all |
| Daily | RustSec publishes on no schedule of its own, and a run costs about one minute of a runner that is free on a public repository |
| `cron: "17 6 * * *"`, not on the hour | GitHub queues every `0 * * * *` in the world together and delays them |
| No cache | The job never invokes `rustc`. It reads `Cargo.lock` and the manifests behind it, and nothing else |
| `cancel-in-progress: false` | A scheduled run has nothing newer to yield to. `true` would let a manual dispatch cancel the nightly answer |
| It files an issue as well as failing | A workflow log is deleted after 90 days, and an advisory can outlive that |
| One open issue, commented on | Not one issue per night. The open issues are listed and filtered exactly rather than searched: GitHub's search index is eventually consistent, so a search is how a duplicate check files a duplicate |

Both halves were tested. The passing half ran on `main` in both repositories and reported
`advisories ok`, with the reporting step skipped. The failing half ran on a temporary branch whose
check command was replaced by one that fails: the job ended red, the issue was created with the log
in it, and a second run of the same branch added a comment instead of a second issue. The branch and
the issue were then deleted.

GitHub disables a scheduled workflow after 60 days with no commit to the repository, and reports
that by email only. `workflow_dispatch` is on the file so the check can be run by hand, and the drift
check below is what notices that the file has been deleted.

### Clippy lints

Each workspace denies `unsafe_code`, `missing_docs`, `panic`, `unwrap_used` and `expect_used`. These
lints close each explicit panic path. They do not close the most common implicit path, so each
workspace also denies two lints from `clippy::restriction`:

- `indexing_slicing` — `v[i]` and `&s[a..b]` panic when the index is out of bounds.
- `string_slice` — `&s[..n]` panics when `n` is not a UTF-8 character boundary.

`pedantic` does not enable either lint. Both lints are `allow` by default.

Production code in both repositories violates neither lint. Test code violates both. `clippy.toml`
in `ratatoskr-platform` sets `allow-indexing-slicing-in-tests = true`, beside the
`allow-unwrap-in-tests` and `allow-expect-in-tests` settings that were already there. Clippy has no
equivalent setting for `string_slice`, so three test files have a file-level `#![allow]` with a
reason.

Two sites were changed instead of suppressed. `windows(2)` with two indexes became `is_sorted_by`.
`rfind` with a slice became `rsplit_once`. Both changes were confirmed to be equivalent, and not
only quieter.

### Dependabot

`.github/dependabot.yml` is in all 17 repositories, and each one watches the `github-actions`
ecosystem only. The configuration groups the updates into one pull request each month.

The file was in the two Rust repositories first. It is now in all 16 because each repository pins two
actions across two workflows, and a pin without a maintainer is the thing this file exists to prevent.
An action pin rots, and it rots silently: a reader cannot find a pin whose `# vX.Y.Z` comment no longer
agrees with its SHA. Dependabot corrects the SHA and the comment together.

The `cargo` ecosystem is deliberately absent from the two Rust repositories. Each commits its
`Cargo.lock` and runs each command with `--locked`. A dependency bump is therefore a deliberate act,
and `cargo deny check` in the gate reports an advisory on the day it is published. In the other 14 no
language ecosystem is named at all: the commit that brings the first code brings its own gate and its
own lockfile policy, and that commit is where the question belongs.

Each file sets `cooldown: default-days: 7`. A SHA pin defends against a tag being moved under us. It
does nothing about a release that is malicious on the day it is published, because Dependabot would
then offer the attacker's commit with a version comment that looks correct. The cooldown puts a week
between a release and the pull request that proposes it. `zizmor` reports the absence of one as
`dependabot-cooldown`, and that is how the two original files were found to be missing it.

The cost is visible and worth stating: up to 16 grouped pull requests a month, one per repository,
each of them one or two SHA bumps with a green gate behind it.

## Size limits

How long a function may be, how many arguments it may take, how deep a block may nest, and how long a
file may be. Three repositories hold code and each carries these in its own linter configuration. The
other 14 enforce nothing yet, and one step in the fleet gate is what keeps that from being a hole.

Every number below is the worst case the tree already had when it was written, plus zero or a stated
margin. That is the same choice as `shadscan --fail-under` in `ratatoskr-web`: a limit set at the
score a tree already has fails on a regression, and a limit set at an aspiration fails on work that
has not been done yet. Nothing was refactored to make a number fit, and no number was raised to make
a build pass.

### The two repositories with Rust

`clippy.toml` in each carries three thresholds. Only one of the three changes behaviour, and saying
which is the reason the other two are worth writing down at all.

| Limit | Value | Worst case measured | Lint | Already enforced before this? |
|---|---|---|---|---|
| Lines in a function | 100 | 98 — `accept`, `crates/public-api/src/captures.rs` (platform). 83 — `lint_type`, `tools/contractsc/src/lint.rs` (contracts) | `clippy::too_many_lines` | Yes. `pedantic` enables it and `-D warnings` makes it fatal. 100 is clippy's own default, written down so that a toolchain bump raising the default cannot loosen these trees silently |
| Arguments in a signature | 7 | 7 — three functions in platform: `crates/operations/src/lib.rs:258` and `:456`, and `crates/identity/src/relay.rs:48`. 6 in contracts | `clippy::too_many_arguments` | Yes, warn-by-default in `clippy::complexity`. 7 is clippy's default, pinned for the same reason |
| Block nesting depth | 5 | 5 — nine blocks in platform, two in contracts | `clippy::excessive_nesting` | **No.** The lint is warn-by-default, but its threshold defaults to 0 and 0 disables it. The `clippy.toml` line is what turns the lint on |
| Lines in a tracked `.rs` file | 850 | 817 — `tools/contractsc/src/compat.rs` (contracts). 716 — `crates/operations/src/lib.rs` (platform) | none; a step in the `gate` job | **No.** Clippy has no file-length lint |

Two properties of `too_many_lines` were measured rather than assumed, because both change what a
number means. It does not count blank lines or comment-only lines: a function of five statements,
five blank lines and five comments is silent at a threshold of 10. And clippy fires only when the
count EXCEEDS the threshold: a ten-line body is silent at 10 and an eleven-line body reports
`(11/10)`. So a seven-argument function at a threshold of 7 is silent, and the eighth argument is the
failure.

The worst cases were read out of the diagnostics themselves, which print the count as `(98/10)`,
after lowering each threshold in `clippy.toml`:

```bash
cargo clippy --workspace --all-targets --locked --message-format short \
  -- -W clippy::too_many_lines -W clippy::excessive_nesting
```

The extra `-W` on the command line is not decoration. It changes the invocation hash, which is what
forces clippy to re-run after a `clippy.toml` edit. Without it a run can print `Finished` and no
diagnostics, and the reading is of nothing.

The file-length limit is one line in each `gate` job rather than a script:

```bash
git ls-files -z "*.rs" | xargs -0 -r wc -l | awk '$2 != "total" && $1 > 850 { print; bad = 1 } END { exit bad }'
```

`*.rs` only, which is why it needs no exclusion list. `Cargo.lock` at 3920 lines,
`openapi/openapi.json` at 1261 and `schema.sql` at 1250 are not source, and an exclusion list would
be a second source of truth that goes stale in silence. The limit exists because the per-function
thresholds do not imply it, and this is not theoretical here: `crates/operations/src/lib.rs` is 716
lines across fourteen top-level functions with a longest of 77, so it passes every clippy threshold
in the repository and is still the largest module in the fleet.

The escape is `#[expect(clippy::too_many_lines, reason = "...")]` at the site, and never a raised
number — a raised number applies to code nobody has written yet. `expect` and not `allow`: `expect`
reports `unfulfilled_lint_expectations` once the item drops back under the limit, so the exemption
deletes itself instead of outliving its reason. The `allow-unwrap-in-tests` family covers none of
these three lints and `--all-targets` measures test bodies, so a table-driven test that outgrows a
limit takes the same attribute at the same site.

`ratatoskr-contracts` carries platform's numbers and not its own tighter ones; 83 lines and 6
arguments would both fit it today. One number per limit across the fleet is cheaper to read than two
numbers and a footnote explaining the difference, and `clippy.toml` records the tighter values it
could take.

One function was left alone deliberately, and it is the one with two lines of headroom. `accept` in
`crates/public-api/src/captures.rs` is 98 lines because it runs six sequential fallible steps in one
transaction, each with an explicit early-return arm, because that workspace denies `unwrap`, `expect`
and `panic!`. Splitting it would spread one transaction across several functions. When the limit
eventually fires there, read the function before shortening it.

### `ratatoskr-web`

`eslint.config.js` carries four rules, all at severity `error`.

| Limit | Value | Worst case measured | Rule |
|---|---|---|---|
| Lines in a file | 200 | 184 — `src/components/theme-provider.tsx` | `max-lines` |
| Lines in a function | 120 | 115 — `ThemeProvider`, in the same file | `max-lines-per-function` |
| Cyclomatic complexity | 8 | 7 — the keydown handler, in the same file | `complexity` |
| Parameters | 2 | 2 — `componentDidCatch`, `src/app/error-boundary.tsx`, a signature React defines and this repository cannot change | `max-params` |

`skipBlankLines` and `skipComments` are set for the two line counts. The configuration and the
components here explain why a value is what it is, and a limit that counted prose would tax the
practice that makes the tree readable.

`error` and not `warn`, and that is the difference between a gate and the appearance of one. CI runs
`npm run lint`, which is a bare `eslint .` with no `--max-warnings`. Measured:
`npx eslint . --rule '{"max-lines-per-function":["warn",1]}'` prints 85 warnings and exits 0, and the
same rule at `error` exits 1. A size rule at `warn` would report every finding and never fail a
build, which is worse than no rule.

ESLint's own defaults were not used, and neither one would have worked. `max-lines` defaults to 300,
which nothing in this tree could reach. `max-lines-per-function` defaults to 50, which fails the tree
today on `ThemeProvider`.

The three generator-owned directories — `src/components/ui`, `src/components/canvasui` and
`src/components/aicss` — are exempt from all four, in the same block that already exempts them from
`react-refresh/only-export-components` and `no-empty`. Canvas UI's `Ripple.tsx` is 550 code lines and
its `createRipple` is 317, so leaving the rules on would fail the build on five findings in files
that the next `npm run ui:add:aicss` rewrites. A size finding there also cannot be answered with a
one-line edit the way `no-empty` can: the answer is a refactor, and the generator undoes it. The
alternative is setting the standard for hand-written code at the shape of a generated WebGL harness.

### The 14 repositories with no code

They enforce nothing, because there is nothing to enforce. What keeps that from being a hole is one
step in `fleet.yml`, which is byte-identical in all 17 repositories and sits beside the step that
already asserts a manifest arrives with its `ci.yml`:

- a tracked `Cargo.toml` requires a tracked `clippy.toml`
- a tracked `package.json` requires a tracked `eslint.config.*`

The step asserts that the file exists. It cannot read the numbers inside it and does not try — the
pull request that adds the file is where the numbers are read. That is the ceiling of this control,
and it is stated in the step itself.

Eleven of the 14 expect Rust and one expects TypeScript, so the assertion covers 12 of them. The gap
is `ratatoskr-export-agent`, whose first code is Swift, and `ratatoskr-mobile`, whose first code is
Kotlin and Swift. The fleet has chosen no linter for either language, and choosing `swiftlint` or
`detekt` for a repository that has not started is the configuration-for-an-unstarted-milestone that
`ratatoskr-platform`'s own rules refuse. The `DEVELOPMENT.md` in both of those repositories records
the gap, and the scaffold pull request there names the tool and adds the assertion.

Measured: the step exits 0 in all 17 repositories as they stand. A scratch repository holding a
`Cargo.toml` and a `package.json` and neither lint file exits 1 and prints both errors. Adding an
untracked `clippy.toml` to it still exits 1, which is the case the word "tracked" is there for.

## The fleet gate

Each repository runs `.github/workflows/fleet.yml`. The file is identical in all sixteen. It installs
nothing and uses one action, so it has no supply-chain surface beyond the checkout and it cannot fail
for a reason that has nothing to do with the tree.

Seven steps, and each one fails only when something is really wrong:

| Step | The failure it catches |
|---|---|
| The files every repository in the fleet must have | A required document is no longer tracked. `SECURITY.md` and `AGENTS.md` would go unnoticed longest, because nothing builds from them |
| The pre-commit hook is present and executable | A hook that lost its executable bit is silently inert, and git records the mode |
| No CRLF in a tracked text file | A blob written past the `.gitattributes` filter, which is what a commit through the web editor or the contents API does |
| No credential in a tracked file | A password in a URL, or a private key, anywhere in the tree |
| Every workflow pins each third-party action to a commit SHA | A moving ref in a workflow that `push` and `pull_request` never trigger, or a nested `uses:` in a composite action |
| Code cannot land without a gate | A manifest arrives and no `ci.yml` arrives with it, or a `ci.yml` that never runs a test |
| Code cannot land without its size limits | A `Cargo.toml` with no `clippy.toml`, or a `package.json` with no `eslint.config.*` |

The last step deserves its name. It is not a second gate: it asserts that a gate exists. An earlier
draft tried to BE the gate, by running the Rust commands itself. That draft knew only `Cargo.toml`, so
it was permanently green in the three repositories whose first code is Kotlin, TypeScript and Swift —
green on exactly the commit it existed to catch. The version that shipped fails closed for every
language in the fleet.

There is one thing this file cannot do by construction. It runs inside one repository and can see
only that repository, so it can assert that a file EXISTS and never that it is the same file as the
one in the other fifteen. [The drift check](#the-drift-check) is the answer to that, and it is the
only job in the project that reads more than one repository.

### Why the credential and key checks are not redundant

GitHub secret scanning is enabled on all seventeen repositories, and it has a pattern for a PostgreSQL
connection string that carries credentials and a pattern for an RSA private key. Both are classified as
GENERIC rather than provider patterns, and generic-pattern scanning is a separate setting.

On these repositories that setting reads `disabled`, and a `PATCH` that tries to enable it answers 200
and leaves it disabled. Neither shape is scanned here, so these two steps are the only thing that looks
for them. The pre-commit hook applies the same rule to staged lines; the workflow applies it to the
whole tree, which is the version that matters, because `git commit --no-verify` skips the hook.

### What the gate does not do, and why

It does not lint prose. Every candidate was measured across all sixteen repositories before this file
was written, and the next section records each result. Two of those measurements were made for this
gate and are the clearest of the set:

| Candidate | Findings | Real defects |
|---|---|---|
| A check on backticked paths that look like files | 156 | 0 |
| A check that each `> Status:` uses the vocabulary `docs/README.md` defines | 16 | 0 |

The documents legitimately name files that are planned and absent by design (`workspace.toml`), files
that live in another repository (`ratatoskr-workspace/docs/DEPLOYMENT_TARGET.md`), a file deleted on
purpose with a note saying when to restore it (`.cargo/config.toml`), and a template placeholder
(`NNNN-short-title.md`). Each of the 156 is one of those. The `Status:` result has the same shape: all
sixteen are the `ARCHITECTURE.md` header, which is a deliberate prose sentence rather than a vocabulary
word, in every repository.

A repository still gains its own `ci.yml` when it gains code. The fleet gate does not replace it, and
the step named above fails until it arrives.

## The workflow gate

Each repository runs `.github/workflows/zizmor.yml`. The file is identical in all sixteen. It runs
[`zizmor`](https://github.com/zizmorcore/zizmor) over that repository's own workflow and Dependabot
files, through `zizmorcore/zizmor-action` pinned to a commit SHA, with the `zizmor` version pinned to
`1.29.0`.

A workflow is the one file in these repositories that runs with a token, and until this gate arrived
nothing read one as code. The fleet gate greps for an unpinned `uses:`, which tests one condition
rather than reading the file.

### Why it is a separate file from the fleet gate

The fleet gate installs nothing and uses one action, so it cannot fail for a reason that has nothing
to do with the tree. That property is the reason it exists in the form it does, and a `zizmor` step
inside it would end it: `zizmor` pulls a container image and queries the GitHub API. Two files means
the check name says which of the two failed, and a network fault never masks a missing document.

### The configuration, and the measurement behind each choice

| Input | Value | Why |
|---|---|---|
| `persona` | `pedantic` | Not the default. Against a fixture carrying ten known-bad patterns, the `regular` persona reported five and `pedantic` reported ten |
| `min-severity` | `low` | Drops the informational tier. Across these 16 repositories that tier is one audit, `anonymous-definition`: 34 findings, 0 defects. The trade is that a future finding arriving at informational severity is dropped unseen |
| `advanced-security` | `false` | This is what makes it a gate. See below |
| `annotations` | `true` | Findings appear on the diff. The action refuses this together with `advanced-security: true` |
| `version` | `1.29.0` | Pinned, like `rust-toolchain.toml` and `Cargo.lock`. Dependabot moves the action's SHA and does not move this input, so a `zizmor` release cannot turn 16 repositories red overnight |

The two audits that `pedantic` adds and `regular` does not report at all are the two that matter
here. `excessive-permissions` is the `permissions: write-all` that `SECURITY.md` forbids.
`unpinned-images` is this fleet's SHA-pinning rule applied to a container image instead of an action.

`advanced-security: false` deserves its own line, because the default is `true` and the default is not
a gate. With `advanced-security: true` the action uploads SARIF to the security tab and **does not fail
on findings** — GitHub's model is that a code-scanning workflow fails only on internal errors, and
blocking a merge is then a ruleset to configure and keep configured. With it off, `zizmor`'s own exit
status is the answer, which is the shape every other check in this fleet already has.

Online audits are on, which is the action's default. They are what makes `impostor-commit` work: it
asks GitHub whether the forty hex characters in a `uses:` line are a commit in the repository they
name. A grep cannot tell a real object name from a plausible one, and this fleet's first
`ratatoskr-contracts` run failed on a SHA that did not exist.

### What it catches

A fixture carrying ten known-bad workflow patterns was written and audited under both personas.

| Pattern in the fixture | `regular` | `pedantic`, `min-severity: low` |
|---|---|---|
| `pull_request_target` trigger | reported | reported |
| `uses:` on a moving tag | reported | reported |
| A `uses:` SHA that is not a commit in that repository | reported | reported |
| `${{ github.event.issue.title }}` in a `run:` block | reported | reported |
| A checkout that keeps its credential | reported | reported |
| `permissions: write-all` | **not reported** | reported |
| An unpinned service container image | **not reported** | reported |
| A `uses:` SHA that is not a released tag | not reported | reported |
| `${{ secrets.GITHUB_TOKEN }}` in a `run:` block | not reported | reported |
| A job with no concurrency limit | not reported | reported |

Each of the ten findings maps to one distinct planted pattern; the mapping was checked line by line.

### What the workflow gate does not see

`unpinned-images` reads a `services.<id>.image` key, a `jobs.<id>.container.image` key and a
`uses: docker://` step. It does not read a shell command, and it does not read a `Dockerfile`. Two
images in `ratatoskr-platform` are therefore outside it and stay on a tag:

- `nats:2-alpine`, started with `docker run` inside a `run:` block, because a service container cannot
  be given the `--jetstream` argument the tests need;
- `rust:1.97.0-slim-bookworm` and `debian:12-slim` in the committed `Dockerfile`, where the second is
  pinned to the target's glibc by tag on purpose.

This is recorded rather than fixed. A pin that no gate reads is a pin that rots, which is the failure
this fleet already documents for action pins, so adding one here would buy less than it looks.

## The spec gate

Each repository runs `.github/workflows/openspec.yml`. The file is identical in all seventeen. It
checks the OpenSpec artifacts: the specs that say what the system does, and the changes in motion
against them. `docs/adr/0008-openspec-and-test-first.md` records why the fleet plans this way.

Where the artifacts live: `ratatoskr-workspace` is the store, under the id `ratatoskr-workspace`, and
holds behaviour more than one repository can see. Each of the other sixteen has its own `openspec/`
root and references the store by name. `openspec/specs/` started empty in all seventeen and grows one
change at a time; the nine documents each repository already had were deliberately NOT converted, for
the reason the ADR gives.

Two commands, and the second is the one that earns the file:

| Command | The failure it catches |
|---|---|
| `openspec validate --all --strict` | A malformed proposal, spec or task list. `--strict` makes a warning fatal, and a change carrying no spec delta fails unless its `.openspec.yaml` declares `skip_specs: true` |
| `openspec validate --archived` | A change archived with a task still unticked. Archiving is what folds a delta into the specs, so this is a spec claiming behaviour that nothing proved |

Both halves of the second one were measured, on a change whose task list is the pair this fleet
requires — `1.1 Add a failing test ...`, `1.2 Make it pass`. With `1.2` unticked the command reports
`1 incomplete task (1/2 completed)` and exits 1. With it ticked the same change passes and the
command exits 0. That is the whole of what CI can say about test-first, and it is worth more than it
looks: the pair shape means an unticked second task is an implementation that was never written, and
an unticked first task is a test that was never run.

### Why it runs in the fourteen repositories that have no specs yet

Because it answers correctly there, which was measured rather than assumed. Against an OpenSpec root
with no specs and no changes, `openspec validate --all --strict` prints `No items found to validate`
and exits 0, and `openspec validate --archived` prints `No archived changes found` and exits 0. One
identical file therefore works everywhere, and a repository is gated from the commit that writes its
first spec rather than from a later commit that remembers to add the workflow.

### Why it is a separate file from the fleet gate

The same reason `zizmor.yml` is separate, and it is the reason `fleet.yml` exists in the form it
does: `fleet.yml` installs nothing, so it cannot fail for a reason that has nothing to do with the
tree. `openspec` is an npm package and needs Node. Two files means the check name says which of the
two failed, and a network fault reddens `specs` and never `invariants`.

### The version is pinned, and here that is load-bearing

`@fission-ai/openspec@1.10.0`, pinned in the workflow the way `zizmor` is pinned to `1.29.0`.
Dependabot moves an action SHA and does not move this input. Stores — the mechanism the fleet plans
with — are a beta feature whose flags, file formats and JSON keys may change between releases, so an
unpinned CLI could change the meaning of the gate without a commit here. Raising it is one commit in
seventeen repositories, and the drift check is what says so.

### What it does not do

It reads the artifacts, not the code. Nothing here asserts that a spec is true of the implementation,
that a scenario has a test, or that the test was written first. The last of those is not a gap that
better tooling closes — see the rejected table below.

`openspec/config.yaml` is the other half of this control and is not a check at all. Its `rules` and
`operations.apply.guidance` state the test-first task shape, and OpenSpec injects them into every
planning and implementation request. That is a rule an agent is given at the moment it plans, rather
than one it could have read. It is advisory by construction: no exit code stands behind it.

### Measured before it was turned on

`openspec init` generates nineteen files per repository — six commands under `.claude/commands/opsx/`,
six skills under `.claude/skills/openspec-*/`, six under `.agents/skills/openspec-*/` for Codex, and
`.agents/skills/.openspec-target`. Every one of them is markdown.

That made one measurement necessary before anything was committed, and it is the lesson [the gate
matched itself](#the-gate-matched-itself-and-the-local-test-could-not-see-it) already paid for once:
a gate that scans the repository must be tested against a tree that already contains the new files.
`fleet.yml`'s CRLF step, credential step and private-key step were run against a tree carrying all
nineteen. All three passed, and no file in the set holds a base64 run long enough for the private-key
body test to consider it.

`openspec store setup` was measured too, and rejected in favour of two smaller steps. It works on a
non-empty Git repository, but it makes its own commit, with the subject
`Initialize OpenSpec store <id>` — not a Conventional Commits subject, and not one this fleet would
have written. `.openspec-store/store.yaml` is three lines; writing it by hand and running
`openspec store register . --id ratatoskr-workspace` produces the same result and commits nothing.

### The one suppression, and why it is not a raised threshold

`zizmor --persona pedantic --min-severity low` reports one finding on this file: `adhoc-packages`,
low severity, on the `npm install --global` line. The workflow gate runs at exactly that severity, so
the finding would turn all seventeen repositories red, and it was found by running zizmor over the
new file before it was committed rather than by a first red run.

The audit asks for a lockfile. There is no way to have one here: a lockfile needs a `package.json`,
and a tracked `package.json` makes `fleet.yml` demand an `eslint.config.*` in fourteen repositories
that have no code to lint. The property the audit protects is that what executes is a known version,
and `@fission-ai/openspec@1.10.0` is exactly that — the same pin, in the same form, as
`version: 1.29.0` in `zizmor.yml`.

So the line carries `# zizmor: ignore[adhoc-packages]` with the reason written beside it, in the same
spirit as `#[expect(clippy::too_many_lines, reason = "...")]` at a site rather than a raised number in
`clippy.toml`. A raised threshold would apply to findings nobody has seen yet; this applies to one
line. With it in place, zizmor reports nothing across every workflow in every class of repository in
the fleet.

### The known limit, and it is the same shape as the hooks

Registering a store is per-machine state. It lives in `~/.local/share/openspec`, not in any
repository, so a fresh clone, a second machine and a CI checkout each know nothing about it — exactly
like `git config core.hooksPath .githooks`. A clone that has not registered resolves `references:` to
nothing, and `openspec doctor` reports it with a pasteable fix. `DEVELOPMENT.md` in every repository
carries the two commands.

## The Rust skill catalogue

Thirteen of the seventeen repositories hold Rust or plan to. `ratatoskr-contracts` and
`ratatoskr-platform` hold it today; eleven more name Rust and Tokio in their own `DEVELOPMENT.md` as
the intended toolchain, and `ratatoskr-workspace` plans the `ws` CLI in Rust. Each of the thirteen
carries eighteen skills under `.agents/skills/`, with `.claude/skills/` symlinked to them so Claude
Code and Codex read one copy rather than two.

The four that do not carry it are the four whose first code is another language: `ratatoskr-web` and
`ratatoskr-browser-extension` in TypeScript, `ratatoskr-export-agent` in Swift, and
`ratatoskr-mobile` in Kotlin Multiplatform and Swift. No Rust in this fleet crosses a language
boundary — there is no UniFFI, no JNI and no Swift C ABI anywhere in it — which is why the FFI half
of the catalogue is absent from all seventeen.

### Where they come from, and what a clone has to do

`po4yka/rust-skills`, BSD-3-Clause, vendored at commit `cb652d08` with `npx skills add`. That is the
same CLI and the same layout `ratatoskr-web` already uses for its ten design skills, which is why no
second mechanism was introduced for this.

A clone does nothing. This is the one control in this document that needs no per-machine step: the
files are tracked, so a fresh checkout has them, and nothing can be silently missing for whoever did
not run a command. `git config core.hooksPath .githooks` and `openspec store register` are both the
other shape, and both are recorded here as limits.

### Eighteen of forty-four, and the rule that chose them

A skill is vendored when this fleet's own stack names the thing it covers, or when it governs how any
Rust change is written, tested or reviewed. Each stack line was read from that repository's
`DEVELOPMENT.md` and `openspec/config.yaml` rather than assumed.

| Group | Vendored |
|---|---|
| Language and discipline | `rust-discipline`, `rust-code-style`, `rust-crate-architecture`, `rust-lints`, `rust-compiler-errors`, `rust-borrow-semantics`, `rust-pattern-semantics` |
| Build and supply chain | `cargo-workflows`, `rust-security`, `rust-serde` |
| Correctness and testing | `rust-tdd`, `rust-test-tools`, `rust-panic-safety` |
| Runtime | `rust-async-internals`, `rust-networking`, `rust-database`, `rust-observability` |
| Interface | `rust-cli` |

Two of them earn their place twice over. `rust-lints` owns `clippy.toml`, `workspace.lints` and
`deny.toml`, and `clippy.toml` is where this fleet's size limits live. `rust-tdd` is the Rust form of
the task pair that every `openspec/config.yaml` in the fleet requires.

### The twenty-six that were left out

| Left out | Reason |
|---|---|
| `rust-jni`, `rust-swift-ffi`, `uniffi-boundary`, `uniffi-packaging-versioning`, `ffi-error-progress-cancel`, `rust-android-build`, `rust-ios-build`, `rust-native-linking` | No Rust here crosses a language boundary. `ratatoskr-mobile` is Kotlin Multiplatform and Swift and `ratatoskr-export-agent` is Swift; neither plans a Rust core, and nothing links a native library |
| `rust-crate-release` | Nothing here publishes to crates.io, and its subject is SemVer bumps and deprecation, which the Development status forbids while it holds |
| `rust-wasm`, `rust-embedded-no-std` | No repository targets WebAssembly or bare metal |
| `rust-performance`, `rust-hot-path`, `rust-copy-on-write` | No profile has named a hot spot, because there is nothing to profile yet. This is the configuration-for-an-unstarted-milestone that this project refuses elsewhere. Add them to a repository the day a measurement asks for them |
| `rust-unsafe`, `memory-model`, `rust-sanitizers-miri`, `rust-send-sync`, `rust-pin-projection`, `rust-variance`, `rust-type-erasure`, `rust-callback-bounds`, `rust-iterator-impl`, `rust-macros`, `rust-event-loop-state` | Advanced language material with no site in this fleet. Add one to a repository the day it writes its first `unsafe` block, hand-written `Iterator`, proc macro or `Pin` projection |
| `rust-debugging` | Half of it is Android tombstones and `addr2line` symbolication, and this fleet deploys one Linux server. The host-first reproduction half overlaps `rust-tdd` |

Adding one later is a one-line command and a thirteen-repository commit, the same shape as raising a
pinned version.

### One skill contradicts a binding rule, and the rule wins

`rust-database` carries a section on deploying migrations in expand-migrate-contract phases, with
`sqlx migrate run` in it. The Development status in every `AGENTS.md` says there are no migrations at
all while it holds: a schema change edits the schema definition in place. That is not a defect in the
skill, which is written for production Rust in general, but an agent that reads it and follows it
writes what the owner has forbidden. `AGENTS.md` in each of the thirteen names the conflict and
resolves it, at the point where an agent reads the rest.

That is the only conflict found. Every other vendored skill was read against the Development status
and against this document, and none of the others contradicts either.

### What the lockfile pins, and what it does not

`skills-lock.json` records the source repository, the path of each `SKILL.md` and a content hash. It
does NOT record a commit, so `npx skills update` fetches whatever the catalogue's default branch
holds at that moment. The pin here is the tracked bytes themselves: an update arrives as a diff in a
pull request, and the drift check fails for as long as the thirteen disagree. That is weaker than the
`@1.10.0` on the OpenSpec CLI and stronger than nothing, and it is stated rather than implied.

### Measured before it was committed

The rule this project applies to a gate that scans the repository is that the gate is tested against
a tree that already contains what is being added. These were run against the thirteen trees with the
skills in them, not against the trees from before:

| What | Result |
|---|---|
| The credential-URL pattern in `fleet.yml` | 0 matches across the eighteen vendored skills, and 0 across all forty-four |
| The private-key test in `fleet.yml` | 0 files carry a PEM header |
| `No CRLF in a tracked text file` | 0 |
| `Code cannot land without a gate`, and `...without its size limits` | Unchanged. No skill adds a root manifest, and the CLI is never a dependency: nothing installs it in CI |

Every step of `fleet.yml` was then run against each of the thirteen trees, and all thirteen pass.

The vendored bytes are identical in all thirteen, checked before the first push by comparing staged
blob names and modes rather than text: 67 vendored paths in each repository — 48 files, 18 symlinks
and `skills-lock.json` — and one distinct tree across the thirteen.

## The drift check

Four files are the same file in every repository, and until now nothing noticed when they stopped
being the same file. `fleet.yml`, `zizmor.yml` and `.githooks/pre-commit` are byte-identical in all
16. `.github/dependabot.yml` has exactly two forms, one for a repository with Rust in it and one for
a repository that has no code yet.

They are identical because they were copied there, not because anything keeps them so. The next fix
lands in whichever repository its author happened to be working in, and the other fifteen keep the
defect with every gate green.

`ratatoskr-workspace/.github/workflows/drift.yml` runs weekly and on demand. It compares git blob
names rather than text, so the comparison is exactly git's own notion of identity, and the same tree
read carries the file mode — which is how a `pre-commit` that has lost its executable bit is caught
in the same pass. One `git/trees?recursive=1` call per repository, sixteen calls.

| Assertion | The failure it catches |
|---|---|
| `fleet.yml`, `zizmor.yml`, `openspec.yml` and `.githooks/pre-commit` are one blob across the fleet | A fix applied in one repository and not the other sixteen |
| The 19 files `openspec init` generates are one blob each, and the SET of their paths is the same everywhere | A partial `openspec update`: the CLI raised in the repository its author was in, forgotten in the other sixteen. A release that adds a seventh command arrives as a missing path rather than a changed one |
| `openspec/config.yaml` is PRESENT in every repository | The planning root deleted from one. Sameness is not asserted: `context:` names one repository's role, stack and tests |
| The 66 vendored skill paths are one blob each, and the SET of them is the same, across the 13 repositories whose stack is Rust | A skill edited in place in one repository; a skill added to one and forgotten in the other twelve; a partial `npx skills update` |
| `skills-lock.json` is one blob across those same 13 | A lockfile raised in one repository without the files it locks, or the reverse |
| At least 13 repositories carry `.agents/skills/rust-tdd/SKILL.md`, and at least 66 vendored paths exist | The catalogue deleted from one repository, and an update that drops a skill from every repository at once |
| Every repository with a tracked `Cargo.toml` carries the catalogue | Rust arriving in a repository that never received the skills. It is the late half of the answer, and it is the only half that is checkable: nothing in a tree of documents says which language the first commit will be in |
| Each of them is present in every repository | A deletion, in a repository where `fleet.yml` itself was the thing deleted |
| `.githooks/pre-commit` has mode `100755` everywhere | A hook that is committed but inert |
| `dependabot.yml` is one blob within each of its two classes | The two forms drifting into three |
| `advisories.yml` is present and one blob in every repository with Rust | A deletion that no `push` trigger can see, because the file has no `push` trigger |
| `ci.yml` is PRESENT in every repository with Rust | A gate deleted from a repository that already had one |

`ci.yml` is checked for presence and deliberately not for sameness. The gates are legitimately
different: `ratatoskr-platform` runs a PostgreSQL service, a NATS container and a native arm64 job,
`ratatoskr-contracts` has none of those to run, and `ratatoskr-web` runs npm and no Rust at all. The
first version of this check required them to be identical and reported the difference as drift on its
first local run, which is how the distinction was found before it reached CI.

The presence assertion reaches the Rust repositories only, and `ratatoskr-web` is therefore outside
it: a `ci.yml` deleted there would pass this check. `fleet.yml` catches the same deletion from the
other side — it fails on a manifest with no gate — so the hole is covered, but by a different file
and only while `package.json` is still tracked. Widening the assertion to every repository with a
manifest is the fix, and it is not made here.

The repository list is discovered, not written down. A seventeenth repository that joins the fleet
without the shared files is the same drift, and a fixed list would report that as healthy by never
looking. The job also fails if fewer than 16 are discovered, which is what a repository disappearing
looks like.

It runs with the repository-scoped `GITHUB_TOKEN` and no other credential. That token can read
another repository's public data, which is all this job needs; that was the one thing about the
design that could only be confirmed by running it, and the first run reported `fleet: 16
repositories` and `collected 71 tracked paths`.

Verified against the real fleet before it shipped, on the tree data as it actually stands: the
passing case reports `every shared file is identical across the fleet` and exits 0, and four planted
defects each produce a precise message and exit 1 — a changed `fleet.yml` in one repository, a
`pre-commit` at mode `100644`, a deleted `advisories.yml`, and a seventeenth repository with none of
the files.

### An empty repository crashed it, on the first day

The fourth of those planted defects was simulated by adding a name to the discovered list with no
tree rows behind it. A real seventeenth repository is not that. `ratatoskr-web` was created about an
hour after this check shipped, and for the six minutes before its first commit it was a repository
with no commits at all. `git/trees/main` does not answer an empty tree for one of those; it answers
`409 Git Repository is empty`, `jq` then failed on `null`, and `set -euo pipefail` ended the step
with exit code 5.

The run was red, which is the correct colour, and for entirely the wrong reason: it died while
reading and never reached the comparison, so it reported nothing about the repository that caused
it. A check that fails without saying what it found is a check somebody re-runs and then ignores.

The fix treats an empty repository as a finding rather than an error. It is collected into a
separate list, reported once by name — `has no commits on main, so it carries none of the shared
files` — and left out of the per-file comparisons, because that one sentence is already the whole of
what there is to say about it. The job still exits 1.

This is the second time the same lesson has been paid for here. [The gate matched
itself](#the-gate-matched-itself-and-the-local-test-could-not-see-it) records the first: a control
tested only against a fixture agrees with the fixture. A planted row in a TSV is not an empty
repository, and only the real one had a 409 in it.

## A merged branch is deleted

**A branch that has been merged into `main` is deleted. It is not kept.** `delete_branch_on_merge` is
set on all 17 repositories, so GitHub removes the head branch at the moment the pull request merges,
and nobody has to remember to.

The rule states what to do about the branches that already existed, too: delete them. Eighty-two of
them were, in one pass, leaving `main` alone in every repository.

A merged branch holds nothing. Its head is reachable from `main` by definition, so every commit,
every tree and every blob it names survives the deletion, and `git log` still tells the whole story.
What it does hold is a name that looks like work in progress. A repository listing sixteen branches
that are all finished is a list a reader has to check one by one before learning that none of them
matters, and the pull request that merged each one is the durable record — it keeps the branch name,
the diff, the discussion and the checks that passed.

### Why this is safe, stated exactly

Two things were verified before anything was deleted, and the second was re-verified for each branch
immediately before its own `DELETE`:

| Check | Result |
|---|---|
| Every branch head reachable from `main` | 82 of 82 compared `identical` or `behind` against `main`. None was `ahead` or `diverged` |
| Nothing unmerged anywhere in the fleet | 0 branches in 0 repositories |

The re-check per branch is the part worth keeping. A single scan taken up front is a reading of a
moment, and the fleet has already paid once for trusting one of those — `docs/QUALITY_GATES.md`
opens by recounting how a repository count taken an hour early was correct when it was taken and
wrong when it was used. The loop fails closed: a branch whose status reads anything but `identical`
or `behind`, including an empty answer, is kept and reported rather than deleted.

Locally the same rule uses `git branch -d`, which refuses a branch that is not fully merged. Never
`-d`'s uppercase form: `AGENTS.md` requires explicit approval for removing an unmerged branch, and
`-D` is precisely the flag that removes one without asking.

### It does not weaken the `deletion` ruleset rule

The two look like opposites and are not. The ruleset's `deletion` rule has
`conditions.ref_name.include: ["~DEFAULT_BRANCH"]`, so it protects `main` and nothing else. It was
confirmed to work on a temporary branch: with the rule the API answers `422 Cannot delete this
branch`, and without it the same request deletes it. `delete_branch_on_merge` acts on the head branch
of a merged pull request, which is never `main`. Nothing overlaps.

## Checks that were measured and rejected

Each row is the result of a command that was run against the fleet.

| Check | Measurement | Decision |
|---|---|---|
| `typos` | 8 findings, 0 real defects | Rejected. Two findings are deliberate spelling errors in a test that asserts an unknown configuration key is refused. A correction breaks the test |
| `markdownlint` | 0 findings, with MD013 and MD060 off | Rejected for now. The documents are correct already, so the tool guards against a regression and finds no defect. 13 near-identical workflows are a cost that this does not repay. With MD013 on, the tool reports many line lengths and no defect |
| A link checker (`lychee` or equivalent) | 0 broken links. The 13 repositories have 0 relative links | Rejected. There is nothing to check. `lycheeverse/lychee-action` also fails by default when it finds no link |
| `gitleaks` in CI | Push protection is on in 17 of 17 repositories | Rejected in CI. Push protection covers a provider token. It does not cover a password in a connection string, and the pre-commit hook covers that |
| CodeQL | `code-scanning/default-setup` answers `languages: []` for each repository that has no code | Rejected. For `ratatoskr-contracts` the expected number of findings is zero, and the analysis gates nothing |
| `taplo` | Not run | Rejected. It finds no defect that `cargo fetch --locked` does not find, and it reformats the aligned dependency tables |
| `actionlint` | 0 findings across the 20 workflow files, with `shellcheck` 0.11.0 present | Rejected. GitHub refuses invalid workflow YAML before a job starts, and `zizmor` now covers the security surface from a gate rather than from a hand-run command. It is still worth running by hand when a `run:` block is edited: it is the tool that reads those blocks with `shellcheck` |
| Backticked paths that look like files | 156 findings, 0 real defects | Rejected. The documents name planned files, files in other repositories, a deliberately deleted file, and a template placeholder |
| `> Status:` vocabulary conformance | 16 findings, 0 real defects | Rejected. All sixteen are the `ARCHITECTURE.md` prose header, which is the same deliberate style in every repository |
| `clippy::cognitive_complexity` | platform's worst function scores 66 against a default of 25; contracts' worst scores 14 | Rejected. It is a `restriction` lint, so the `clippy.toml` key alone is dead config unless the lint is also named in `[workspace.lints.clippy]`. Clippy's own documentation disowns the metric and points at `too_many_lines` and `excessive_nesting`, both of which are adopted and both of which already flag the same two functions. The 66 is almost entirely early-return arms, a shape the workspace forces by denying `unwrap`, `expect` and `panic!` |
| Tightening `clippy::type_complexity` below its default of 250 | Worst score 192, `crates/http/tests/public_faults.rs:106` | Rejected. Already enforced at the default and green in both repositories. Every site under a tighter value is test scaffolding, one function pointer in a test helper costs 50 points per nesting level, and platform and contracts would need different numbers |
| `clippy::large_stack_frames`, and the byte-size threshold family — `enum-variant-size`, `array-size`, `pass-by-value-size-limit`, `trivial-copy-size-limit`, `future-size`, `large-error`, `vec-box-size` | All green at their defaults in both repositories | Rejected. They bound data layout rather than code size. `large_stack_frames` is `nursery`, so a toolchain bump could redden `main` with no code change, and it sums MIR locals — a documented over-count. Three of the byte-size keys have inverted polarity, where a smaller number is the more permissive setting |
| ESLint `max-statements`, `max-depth`, `max-nested-callbacks`, `max-classes-per-file` | Worst hand-written values 9, 1, 2 and 1 | Rejected. Each measures something `max-lines-per-function` or `complexity` already gates, or cannot fire on anything a React tree plausibly writes — the idiom is early return plus JSX conditionals, so nesting stays at 1. `max-statements` also punishes hook-heavy components structurally, since every `useState` and `useEffect` is one statement. Three gates on one defect is how a limits configuration becomes something people disable |
| `@typescript-eslint/max-params`, and `eslint-plugin-sonarjs` for cognitive complexity | Not adopted | Rejected. The core `max-params` accepts `countThis` natively on the installed ESLint, so the TypeScript variant would mean disabling the base rule and maintaining two configurations for behaviour the base rule already has. `sonarjs` would be a new dependency to gate a tree whose worst cyclomatic complexity is 7 |
| A baseline file with a NEW/GREW comparator, as the retired Python repository used for files over 1500 LOC and classes over 1000 | The baseline would hold zero entries: every number adopted here is at or above today's worst case | Rejected. That machinery exists to grandfather violations that already exist, and there are none. It is also a second source of truth that goes stale in silence, and it can re-grandfather a function that was refactored and then regressed. `#[expect]` and `eslint-disable ... -- reason` grandfather per site, beside the code the reviewer is reading, and expire by themselves |
| A `.rs` file-length limit at the conventional 1000 | Worst file 817 lines, so 183 lines of headroom | Rejected at 1000 and adopted at 850. A limit that cannot fire on plausible near-future code is decoration |
| A coverage floor per repository, at the value the tree measures today | Not run. `ratatoskr-web` has `@vitest/coverage-v8` installed and could answer in one command. `ratatoskr-platform` cannot answer without a PostgreSQL and a NATS server, so the fleet cannot be measured in one pass today | Deferred rather than rejected. The shape is the one `shadscan --fail-under 69` already uses in `ratatoskr-web`: a floor at today's value fails on a regression and does not fail on work nobody has done yet. What stops it is that a floor is worth adopting only when all three trees can be measured the same way, and two of the three have no number |
| `cargo-mutants` | Not run | Rejected for now, and it is the most interesting rejection here. It is the only tool that measures whether a test would CATCH a defect, which is precisely what a coverage percentage does not answer and precisely what a test-first rule is for. It is also minutes per mutant, against a workspace whose suite already needs two services. Revisit it on a schedule, the way `advisories.yml` runs, rather than in the gate |
| A check that the failing test was written before the implementation | Impossible by construction | Rejected. A gate reads the tree, not the hour each line was typed. `git log` cannot answer it either: a test and its implementation land in one commit as often as not, and splitting them in two to satisfy a check is the shape of a rule people work around. What is checkable is the artifact, and two things check it — `openspec validate --archived`, and the step in `fleet.yml` that fails on a manifest whose `ci.yml` never runs a test |
| Vendoring all 44 Rust skills instead of 18 | 119 files and 1.67 MB per repository, against 67 files and 642 KiB for the eighteen | Rejected. Twenty-six of them have no site in this fleet and the reason for each is listed in [The Rust skill catalogue](#the-rust-skill-catalogue). A skill that cannot fire is a file to re-read on every update |
| Installing the Rust skills per machine, with `npx skills add --global`, instead of vendoring them | Not adopted | Rejected. It is genuinely one copy, which is what a central catalogue sounds like, but it is invisible to a fresh clone, to a second machine and to review, and nothing can check it. The fleet already carries two per-machine steps and records both as limits; a third that governs how code gets written is worse than 642 KiB of tracked text |
| A git submodule of `po4yka/rust-skills` instead of vendored copies | Not adopted | Rejected. One pinned SHA rather than 67 paths is a real advantage, and an uninitialised submodule is a silently empty directory: the agent reports nothing and simply has no skills. That is the failure mode this project refuses in a gate, and it is no better in a catalogue |
| A step in `fleet.yml` asserting that the Rust skills are present | Not added | Rejected. `fleet.yml` is byte-identical in all 17 and four of them legitimately have no Rust, so the step has no condition it can read. `Cargo.toml` is the only Rust signal a repository can see about itself and eleven of the thirteen do not have one yet. The drift check is where it belongs, because it is the one job that sees more than one repository at a time |
| Asserting that `openspec/config.yaml` is one blob across the fleet | 17 of 17 differ, by design | Rejected. Its `context:` block names one repository's role, its stack and where its tests live. The `rules` and `operations` beneath it ARE identical, and a tree read compares whole blobs and cannot compare a fragment of one. Presence is asserted instead |

## A cancelled run is a missing verdict

Every workflow in the fleet set `cancel-in-progress: true`. On a pull request that is right: only the
newest push needs an answer, and cancelling the superseded run is what keeps the queue short. On
`main` it is the opposite. A cancelled run leaves that commit with no verdict at all, and `main` is
the branch whose history is meant to record whether each commit passed. Two pushes a minute apart
erased the first result permanently, because the run log was the only place it existed.

All three of `fleet.yml`, `zizmor.yml` and `ci.yml` now read:

```yaml
cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

`advisories.yml`, `drift.yml` and `release.yml` set `false` outright. A scheduled run has nothing
newer to yield to, and a cancelled release is a half-published one.

This mattered less while the checks were advisory. With `required_status_checks` in the ruleset, a
cancelled run is an absent check rather than a missing note.

### A run that was never created at all

Cancellation is not the only way a commit on `main` ends up with no verdict, and the fleet has now
seen the other way. Sixteen pull requests were merged within a few minutes of each other on
2026-08-20. Fifteen produced the expected three or five `push` runs on `main`. `ratatoskr-extractor`
produced none: its three workflows are `active`, its own pull-request runs had passed minutes
earlier, and GitHub simply created no run for the merge commit.

The content was not left unaudited, and the distinction is worth keeping. The merge commit's tree is
`2cc6f37b923320bd6cc9fc9666f183f6499bc8a4`, and that is the same tree the green pull-request runs
audited — identical object name, so identical content. What is missing is the record against the
commit on `main`, not the verdict on what it contains.

There is no clean way to obtain the missing run. `fleet.yml`, `zizmor.yml` and `openspec.yml` carry
`push` and `pull_request` and no `workflow_dispatch`, so nothing can re-ask the question without a new
commit. The next commit to that repository answers it. Adding `workflow_dispatch` to the three shared
workflows would make this recoverable, and it is not done here: it is a change to three files in
seventeen repositories, and it should be decided on its own rather than folded into the change that
happened to find the problem.

## Git hooks

Each repository has the same `.githooks/pre-commit`. The file is 25 lines of POSIX shell under its
comments, and it needs no program to be installed. It makes three checks:

1. A staged line must not embed a credential in a URL.
2. A staged line must not contain a private key header.
3. `cargo fmt --all -- --check` must pass, if the repository has a `Cargo.toml` **and the commit
   carries a `.rs` file**.

The third condition lets one file be correct in a Rust repository and in a repository of documents.
The hook does not know which repository it is in.

The private-key check requires the base64 body that a real key brings, not only the PEM header. The
header alone appears here on purpose: `ratatoskr-contracts` has
`tools/contractsc/tests/secrets.rs`, which asserts that its own secret scanner fires on
`-----BEGIN RSA PRIVATE KEY-----`. The first version of the hook refused any staged line holding that
header, so editing that test needed `--no-verify`. The body test is also unanchored, because a key
indented inside YAML or inlined with `\n` escapes is still a key, and the base64 run must contain a
character no hexadecimal digit can be — without that last rule the fleet workflow matched itself,
through the PEM header in its own pattern and its own forty-character action SHA.

The formatting check needed the same shape of correction, and for the same reason. It first ran the
whole-tree `cargo fmt` check whenever a `Cargo.toml` was present, whatever the commit contained, and it
refused a CI-only commit in `ratatoskr-platform` because unrelated work in progress sat unformatted in
the working tree. rustfmt is whole-file, so the whole-tree check is right when Rust is being committed;
running it when none is being committed was not. A `.rs` file that is unformatted in the working tree
and absent from the commit has not entered history, and the check fires on the commit that puts it
there.

Both corrections are the same lesson. A hook that refuses a commit it has no business refusing is a
hook that gets bypassed, and a bypassed hook protects nothing.

The credential check excludes a loopback host and the names that RFC 2606 reserves. Both types
occur correctly in these repositories: `postgres://platform:platform@127.0.0.1:5432/platform` is the
local database, and `https://otel:LEAKME@collector.example:4317` is a test that asserts a credential
in an OTLP endpoint is refused. The pattern was measured before it was accepted. It gives zero
findings across the 17 repositories today, and it still finds a credential on a real host.

### The known limit of the hooks

**A committed hook directory does nothing on its own.** Each clone must run this command:

```bash
git config core.hooksPath .githooks
```

A clone that did not run the command has no hook. This includes a second machine, a CI checkout, and
a clone into a different parent directory. Git treats this as a security boundary, and a repository
cannot opt a clone in.

`git commit --no-verify` also skips the hook, and an agent can pass that option.

The hooks are therefore a convenience that finds a mistake early. The gate is CI and the branch
ruleset.

The hook makes no Clippy check. A workspace-wide Clippy run competes for the same target directory
as `rust-analyzer`, and it can block for an unbounded time. CI has the tree to itself.

The hook makes no commit-message check. The subjects in the history of these repositories already
agree with Conventional Commits. A regular expression refuses `Initial commit` and a merge subject
that Git creates locally. Both subjects are in the real history.

## Platform state

The controls in the table at the top of this document are repository settings. They are not files,
so a checkout does not show them, and a settings change removes them without a commit.

Write these settings with the GitHub API, in a loop over the 17 repositories:

```bash
gh api -X PUT   "repos/po4yka/<repo>/vulnerability-alerts"
gh api -X POST  "repos/po4yka/<repo>/rulesets" --input ruleset.json
gh api -X PUT   "repos/po4yka/<repo>/actions/permissions" \
  -F enabled=true -f allowed_actions=all -F sha_pinning_required=true
gh api -X PATCH "repos/po4yka/<repo>" -F delete_branch_on_merge=true
```

Read each setting back after you write it. A `PATCH` that sets
`secret_scanning_non_provider_patterns` answers 200 and leaves the setting disabled, so a write that
succeeds is not evidence that the setting changed.

`sha_pinning_required` has two limits. It refuses an unpinned action from GitHub itself, so each
`uses:` line must be in SHA form before you turn the setting on. It does not apply to a reusable
workflow reference.

## Defects that these controls found

### A flaky test in `ratatoskr-platform`

`each_role_boots_on_its_documented_configuration_and_reports_ready` fails about one time in three on
a developer machine. The test failed on an unmodified `main`, on the same machine and against the
same services, so the defect is in the test.

The test has two failure modes. In the first mode, `/health/ready` does not answer 200 before the
poll expires. In the second mode, the process does not exit 0 after SIGTERM. Each assertion has a
fixed time window.

CI has not reported this failure yet. The test is timing-sensitive, so a green run is not evidence
that the test is correct.

### A self-hosted runner on a public repository — closed

`docs/DEPLOYMENT_TARGET.md` stated that the `po4yka-RIPDPI` self-hosted runner "is removed as part of
the cleanup". It was not: `raspi-ripdpi-evidence` was registered and online on a repository that is
public and not archived. The runner is now removed, and `total_count` is 0 on all seventeen
repositories of the account.

The exposure was narrower than it first looked, and the measurement is worth keeping. One workflow of
twenty-four referenced the self-hosted label, and it is `workflow_dispatch` only, which a fork cannot
trigger. No job had ever run on the runner, and no fork had ever run a workflow there. The real path
was a fork proposing a NEW workflow on `pull_request`, which GitHub reads from the pull request head —
gated by an approval policy of `first_time_contributors`, which stops a first-time contributor and not
a returning one. With four forks and sixteen open issues, that gate opens on the day a first outside
contribution is merged.

The host-side service was removed as well, reported on 2026-08-19 and not verifiable through the API;
`DEPLOYMENT_TARGET.md` records that distinction and how to re-check it on the machine.

One note for whoever reintroduces a runner: on a public repository it needs
`approval_policy=all_external_contributors` in the same change, not afterwards.

### The gate matched itself, and the local test could not see it

The first rollout of `fleet.yml` failed in all sixteen repositories, each on the credential step, each
with "`.github/workflows/fleet.yml` contains a private key". The file carries the PEM header inside its
own pattern and a forty-character action SHA that reads as a base64 body, so header-plus-body flagged
the scanner's own source.

The reason the local run missed it is the more useful half. Every step had been run against all sixteen
repositories and all sixteen passed — before the commit, so the tree under test did not contain the file
under test. **A gate that scans the repository must be tested against a tree that already contains the
gate.**

This is the fourth time a scanner in this project has been defeated by the project's own content:
`RATATOSKR__ADMN__BIND` is a deliberate misspelling asserting that an unknown configuration key is
refused, `otel:LEAKME@collector.example` is a credential asserting that an endpoint is refused,
`secrets.rs` holds a PEM header asserting that a scanner fires, and now a workflow's own pin. A
repository set that tests scanners will always hold specimens of what scanners seek. Any fleet-wide
content check must be built for that, and must be measured before it is trusted.

### The first `zizmor` run found five things, in the two repositories that have code

The workflow gate was measured across all 16 repositories before it was turned on. Fourteen were
clean. The two with a `ci.yml` were not, and each finding was real and is fixed:

| Repository | Audit | What it was |
|---|---|---|
| `ratatoskr-platform` | `unpinned-images` | The PostgreSQL service container was `postgres:17`. A service container runs on the runner beside the build and on the same network, so a compromised image reaches the `crates.io` downloads that produce the release binary. It is pinned by digest now |
| `ratatoskr-platform` | `template-injection`, twice | `${{ github.sha }}` spliced into a `run:` block. `$GITHUB_SHA` is the runner's own variable and holds the same value, so the expression never had to be in the script at all |
| `ratatoskr-platform` and `ratatoskr-contracts` | `dependabot-cooldown` | Dependabot would propose an action release on the day it was published, with a correct-looking version comment |

None of the five was being exploited, and that is the point of listing them. Each is a rule this fleet
already states elsewhere — pin what you execute; do not splice an expression into a shell — that had
not been applied to the file in question, and nothing in the fleet was reading these files closely
enough to say so.

### Disposable test databases remain

`DEVELOPMENT.md` in `ratatoskr-platform` says that the integration suite creates a database for each
test and drops it afterwards. It also says that a test which panics leaves its database, so that a
person can examine the failure.

A developer machine had 64 databases with the name `platform_test_*`. Examine them before you drop
them, because one database can hold a failure that somebody kept.

CI does not have this problem. Each run gets a new service container.

## Deployment

There is no continuous deployment, and this section records why rather than leaving the absence to be
inferred.

`ratatoskr-platform` builds its artifact, and can now publish it. A `Dockerfile` is committed,
`[profile.release]` is in `Cargo.toml`, and `ci.yml` has a second job on `ubuntu-24.04-arm` — a native
arm64 runner, which a public repository gets at no cost — that builds the image, checks that each
binary loads its configuration, and smoke-tests the running artifact through its operator plane.
`.github/workflows/release.yml` is the step that keeps the result. What is still absent is a systemd
unit and any step that reaches the machine.
`ratatoskr-contracts` publishes no package until its milestone 10. `docs/DEPLOYMENT_TARGET.md` fixes
the target as one Raspberry Pi 5, `aarch64-unknown-linux-gnu`, Debian 12, glibc 2.36.

Two things were considered and rejected:

- **A cross-compiled `aarch64-unknown-linux-gnu` build on `ubuntu-latest`.** It does not link: the
  runner image has no `gcc-aarch64-linux-gnu`, and the attempt fails with `ld: unknown options:
  --as-needed -Bstatic`. Installing a cross toolchain would make it link, but a cross-compile is not the
  ABI proof `DEPLOYMENT_TARGET.md` asks for. It would catch a target-specific compilation error and it
  would not catch a page-size or loader problem, which is what that document says must be re-verified —
  a `debian:12-slim linux/arm64` container reports a 4 KiB page size against the target's 16 KiB. The
  native arm64 job replaced it, and it answers the same question in the place the question arises.
- **A deploy job.** From a public repository it needs either a self-hosted runner on the target or a
  long-lived credential to it. See the runner finding above for why neither is acceptable without a
  decision first.

### The release, and the attestation

`ci.yml` builds this image on every push and then discards it. So without this file the only way to
deploy is to build again on the target, which means the thing that runs in production is compiled by
a machine nobody audited from a tree nobody gated.

`release.yml` triggers on a `v*.*.*` tag and on nothing else automatic. It runs on
`ubuntu-24.04-arm`, so the artifact is the architecture it will be run on rather than a
cross-compile, and it publishes to `ghcr.io/po4yka/ratatoskr-platform` under the version — never
under `latest`. A moving tag is the thing this project refuses everywhere else, and a deployment that
follows one cannot say what it is running.

It then attaches a provenance attestation with `actions/attest-build-provenance`. That is a signed
statement, made with GitHub's OIDC identity rather than with a key stored in this repository, that
this image digest was produced by this workflow from this commit. A person holding the image checks
it with `gh attestation verify oci://... --repo po4yka/ratatoskr-platform` and gets an answer that
does not depend on trusting whoever handed the image over. SHA-pinning every action and
digest-pinning the PostgreSQL service protect that property on the way in; this is the same property
on the way out.

Four things fail the release rather than shipping:

| Check | The failure it catches |
|---|---|
| `git merge-base --is-ancestor` against `main` | A tag on a commit `main` cannot reach, which is a commit no gate ever saw. A tag is a name a person types and it can name anything in the repository |
| The tag version equals the `Cargo.toml` version | Tagging `v0.2.0` with the manifest still on `0.1.0`, which produces an image whose name and whose `platform_build_info` disagree |
| Each of the three binaries loads its configuration, in the image about to be published | The same assertion `ci.yml` makes, made against the artifact itself rather than against one built from the same tree. `ratatoskr-ingest` is expected to REFUSE without an explicit public bind: 78 is its correct answer and 0 would be the defect |
| The published digest is read back from the push | The attestation must name the digest a puller resolves, and those are the same number only if it is taken from the push rather than computed locally |

What has been exercised and what has not, stated plainly. A `workflow_dispatch` run with `publish`
off ran the whole first half on a native arm64 runner: the ancestry check, the version check, the
image build and the smoke test. The publishing half — the `ghcr.io` login, the push, the attestation
and the GitHub release — has NOT been run. It first runs on the first `v*.*.*` tag, and that tag has
not been created. Until then it is code that has been reviewed and linted and not executed, which is
exactly the state this document warns about elsewhere, and the honest thing to do is say so rather
than let the section imply otherwise.

One thing is deliberately left alone. `Dockerfile` names `rust:1.97.0-slim-bookworm` and
`debian:12-slim` by tag, not by digest. `zizmor` does not read a Dockerfile, so nothing reports it,
and the base image of the artifact deserves the same pin the PostgreSQL service got. It is a separate
change and it is not in this one.

## What arrives with the first code in a repository

Add these files in the same pull request as the first `Cargo.toml`, and not before:

- `rustfmt.toml`, `clippy.toml`, `rust-toolchain.toml` and `deny.toml`, copied from
  `ratatoskr-contracts`;
- `.github/workflows/ci.yml`, copied from the repository whose gate is closest;
- `.github/workflows/advisories.yml`, copied UNCHANGED from either repository that has it;
- `.github/dependabot.yml` for the `github-actions` ecosystem, in the form the two Rust
  repositories already use — it differs from the one every other repository has.

That `ci.yml` must run the tests. A step in `fleet.yml` fails a repository that has a manifest and a
`ci.yml` with no test invocation in it, for the same reason the step beside it fails a `Cargo.toml`
with no `clippy.toml`: every `openspec/config.yaml` in this fleet tells an agent to write the
failing test first, and a rule with nothing behind it in CI is a rule that decays. The step reads
for an invocation and not for a passing or a useful test — the pull request is where those are read.

Nothing about OpenSpec arrives with the first code. `openspec/`, `openspec/config.yaml` and
`.github/workflows/openspec.yml` are already in all seventeen repositories, because planning is what
a repository with no code has most of. What the first code commit adds to `openspec/config.yaml` is
one line in its `context:` naming where the tests now live.

`advisories.yml` is not optional and is not a matter of taste: the drift check asserts that every
repository holding a `Cargo.toml` has it and that the file is identical in all of them, so a first
code commit without it turns the workspace drift check red rather than being quietly incomplete.

Copy each file. Do not use a symbolic link, and do not use a path reference. Invariant 5 says that
each child repository builds independently of the workspace, and that makes an identical copy the
correct answer.

Do not copy `clippy.toml` without a review of its content. The file in `ratatoskr-contracts` refuses
`std::collections::HashMap` and `std::time::SystemTime`. Both rules are correct for a contract crate.
In a connector repository, each rule is a guess until somebody decides that the service speaks a wire
timestamp.

Add the repository's new check names to the `required_status_checks` rule in its ruleset, and only
after a run has published them. A required check that no workflow produces gives a ruleset you must
bypass in order to work at all. For a Rust repository the names are `gate` from `ci.yml`, alongside
the `invariants` and `audit` that every repository already requires. Do NOT add `advisories`: it has
no `push` or `pull_request` trigger, so requiring it would block every merge and never be satisfied.
