# Quality gates

> Status: Implemented  
> Owner: `ratatoskr-workspace`  
> Last reviewed: 2026-08-19  
> Related: `DEVELOPMENT.md`, `TESTING.md`, `THREAT_MODEL.md`, `docs/ARCHITECTURE.md` section 11

## Scope

This document records the static analysis, the linters, the continuous integration and the Git hooks
that the 16 Ratatoskr repositories have today. It also records the checks that were measured and
then rejected, and it gives the reason for each rejection.

Workspace CI does not replace repository CI. Each repository owns its own gate. This document
describes the fleet, because the controls are identical in each repository and a reader must be able
to find the policy in one place.

Every number in this document comes from a command that was run. If you change a control, run the
command again and correct the number.

## What each repository has

All 16 repositories are public. The default branch of each repository is `main`.

| Control | Repositories | Notes |
|---|---|---|
| `.gitattributes` | 16 of 16 | One line: `* text=auto eol=lf` |
| `.editorconfig` | 16 of 16 | Editor defaults. No check enforces the file |
| `.githooks/pre-commit` | 16 of 16 | Identical file. See [Git hooks](#git-hooks) |
| Branch ruleset on `main` | 16 of 16 | The `deletion` rule only |
| Dependabot alerts | 16 of 16 | Alerts only. No version-update pull requests |
| Secret scanning and push protection | 16 of 16 | GitHub gives these to a public repository |
| `sha_pinning_required` for Actions | 16 of 16 | A workflow must pin each action to a commit SHA |
| The fleet gate, `.github/workflows/fleet.yml` | 16 of 16 | Identical file. See [The fleet gate](#the-fleet-gate) |
| A repository gate, `.github/workflows/ci.yml` | 2 of 16 | `ratatoskr-contracts` and `ratatoskr-platform` |

The ruleset does not include the `non_fast_forward` rule. The account has one administrator, and
agents push with the same token. A bypass for that administrator makes the rule apply to nobody, and
a rule that applies to nobody is a control that protects nothing.

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

`.github/dependabot.yml` in each Rust repository watches the `github-actions` ecosystem. The
configuration groups the updates into one pull request each month.

The `cargo` ecosystem is deliberately absent. Each repository commits its `Cargo.lock` and runs each
command with `--locked`. A dependency bump is therefore a deliberate act. `cargo deny check` in the
gate reports an advisory on the day it is published.

An action pin is the opposite case. It rots, and it rots silently. A reader cannot find a pin whose
`# vX.Y.Z` comment no longer agrees with its SHA. Dependabot corrects the SHA and the comment
together.

## The fleet gate

Each repository runs `.github/workflows/fleet.yml`. The file is identical in all sixteen. It installs
nothing and uses one action, so it has no supply-chain surface beyond the checkout and it cannot fail
for a reason that has nothing to do with the tree.

Six steps, and each one fails only when something is really wrong:

| Step | The failure it catches |
|---|---|
| The files every repository in the fleet must have | A required document is no longer tracked. `SECURITY.md` and `AGENTS.md` would go unnoticed longest, because nothing builds from them |
| The pre-commit hook is present and executable | A hook that lost its executable bit is silently inert, and git records the mode |
| No CRLF in a tracked text file | A blob written past the `.gitattributes` filter, which is what a commit through the web editor or the contents API does |
| No credential in a tracked file | A password in a URL, or a private key, anywhere in the tree |
| Every workflow pins each third-party action to a commit SHA | A moving ref in a workflow that `push` and `pull_request` never trigger, or a nested `uses:` in a composite action |
| Code cannot land without a gate | A manifest arrives and no `ci.yml` arrives with it |

The last step deserves its name. It is not a second gate: it asserts that a gate exists. An earlier
draft tried to BE the gate, by running the Rust commands itself. That draft knew only `Cargo.toml`, so
it was permanently green in the three repositories whose first code is Kotlin, TypeScript and Swift —
green on exactly the commit it existed to catch. The version that shipped fails closed for every
language in the fleet.

### Why the credential and key checks are not redundant

GitHub secret scanning is enabled on all sixteen repositories, and it has a pattern for a PostgreSQL
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

## Checks that were measured and rejected

Each row is the result of a command that was run against the 16 repositories.

| Check | Measurement | Decision |
|---|---|---|
| `typos` | 8 findings, 0 real defects | Rejected. Two findings are deliberate spelling errors in a test that asserts an unknown configuration key is refused. A correction breaks the test |
| `markdownlint` | 0 findings, with MD013 and MD060 off | Rejected for now. The documents are correct already, so the tool guards against a regression and finds no defect. 13 near-identical workflows are a cost that this does not repay. With MD013 on, the tool reports many line lengths and no defect |
| A link checker (`lychee` or equivalent) | 0 broken links. The 13 repositories have 0 relative links | Rejected. There is nothing to check. `lycheeverse/lychee-action` also fails by default when it finds no link |
| `gitleaks` in CI | Push protection is on in 16 of 16 repositories | Rejected in CI. Push protection covers a provider token. It does not cover a password in a connection string, and the pre-commit hook covers that |
| CodeQL | `code-scanning/default-setup` answers `languages: []` for each repository that has no code | Rejected. For `ratatoskr-contracts` the expected number of findings is zero, and the analysis gates nothing |
| `taplo` | Not run | Rejected. It finds no defect that `cargo fetch --locked` does not find, and it reformats the aligned dependency tables |
| `actionlint` | Not in a gate | Rejected. GitHub refuses invalid workflow YAML before a job starts, and `zizmor` covers the security surface |
| Backticked paths that look like files | 156 findings, 0 real defects | Rejected. The documents name planned files, files in other repositories, a deliberately deleted file, and a template placeholder |
| `> Status:` vocabulary conformance | 16 findings, 0 real defects | Rejected. All sixteen are the `ARCHITECTURE.md` prose header, which is the same deliberate style in every repository |

## Git hooks

Each repository has the same `.githooks/pre-commit`. The file is 12 lines of POSIX shell, and it
needs no program to be installed. It makes three checks:

1. A staged line must not embed a credential in a URL.
2. A staged line must not contain a private key header.
3. `cargo fmt --all -- --check` must pass, if the repository has a `Cargo.toml`.

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

The credential check excludes a loopback host and the names that RFC 2606 reserves. Both types
occur correctly in these repositories: `postgres://platform:platform@127.0.0.1:5432/platform` is the
local database, and `https://otel:LEAKME@collector.example:4317` is a test that asserts a credential
in an OTLP endpoint is refused. The pattern was measured before it was accepted. It gives zero
findings across the 16 repositories today, and it still finds a credential on a real host.

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

Write these settings with the GitHub API, in a loop over the 16 repositories:

```bash
gh api -X PUT   "repos/po4yka/<repo>/vulnerability-alerts"
gh api -X POST  "repos/po4yka/<repo>/rulesets" --input ruleset.json
gh api -X PUT   "repos/po4yka/<repo>/actions/permissions" \
  -F enabled=true -f allowed_actions=all -F sha_pinning_required=true
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

### A self-hosted runner on a public repository

`docs/DEPLOYMENT_TARGET.md` states that the `po4yka-RIPDPI` self-hosted runner "is removed as part of
the cleanup". That statement was false when this document was written. `po4yka/RIPDPI` is public, is
not archived, and has one runner registered: `raspi-ripdpi-evidence`, online, with the labels
`self-hosted`, `Linux`, `ARM64`, `ripdpi-network-evidence` and `physical-android`.

A public repository accepts a pull request from any fork, and for a `pull_request` event GitHub reads
the workflow definitions from the pull request head. GitHub's own guidance is to use a self-hosted
runner with a private repository only, for that reason. The 16 Ratatoskr repositories have no runner —
that was verified for each one — so the exposure is in `RIPDPI` alone. It is recorded here because
`DEPLOYMENT_TARGET.md` names the same class of host as the one that will hold `identity.sessions`.

This needs a decision rather than a check: remove the runner, make the repository private, or require
approval for every outside contributor. `DEPLOYMENT_TARGET.md` now states what is registered instead of
asserting a control that does not exist.

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

Nothing in the sixteen repositories is deployable yet. `ratatoskr-platform` has no committed
`Dockerfile`, no systemd unit and no release profile; `ratatoskr-contracts` publishes no package until
its milestone 10. `docs/DEPLOYMENT_TARGET.md` fixes the target as one Raspberry Pi 5,
`aarch64-unknown-linux-gnu`, Debian 12, glibc 2.36.

Two things were considered and rejected for now:

- **An `aarch64-unknown-linux-gnu` build in CI.** It does not link on `ubuntu-latest`: the runner image
  has no `gcc-aarch64-linux-gnu`, and the attempt fails with `ld: unknown options: --as-needed
  -Bstatic`. Installing a cross toolchain would make it link, but a cross-compile is not the ABI proof
  `DEPLOYMENT_TARGET.md` asks for. It would catch a target-specific compilation error and it would not
  catch a page-size or loader problem, which is what that document says must be re-verified — a
  `debian:12-slim linux/arm64` container reports a 4 KiB page size against the target's 16 KiB.
- **A deploy job.** From a public repository it needs either a self-hosted runner on the target or a
  long-lived credential to it. See the runner finding above for why neither is acceptable without a
  decision first.

What becomes correct as soon as a `Dockerfile` is committed: build the image for `linux/arm64` in CI and
publish it as a build artifact. That catches the glibc and target problems in the place they occur, adds
no secret, and leaves the copy to the machine a step the maintainer runs.

## What arrives with the first code in a repository

Add these files in the same pull request as the first `Cargo.toml`, and not before:

- `rustfmt.toml`, `clippy.toml`, `rust-toolchain.toml` and `deny.toml`, copied from
  `ratatoskr-contracts`;
- `.github/workflows/ci.yml`, copied from the repository whose gate is closest;
- `.github/dependabot.yml` for the `github-actions` ecosystem.

Copy each file. Do not use a symbolic link, and do not use a path reference. Invariant 5 says that
each child repository builds independently of the workspace, and that makes an identical copy the
correct answer.

Do not copy `clippy.toml` without a review of its content. The file in `ratatoskr-contracts` refuses
`std::collections::HashMap` and `std::time::SystemTime`. Both rules are correct for a contract crate.
In a connector repository, each rule is a guess until somebody decides that the service speaks a wire
timestamp.

Add a `required_status_checks` rule to the repository ruleset only after a run publishes the check
name. A required check that no workflow produces gives a ruleset that you must bypass to work.
