# ADR-0008: OpenSpec as the planning layer, and a test-first task shape

> Status: Accepted  
> Owner: `ratatoskr-workspace`  
> Last reviewed: 2026-08-20  
> Related: `AGENTS.md`, `DEVELOPMENT.md`, `docs/QUALITY_GATES.md`, `docs/TESTING.md`

## Context

`AGENTS.md` requires a changeset ID for every change that touches more than one repository, and it
describes what a changeset records: goal, affected repositories, dependency order, compatibility
strategy, rollout, rollback, required checks. Nothing implements it. `ws`, `workspace.toml`,
`workspace.lock` and `changesets/` do not exist. The requirement has been binding for the whole of
the architecture bootstrap and has had no carrier.

The second gap is on the other side of the fleet. Fourteen of the seventeen repositories hold no
code. Each carries nine documents that describe intent in prose. None of them states a behaviour in a
form that becomes a test, so a repository can be planned for months and still hand its first
implementer a paragraph rather than a scenario.

The third gap is that test-first is not written down anywhere. `docs/TESTING.md` lists the layers a
test suite should have. It does not say that the failing test comes before the implementation, and an
agent reading `AGENTS.md` in any of the seventeen repositories was never told so.

## Decision drivers

- A cross-repository plan needs one place to live, readable from every repository that implements it.
- A repository with no code still needs somewhere to plan, and that place must not be a linter
  configuration for a milestone that has not started — `docs/QUALITY_GATES.md` refuses those.
- Whatever carries the rules has to reach an agent at the moment it plans, not only in a document.
- The fleet's controls are files that are identical everywhere, with a drift check that says so. A
  new control should have that shape or explain why not.

## Considered options

**A separate planning repository, `ratatoskr-plans`.** Matches the pattern already in use in another
project of this account. Rejected: the drift check discovers the fleet by the `ratatoskr-` name
prefix, so the new repository would join it as an eighteenth member and would need `fleet.yml`,
`zizmor.yml`, `openspec.yml`, `.githooks/pre-commit`, `dependabot.yml` and a branch ruleset before it
could hold a single line of planning.

**Local `openspec/` roots only, with no store.** Cheapest. Rejected: it leaves the cross-repository
plan with nowhere to live, which is the first of the three gaps and the one that has been open
longest.

**A store only, with no local roots.** Rejected: implementation in each repository then loses its own
apply, review and archive cycle. OpenSpec does not route tasks to repositories, so one shared task
list cannot be split by the directory an agent happens to run in.

**Converting the existing nine documents into specs.** Rejected. OpenSpec grows a spec from the
change that needed it. A bulk conversion produces a large spec set that is stale on the day it lands
and that nobody trusts, and the documents it copied are still there being the real answer.

## Decision

`ratatoskr-workspace` is the OpenSpec store for the fleet, under the id `ratatoskr-workspace`. It
already owns cross-repository coordination in `AGENTS.md`, so the store gives that role its tooling
instead of creating a second home for it. `.openspec-store/store.yaml` carries the identity and the
clone URL.

All seventeen repositories get their own `openspec/` root. Each of the sixteen product repositories
declares `references: [ratatoskr-workspace]` in `openspec/config.yaml` — read-only, by name and never
by path, which is what invariant 6 requires. `openspec instructions` in those repositories then lists
the store's specs with the exact command that fetches one.

`openspec/specs/` starts empty in all seventeen. The nine documents stay where they are, as material
an exploration reads.

The task shape is test-first, and it is carried by `rules.tasks` and `operations.apply.guidance` in
every `openspec/config.yaml` rather than by a document. Those fields are injected into every planning
and implementation request, which is the difference between a rule an agent follows and a rule an
agent could have read.

## Consequences

The gate gains one file, `.github/workflows/openspec.yml`, identical in all seventeen, running
`openspec validate --all --strict` and `openspec validate --archived`. It is separate from
`fleet.yml` for the reason `zizmor.yml` is separate: `fleet.yml` installs nothing and must stay able
to answer on a day when nothing can be pulled.

The CLI version is pinned in that file. Stores are a beta feature whose flags and file formats may
change between releases, so the pin is load-bearing rather than tidy, and raising it is one commit in
seventeen repositories.

Registering the store is per-machine state, like `git config core.hooksPath .githooks`. A clone that
has not run `openspec store register` resolves references to nothing. `openspec doctor` reports it.

`openspec init` generates nineteen command and skill files per repository. A partial `openspec update`
is a new class of drift, and `drift.yml` now compares both the set of those paths and each blob.

## Security and privacy

`openspec.yml` installs one npm package and needs `contents: read` and no token. OpenSpec disables
its telemetry in CI; the workflow sets `DO_NOT_TRACK` as well so a reader does not have to trust that
behaviour. The generated files were run through `fleet.yml`'s credential and private-key steps on a
tree that already contained them, and the tree was clean — the test that four earlier scanners in
this project failed.

## Compatibility and migration

Additive. No existing file is deleted and no command changes. `ci.yml` is untouched in the three
repositories that have one, so the step asserting that `ci.yml` and `DEVELOPMENT.md` are one list
keeps its meaning.

## Validation

Measured before any file was written:

| Question | Answer |
|---|---|
| `openspec validate --all --strict` on a root with no specs and no changes | prints `No items found to validate`, exits 0 |
| `openspec validate --archived` on the same root | prints `No archived changes found`, exits 0 |
| `openspec store setup` on a non-empty Git repository | accepted, but it makes its own commit with a non-Conventional subject, so the store files are written by hand and `openspec store register` is used instead — it commits nothing |
| `references:` resolution from a repository with its own root | `openspec doctor` reports `ok`, `openspec context` prints the fetch command |
| `fleet.yml`'s credential, private-key and CRLF steps on a tree containing the generated files | all three pass |
| `zizmor --persona pedantic --min-severity low` on the new workflow | one low finding, `adhoc-packages`, which the gate's own severity floor would have made fatal. Suppressed at the line with its reason; see `docs/QUALITY_GATES.md` |

Measured after:

| Assertion | Green | Red |
|---|---|---|
| A manifest requires a `ci.yml` that runs tests | exits 0 in contracts, platform and web as they stand | exits 1 in each when the test line is removed from a copy of its `ci.yml` |
| The shared files are one file across the fleet | reported across all seventeen indexes | reported the divergence when one repository's `opsx/propose.md` was altered by one line |
| A change may not be archived with work left undone | a change whose two tasks are both ticked passes, exit 0 | the same change with `1.2 Make it pass` unticked reports `1 incomplete task (1/2 completed)`, exit 1 |
| The whole `fleet.yml` step set, and both `openspec validate` commands | exit 0 in all seventeen repositories | — |

## Follow-up

- One real change end to end in `ratatoskr-contracts`, test-first, recorded in
  `docs/QUALITY_GATES.md`.
- `specs` added to `required_status_checks` in each of the seventeen rulesets, after a run has
  published the name.
- A coverage floor and mutation testing stay unadopted. Both are recorded in the rejected table of
  `docs/QUALITY_GATES.md` with what would have to be measured first.
- The Rust arm of the test-first rule is now a vendored skill. `rust-tdd`, from
  `po4yka/rust-skills`, is one of eighteen carried by the thirteen repositories whose stack is Rust,
  and it states the red-green-refactor loop in the tool commands those repositories actually run.
  This ADR is not superseded and no new one was written: the decision recorded here is unchanged,
  and `docs/QUALITY_GATES.md` carries the catalogue, the selection rule and the drift assertion.
