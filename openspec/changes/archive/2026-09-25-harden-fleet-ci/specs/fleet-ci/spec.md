## Purpose

Defines the CI behaviour every Ratatoskr repository shares and that no single repository can verify alone: where the shared checks are defined, which checks gate a merge, how drift between repositories is detected, and the invariants every repository's tests and dependency manifests satisfy.

## ADDED Requirements

### Requirement: Shared checks are defined once in the workspace

The `fleet`, `zizmor`, `openspec`, `advisories` and Dependabot auto-merge checks SHALL be defined only in `ratatoskr-workspace/.github/workflows/reusable-{fleet,zizmor,openspec,advisories,dependabot-automerge}.yml`. Every repository SHALL carry the wrappers `fleet.yml`, `zizmor.yml`, `openspec.yml` and `dependabot-automerge.yml`, and every repository with Rust SHALL carry `advisories.yml`. Each wrapper SHALL hold only triggers, concurrency and permissions, and SHALL call its reusable workflow at a pinned 40-hex commit of `ratatoskr-workspace`. The workspace's advisories wrapper SHALL pass `manifest-dir: harness`.

#### Scenario: A wrapper calls the workspace at a commit
- **WHEN** a repository's `fleet.yml`, `zizmor.yml`, `openspec.yml`, `dependabot-automerge.yml` or `advisories.yml` is read
- **THEN** its only job calls `po4yka/ratatoskr-workspace/.github/workflows/reusable-<name>.yml@<sha>` where `<sha>` is 40 hexadecimal characters

#### Scenario: A check is changed once
- **WHEN** a step of a shared check changes
- **THEN** the change is made in the workspace's reusable workflow, and each repository receives it by raising its wrapper's pinned SHA

### Requirement: Required status checks cover every job a merge depends on

The `main` ruleset of every repository SHALL require `fleet / invariants`, `zizmor / audit` and `openspec / specs`, and SHALL require every job of that repository's own `ci.yml` by the name the job publishes. It SHALL NOT require a check that no `push` or `pull_request` run produces.

#### Scenario: A CI job fails on a pull request
- **WHEN** any job of a repository's `ci.yml` fails on a pull request that has auto-merge enabled
- **THEN** GitHub does not merge the pull request

#### Scenario: The shared check names
- **WHEN** a repository's ruleset is read back through the API
- **THEN** its required checks include `fleet / invariants`, `zizmor / audit` and `openspec / specs`, and do not include `advisories` or `drift`

### Requirement: Drift between repositories is detected

The workspace `drift.yml` SHALL fail when `fleet.yml`, `zizmor.yml`, `openspec.yml` or `dependabot-automerge.yml` differs by blob between any two repositories; when any reusable workflow pinned by the wrappers is, at the pinned commit, a different blob from the same file on workspace `main`, or fewer than five reusable workflows are pinned; and when any discovered `ratatoskr-*` repository other than `ratatoskr-workspace` is not declared in `workspace.toml`.

#### Scenario: A check fixed in the workspace but not rolled out
- **WHEN** `reusable-fleet.yml` on workspace `main` differs from the blob at the SHA the wrappers pin
- **THEN** the drift job fails and names the file and the pinned SHA

#### Scenario: A repository outside the manifest
- **WHEN** a `ratatoskr-*` repository exists on GitHub and no `workspace.toml` entry's remote names it
- **THEN** the drift job fails and names the repository

#### Scenario: One automerge wrapper differs
- **WHEN** `dependabot-automerge.yml` in one repository has a different blob from the rest
- **THEN** the drift job fails and lists the repositories holding each version

### Requirement: Tests never read the wall clock

The fleet check SHALL fail when a tracked test file, found by path, contains a wall-clock read (`Clock.System`, `SystemTime::now`, `Utc::now`, `Local::now`, `OffsetDateTime::now_utc`, `OffsetDateTime::now_local`, `Timestamp::now`, `Zoned::now`, `Date.now(`, `new Date()`, `System.currentTimeMillis`, the `java.time` `.now(` family, or Swift `Date()`) on a line without a `wall-clock:` comment. Rust `Instant::now()` SHALL be allowed. The check SHALL fail, not pass, when its search itself errors.

#### Scenario: A test reads the real date
- **WHEN** a Kotlin test file contains `Clock.System.now()` with no `wall-clock:` comment on that line
- **THEN** the `fleet / invariants` check fails and prints the file and line

#### Scenario: Real time is stated as needed
- **WHEN** the same read carries a same-line `// wall-clock: deadline for the child process` comment
- **THEN** the check passes

#### Scenario: Monotonic time
- **WHEN** a Rust test calls `Instant::now()`
- **THEN** the check passes

### Requirement: `main` is re-verified on a schedule

Every repository's `ci.yml` SHALL run on a weekly `schedule` trigger on Monday, at a minute that is not on the hour and differs between repositories, in addition to `push` and `pull_request`.

#### Scenario: Weekly run
- **WHEN** a repository's `ci.yml` is read
- **THEN** its triggers include a `schedule` whose cron runs on day-of-week 1 at a non-zero minute distinct from every other repository's

### Requirement: An advisory cannot hide a gate failure

In every repository with Rust, `cargo deny` SHALL run in a job with id `deny`, separate from the job that runs formatting, Clippy and tests, and both jobs SHALL be required.

#### Scenario: A new advisory and a failing test
- **WHEN** a pull request breaks a test while a new RustSec advisory affects the lockfile
- **THEN** the `deny` job and the test job both report failure on the same run

### Requirement: The lockfile pins dependency versions

A Cargo manifest SHALL NOT use an exact `=x.y.z` requirement for a registry dependency unless a comment on the same or the preceding line states why exactness is required. Every command in CI SHALL run with `--locked` against the committed `Cargo.lock`.

#### Scenario: An exact requirement without a reason
- **WHEN** a tracked `Cargo.toml` contains `version = "=0.23.43"` with no comment on that or the preceding line
- **THEN** the manifest violates this requirement

### Requirement: Dependabot security updates are on and version updates stay on actions

Dependabot security updates SHALL be enabled in every repository's settings. `.github/dependabot.yml` SHALL name only the `github-actions` ecosystem, and both of its forms SHALL state that security updates are enabled in settings.

#### Scenario: Settings read back
- **WHEN** `GET /repos/po4yka/<repo>/automated-security-fixes` is called for any repository
- **THEN** it reports `enabled: true`

### Requirement: Dependabot pull requests merge themselves when green

`allow_auto_merge` SHALL be enabled in every repository. The auto-merge workflow SHALL enable squash auto-merge only on a pull request authored by `dependabot[bot]` whose head repository is the same repository, and SHALL do nothing on any other pull request.

#### Scenario: A Dependabot pull request
- **WHEN** `dependabot[bot]` opens a pull request from a branch of the same repository
- **THEN** auto-merge with the squash method is enabled on it, and GitHub merges it once every required check passes

#### Scenario: A pull request from anyone else
- **WHEN** a person opens a pull request, whoever later triggers a run on it
- **THEN** the auto-merge job is skipped and auto-merge is not enabled

### Requirement: CI checks fail closed

A CI check SHALL fail, and SHALL NOT pass, when the tool it relies on is absent or errors: a tool SHALL NOT be run as the condition of an `if` when its absence would read as false, an assertion SHALL NOT be wrapped in `|| true`, and a `grep` exit status above 1 SHALL be treated as an error.

#### Scenario: The search tool errors
- **WHEN** a check's `grep` exits with status 2
- **THEN** the check fails with an error rather than reporting no match
