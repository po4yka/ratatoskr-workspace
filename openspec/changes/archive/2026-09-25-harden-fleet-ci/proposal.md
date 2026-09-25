## Why

In September 2026 the fleet's CI let three failures through that no single repository could see. `ratatoskr-mobile`'s `ResumableUploadCoordinatorTest` combined a fixture expiry of 2026-09-01 with the real clock and went red on that date with no commit, on a `main` whose CI had last run on 2026-08-30. RUSTSEC-2026-0285 in `rustls` turned twelve repositories red as the second step of their gate, hiding whatever else those pull requests broke, and in `ratatoskr-vault` an exact `=0.23.43` manifest requirement blocked the `cargo update -p rustls` that fixed it, while Dependabot security updates were disabled everywhere. Every fix to a shared check also had to be repeated by hand in eighteen copies of the same file, and `ratatoskr-channel-digests` sat outside `workspace.toml` for a month with every gate green.

## What Changes

- The shared checks (`fleet`, `zizmor`, `openspec`, `advisories` and the Dependabot auto-merge) are defined once, as reusable workflows in `ratatoskr-workspace/.github/workflows/reusable-*.yml`. Every repository carries thin wrappers that hold the triggers, concurrency and permissions and call the reusable file at a pinned 40-hex workspace commit. This replaces the self-contained, byte-identical `fleet.yml` design by the owner's explicit choice: a repository's shared checks now depend on the workspace repository being reachable on GitHub at run time.
- The required status checks become `fleet / invariants`, `zizmor / audit` and `openspec / specs`, and each repository's ruleset also requires every job of its own `ci.yml`.
- `drift.yml` additionally asserts that `dependabot-automerge.yml` is one blob across the fleet, that every pinned reusable workflow is the same blob as on workspace `main`, and that every discovered `ratatoskr-*` repository other than the workspace is declared in `workspace.toml`.
- A new fleet invariant fails a tracked test file that reads the wall clock, with a same-line `wall-clock:` escape.
- Every `ci.yml` also runs weekly, on Monday at a staggered minute.
- In repositories with a root `Cargo.toml`, `cargo deny` runs in its own `deny` job.
- Exact `=x.y.z` requirements are removed from Cargo manifests unless a comment states why; `Cargo.lock` with `--locked` pins.
- Dependabot security updates and `allow_auto_merge` are enabled in every repository, and Dependabot's pull requests auto-merge when every required check passes.
- CI checks that could pass silently (a missing tool read as false, `|| true` around an assertion, `grep` exit status 2 read as no match) are fixed.

## Capabilities

### New Capabilities

- `fleet-ci`: the CI behaviour every Ratatoskr repository shares and that one repository alone cannot verify — where the shared checks are defined, which checks gate a merge, how drift between repositories is detected, and the invariants every repository's tests and dependency manifests satisfy.

### Modified Capabilities

None.

## Impact

All 18 repositories, in this order: `ratatoskr-workspace` first, because the wrappers pin a workspace commit that must already contain the reusable workflows; then the seventeen product repositories in any order, since each change is local to that repository's CI, manifests and tests; then the rulesets and repository settings, only after each repository's wrapper has published the new check names; and last a workspace commit that raises no pin but lets `drift.yml` run against the rolled-out fleet.

Outside this change: `ws fleet init`, which bootstraps a new repository with the shared files and is delivered on its own branch; any change to what a product gate tests; `workflow_dispatch` on the shared wrappers.

Rollback is one `git revert` per repository in reverse order, then restoring the previous required check names in each ruleset. Nothing is deployed and no schema changes, so there is no data rollback.
