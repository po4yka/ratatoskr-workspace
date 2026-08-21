# Ratatoskr Workspace Agent Instructions

## Scope

These instructions apply to work performed in the `ratatoskr-workspace` Git repository.

The repositories mounted under `repos/` are independent Git repositories. Their own `AGENTS.md` files govern work inside them. The workspace repository coordinates those repositories; it does not absorb their domain implementation.

## Repository mission

`ratatoskr-workspace` is the integration and orchestration point for the Ratatoskr multi-repository system. It is responsible for:

- pinning a compatible set of child repository commits;
- describing repository topology, dependencies, profiles, and commands;
- creating isolated task worktrees;
- coordinating Claude Code, Codex, and other coding agents;
- tracking cross-repository changesets;
- running cross-service integration environments and tests;
- producing reproducible system snapshots and release tags.

It must provide a monorepo-like developer experience without destroying the independent history, release lifecycle, data ownership, or security boundary of any child repository.

## Current phase

The repository is in architecture bootstrap. Do not assume that `ws`, `workspace.toml`, `workspace.lock`, submodules, CI jobs, Compose profiles, hooks, or agent adapters already exist unless they are present in the checked-out tree.

When documentation describes planned commands or files that are not implemented yet:

- do not claim that they were executed;
- do not create unrelated scaffolding merely to make the documentation appear true;
- implement only the part explicitly required by the current task;
- update these instructions when the operating model materially changes.

### Development status

Ratatoskr is in development. No database holds data that has to survive a schema change. While this
status holds, these rules are binding, and they override anything else in this repository that
plans otherwise, including the rest of this file:

- **One version only.** The API, the database, and the contracts keep their first version. Do not
  add a `v2` or a later major version, and do not add version negotiation, deprecation windows, or
  parallel-major routing.
- **No database migrations.** Do not add a migration file, and do not add migration tooling. A
  schema change edits the current schema definition in place, and a test database is created from
  that definition.
- **The product is `Ratatoskr`.** It is not "Ratatoskr Next". Do not write that name in code,
  documentation, identifiers, comments, or commit messages.

Only the repository owner changes this status. Ask before you write anything these rules forbid.

## How a change starts

Every non-trivial change begins as an OpenSpec change rather than as an edit, and each assistant
starts one in its own syntax. Claude Code has the command: `/opsx:propose <what you want to build>`,
or `/opsx:explore` first when the shape is not clear yet. Codex has no project-level command and
triggers the same skill by name, `$openspec-propose`, or lets its description match it. OpenCode has
its own command, `/opsx-propose`. Whichever starts it, the result is `openspec/changes/<id>/` holding
a proposal, the spec deltas, a design and a task list, and you read that plan before any code is
written. `/opsx:apply`, `$openspec-apply-change` or `/opsx-apply` builds it, and `/opsx:archive`,
`$openspec-archive-change` or `/opsx-archive` folds the deltas into `openspec/specs/`.

`openspec/specs/` holds the behaviour that is true today, and it starts empty on purpose. A spec here
grows from a change that needed it. Do NOT convert `docs/REQUIREMENTS.md`, `docs/INTERFACES.md`,
`docs/DOMAIN.md` or `docs/DATA_MODEL.md` into specs in bulk. Those documents stay where they are, as
material an exploration reads. A spec set produced by bulk conversion is large, stale on the day it
lands, and trusted by nobody.

This repository is the store for the fleet. What belongs here is behaviour that more than one
repository can see — the shape of a contract, the meaning of a field, the order in which repositories
must receive a change. Behaviour internal to one repository belongs in that repository's own
`openspec/`, not here. The sixteen product repositories reference this store by name, so a spec
written here is readable from all of them.

### Tests come first

The task list carries one pair per behaviour. The first task adds a test that fails. The second makes
it pass. Never one task that does both.

- Run the new test before you write the implementation, and confirm it fails for the reason the task
  states — not for a compile error or a typo.
- A refactor task comes after the tests are green. It adds no test and changes no behaviour.
- A task that cannot start from a failing test says why in one line. Configuration, documentation and
  generated files are the usual reasons.
- Do not tick a task whose test has not been run.

Nothing can check the order in which the two were written. What CI does check is
`openspec validate --archived`, which fails when a change was archived with a task left unticked, and
the step in `fleet.yml` that fails when a repository holds a manifest and a `ci.yml` that never runs
a test. `ratatoskr-workspace/docs/QUALITY_GATES.md` states that limit rather than implying it is
covered.

## The Rust skill catalogue

`.agents/skills/` holds eighteen Rust skills, and `.claude/skills/` symlinks to them, so all three
assistants read one copy. Codex reads `.agents/skills/`, Claude Code reads `.claude/skills/`, and
OpenCode scans both, so the existing symlink already covers it and nothing belongs under
`.opencode/skills/`. Each is a reference sheet rather than a tutorial: the commands, flags,
thresholds and triage tables for one Rust concern. Your assistant reads the descriptions and opens a
skill only when the task matches one, so the set costs almost nothing until it is needed.

`rust-tdd` is the Rust form of the task pair above. `rust-lints` owns `clippy.toml`, which is where
this repository's size limits live. `rust-security` answers a `RUSTSEC` advisory.
`rust-async-internals` covers `tokio::select!` cancel safety and shutdown. `rust-database` covers
pool budgets and transaction ownership. `rust-compiler-errors` is the entry point when the build
fails and the cause is not obvious.

`rust-database` also carries a section on deploying migrations in compatible phases. The Development
status above overrides it: while that status holds, this product has no migrations at all. Read the
rest of that skill and skip that section.

The eighteen are identical in every Ratatoskr repository whose stack is Rust, and
`ratatoskr-workspace/.github/workflows/drift.yml` fails when one copy stops matching the others. Do
not edit a file under `.agents/skills/`. A correction belongs upstream in `po4yka/rust-skills` and
reaches this repository through `npx skills update`.

The catalogue holds forty-four skills and eighteen are vendored here.
`ratatoskr-workspace/docs/QUALITY_GATES.md` records which were left out and why. They are vendored
under BSD-3-Clause, (c) 2026 Nikita Pochaev, who also owns this repository; each `SKILL.md` keeps its
`license` field, and the full text is in that repository's `LICENSE`.

## Sources of truth

Use the following precedence order:

1. the active task or changeset specification;
2. accepted ADRs in `docs/adr/`;
3. `README.md` and architecture documents;
4. `workspace.toml` for semantic repository configuration;
5. Git submodule pointers for exact compatible commits;
6. generated `workspace.lock` for the resolved snapshot;
7. repository-local `AGENTS.md` files for child implementation rules.

Do not silently reconcile contradictions. Surface the conflict and preserve the stricter safety or compatibility rule until an explicit decision is made.

## Non-negotiable invariants

1. **Baseline submodules are read-only.** Never edit files directly under `repos/` in the pinned workspace checkout.
2. **All implementation happens in task worktrees.** Use `.workspaces/<task-id>/repos/<repo-id>/` or the equivalent path created by the harness.
3. **One writer per repository per task.** Multiple read-only reviewers are allowed; concurrent writers to one repository worktree are not.
4. **Every cross-repository change has a changeset ID.** The changeset records affected repositories, dependency order, rollout, rollback, and verification.
5. **Each child repository remains independently buildable.** Do not require the workspace checkout for normal production builds.
6. **No committed relative path dependencies between repositories.** Temporary local overrides may be generated by the harness and must not leak into commits.
7. **Contracts evolve through expand/migrate/contract.** Do not coordinate a simultaneous breaking cutover across all repositories.
8. **Workspace `main` represents a verified compatible snapshot.** Do not advance pins without integration validation.
9. **Agents do not merge or push outside the explicit harness/publish workflow.** Creating local commits or draft PRs must follow the active task authorization.
10. **Secrets never enter repository manifests, task context, generated lockfiles, logs, fixtures, or agent prompts.**

## Allowed responsibilities

Changes in this repository may include:

- `workspace.toml`, `.gitmodules`, and generated `workspace.lock` handling;
- the Rust `ws` CLI and MCP server;
- Git/submodule/worktree orchestration;
- task and changeset schemas;
- Claude Code, Codex, and neutral agent-kit configuration;
- cross-repository contract-impact analysis;
- Docker Compose integration profiles and test fixtures;
- release coordination and pinned snapshot updates;
- architecture, operations, and runbook documentation;
- workspace-level CI that validates topology and compatibility.

## Responsibilities that belong elsewhere

Do not place the following in this repository:

- service domain logic;
- provider OAuth clients or tokens;
- database entities owned by a service;
- extraction, LLM, Git backup, or social synchronization implementation;
- copied source code used to bypass a child repository release;
- a universal shared application layer for all services.

If a workspace feature needs child-repository behavior, define a stable manifest, command, or contract rather than importing private implementation.

## Required workflow

### 1. Establish task context

Before changing files:

- identify the task or changeset ID;
- inspect the workspace status and dirty repositories;
- determine the affected repository set;
- read each affected child repository's `AGENTS.md`;
- identify contract producers, consumers, rollout order, and rollback constraints.

Do not begin a cross-repository implementation from an untracked chat instruction alone when a changeset file is required by the repository's current workflow.

### 2. Protect the baseline

The pinned checkout under `repos/` is evidence of the current system snapshot.

- Do not switch branches inside baseline submodules.
- Do not leave baseline submodules dirty.
- Do not update submodule pointers while child PRs are still unmerged unless the task explicitly tests proposed commits.
- Do not run cleanup commands that can remove user-created worktrees or untracked task artifacts.

### 3. Create isolated worktrees

For every repository that needs writes:

- fetch the intended base ref;
- create a task-specific branch;
- create a dedicated worktree;
- record branch, base commit, repository role, and dependencies in the changeset;
- give exactly one writer agent ownership of that worktree.

### 4. Implement in dependency order

Typical order:

1. contracts;
2. backward-compatible consumers;
3. producers;
4. clients;
5. integration environment;
6. workspace pins after child merges.

A different order is valid only when the changeset explains why compatibility remains safe.

### 5. Verify locally and system-wide

Run repository-local checks in each child worktree before workspace integration checks. The workspace must not hide a child repository failure.

When the relevant tooling exists, workspace verification should include:

- `workspace.toml` and `.gitmodules` consistency;
- existence of all pinned commits;
- deterministic `workspace.lock` generation;
- dependency graph cycle detection;
- contract producer/consumer compatibility;
- generated client and agent-config drift;
- each repository's `## Deployment target` section against `docs/DEPLOYMENT_TARGET.md`;
- selected Compose profile startup;
- cross-service integration and upgrade/rollback tests;
- absence of dirty baseline submodules.

If a documented command does not exist, report that fact and use only available repository commands.

### 6. Publish coordinated changes

Child repository PRs are opened first. The workspace pin PR is opened only after the intended child commits are known and the combined snapshot has passed integration validation.

Every workspace pin PR must state:

- changeset ID;
- child PRs and merged commit SHAs;
- profiles tested;
- contract or schema versions changed;
- rollout order;
- rollback plan;
- unresolved risks.

## Cross-repository changesets

A changeset is the coordination record, not a replacement for Git history. It should include:

- goal and non-goals;
- affected repositories and roles;
- dependency graph;
- compatibility strategy;
- database schema change and event migration impact;
- rollout and rollback order;
- required checks;
- PR and commit references;
- final pinned workspace snapshot.

Do not mark a changeset complete merely because all child PRs merged. It is complete only after the verified pins land in the workspace and the release state is recorded.

## Agent orchestration rules

The workspace coordinator is read-only with respect to child implementation unless explicitly assigned as that repository's writer.

Every worker agent receives a bounded context containing:

- task goal;
- assigned repository and worktree;
- allowed paths;
- relevant contracts;
- upstream and downstream dependencies;
- required checks;
- forbidden operations.

Agent results should be machine-readable where possible and include:

- summary;
- changed files;
- commands run;
- check results;
- commit SHA, when created;
- blockers and unresolved risks.

Do not let agent-native teams or subagents own Git topology. Claude/Codex delegation may parallelize analysis or repository-local work, but `ws` remains responsible for branches, worktrees, changesets, validation, and PR coordination.

## Git and destructive-operation safety

Never run or authorize the following without explicit user approval and a verified target:

- force-push;
- destructive ref updates;
- `git reset --hard` on a user worktree;
- recursive deletion of `.workspaces/`;
- removal of unmerged branches or worktrees;
- automatic merge of a release train;
- deletion of tags or published snapshots.

Prefer additive operations and dry-run/status output. Preserve unrelated user changes.

A branch already merged into `main` is the one exception, and it points the other way: delete it.
`delete_branch_on_merge` is set on all 17 repositories, so GitHub does it at the merge; a branch left
over from before is deleted by hand. Its head is reachable from `main`, so nothing is lost, and the
pull request keeps the name, the diff and the checks. Use `git branch -d`, which refuses a branch that
is not fully merged, and never `-D`, which is the flag that removes one without asking.
`ratatoskr-workspace/docs/QUALITY_GATES.md` carries the rule and what was measured before it was
applied.

## Documentation rules

- Describe current behavior separately from target architecture.
- Mark planned commands and files as planned until implemented.
- Keep repository names, deployable names, event names, and paths consistent with manifests and contracts.
- Record significant topology, release, or compatibility decisions as ADRs.
- Do not duplicate detailed child-domain rules in the root; link to the owning repository instead.

## Completion criteria

A workspace task is complete only when:

- baseline submodules remain clean;
- all writes occurred in assigned task worktrees;
- affected child repositories pass their own checks;
- compatibility and integration checks pass for the selected profiles;
- generated manifests and lockfiles are current;
- the changeset accurately records PRs, commits, rollout, rollback, and verification;
- no secret or local-only override is committed;
- documentation reflects the implemented state;
- the resulting workspace pins form a reproducible compatible snapshot.
