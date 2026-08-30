## Purpose

Defines how the workspace identifies, reproduces, and verifies one compatible Ratatoskr fleet snapshot across all sixteen independently released product repositories.

## ADDED Requirements

### Requirement: The workspace identifies the complete fleet
The workspace SHALL declare exactly one entry for each of the sixteen product repositories and SHALL keep repository identifiers, paths, canonical remotes, default branches, kinds, ownership, security classification, dependency edges, commands, contracts, and deployment-profile membership in a committed semantic manifest. Repository identifiers, paths, and canonical remotes MUST be unique, and commit identifiers MUST NOT appear in the semantic manifest.

#### Scenario: Complete fleet manifest
- **WHEN** an operator asks the workspace to validate the committed manifest
- **THEN** validation reports all sixteen product repositories exactly once and reports no topology error

#### Scenario: Duplicate or incomplete fleet manifest
- **WHEN** a repository identifier, path, or canonical remote is duplicated, or a required product repository is absent
- **THEN** validation fails and identifies every conflicting or missing entry without changing the checkout

### Requirement: Gitlinks are the authoritative revision pins
Every manifest repository SHALL have one matching `.gitmodules` entry and one committed gitlink at the declared path. The gitlink commit SHALL be the exact child revision selected for the snapshot; the manifest SHALL describe semantics and SHALL NOT override that revision.

#### Scenario: Matching materialized baseline
- **WHEN** all submodules are initialized at their committed gitlink revisions
- **THEN** snapshot validation succeeds without switching a child branch or modifying a child worktree

#### Scenario: Gitlink topology mismatch
- **WHEN** a manifest path, `.gitmodules` path or remote, and committed gitlink do not describe the same repository
- **THEN** snapshot validation fails with the repository identifier and conflicting values

#### Scenario: Materialized child drift
- **WHEN** an initialized baseline submodule is at another commit or contains tracked or untracked changes
- **THEN** snapshot validation fails and reports the affected repository without cleaning, resetting, or otherwise modifying it

### Requirement: The lock is generated deterministically
The workspace SHALL generate `workspace.lock` solely from the committed manifest, `.gitmodules`, gitlinks, and declared files at the pinned child revisions. For an unchanged input tree, repeated generation on supported hosts SHALL produce byte-identical output with stable ordering and no wall-clock timestamps, host paths, credentials, or other machine-local values.

#### Scenario: Repeated lock generation
- **WHEN** the lock is generated twice from the same manifest, gitlinks, and child contents
- **THEN** the two outputs are byte-for-byte identical

#### Scenario: Lock freshness check
- **WHEN** the committed lock differs from freshly generated output
- **THEN** the check fails, reports the semantic difference, and does not rewrite the lock

### Requirement: The lock proves snapshot content
For every product repository, the lock SHALL record the exact gitlink commit, canonical remote, default branch, and deterministic digests for every contract, schema, generated-client, or deployment-target file declared by that repository's manifest entry. The lock SHALL also record digests of the semantic manifest and `.gitmodules` so that the full snapshot description is tamper-evident.

#### Scenario: Declared artifact changes
- **WHEN** a declared contract, schema, generated-client, or deployment-target file changes at a newly selected child revision
- **THEN** regenerated lock data changes for that repository and the stale committed lock is rejected

#### Scenario: Declared artifact is absent
- **WHEN** a manifest declares a digest input that does not exist at the pinned child revision
- **THEN** lock generation fails and identifies the repository and missing path

### Requirement: Dependency topology is valid
Every dependency edge SHALL reference a declared repository, SHALL have a declared compatibility purpose, and the required-build dependency graph SHALL be acyclic. Validation SHALL report a deterministic dependency order and every detected cycle.

#### Scenario: Valid dependency graph
- **WHEN** every edge references a declared repository and the required-build graph is acyclic
- **THEN** validation reports a stable dependency order with contracts and required consumers before dependent producers and clients

#### Scenario: Invalid dependency graph
- **WHEN** an edge references an unknown repository or required-build edges form a cycle
- **THEN** validation fails with the unknown identifier or complete cycle path

### Requirement: Snapshot verification works from a fresh checkout
A documented bootstrap command SHALL initialize the sixteen read-only baseline submodules, and a documented verification command SHALL validate manifest syntax, topology, gitlinks, submodule state, dependency order, declared artifact digests, and lock freshness without requiring provider credentials or mutating repository state.

#### Scenario: Fresh public checkout
- **WHEN** an operator clones the public workspace, initializes its submodules, and runs snapshot verification
- **THEN** the command verifies the committed snapshot using only public repository access and exits successfully

#### Scenario: Uninitialized baseline
- **WHEN** snapshot verification runs before one or more required submodules are initialized
- **THEN** it fails with the exact initialization command and does not attempt an implicit network or Git mutation

### Requirement: Main is gated by the snapshot
Workspace continuous integration SHALL initialize the pinned submodules and run the same non-mutating snapshot verification exposed to operators. A commit with manifest, `.gitmodules`, gitlink, lock, dependency, or declared-artifact drift MUST NOT receive a successful workspace integration verdict.

#### Scenario: Consistent pull request snapshot
- **WHEN** a pull request contains a complete, deterministic, internally consistent fleet snapshot
- **THEN** the workspace snapshot check succeeds on the exact pull request commit

#### Scenario: Inconsistent pull request snapshot
- **WHEN** any authoritative snapshot source disagrees or a pinned commit cannot be fetched from its declared public remote
- **THEN** the workspace snapshot check fails before the commit can represent a verified `main` snapshot
