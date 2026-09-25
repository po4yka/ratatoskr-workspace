## Context

`docs/QUALITY_GATES.md` is the source of truth for which gate exists in which repository and what it measured. Before this change `fleet.yml`, `zizmor.yml` and `openspec.yml` were self-contained and byte-identical in all 18 repositories, with `drift.yml` in this workspace as the only job that compared them. The motivating failures are recorded in `proposal.md`.

## Goals / Non-Goals

**Goals:**

- One definition of each shared check, so a fix lands once.
- A merge, including an automatic one, waits for every CI job of the repository.
- `main` is re-verified without a push.
- A date, an advisory or an exact manifest requirement cannot silently break or block a repository.

**Non-Goals:**

- No change to what any product gate tests beyond the wall-clock fixes.
- No Dependabot version updates for language ecosystems.
- No `workflow_dispatch` on the shared wrappers.

## Decisions

### Reusable workflows at a pinned workspace commit

Each wrapper calls `po4yka/ratatoskr-workspace/.github/workflows/reusable-<name>.yml@<40-hex>`. A full SHA rather than `@main`, because a moving reference would let a workspace commit change every repository's gate with no commit in that repository. Dependabot does not raise these pins, because the workspace commits carry no release tag, so raising them is a scripted one-line change per repository, and `drift.yml` fails until every wrapper pins the revision `main` holds. The comparison is by the called file's blob, so a workspace commit that does not touch a check needs no re-pin.

The alternative kept until now, self-contained copies, made every repository independent of the workspace at CI time. The owner chose the reusable form knowing that a repository's shared checks now need `ratatoskr-workspace` reachable on GitHub. The job still installs nothing, and the product build still does not depend on the workspace.

### Required checks include every CI job

Auto-merge waits only for required checks, so the ruleset lists the three shared checks by their new `<caller> / <called>` names and every job of the repository's `ci.yml`. The auto-merge job itself is not required: it is skipped on any pull request not authored by Dependabot.

### Wall-clock detection by path and pattern

The check finds test files by path and greps for the wall-clock reads of the fleet's languages. It is deliberately a grep: it runs in every repository with no toolchain. Its ceiling, a Rust `#[cfg(test)]` module inside `src/`, is stated in the step. Rust `Instant::now()` is monotonic and does not match.

## Risks / Trade-offs

- [The workspace repository is unreachable or renamed] → every repository's shared checks fail closed; the product build is unaffected.
- [A wrapper pin lags `main`] → `drift.yml` reports it weekly; the lagging repository still runs a pinned, reviewed revision.
- [An auto-merge through `GITHUB_TOKEN` triggers no `push` run on `main`] → the weekly scheduled `ci.yml` re-verifies `main`.
- [The wall-clock grep misses a `#[cfg(test)]` module or an unlisted API] → stated as the ceiling; review reads the rest.
