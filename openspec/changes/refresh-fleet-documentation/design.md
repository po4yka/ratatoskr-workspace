## Context

See `proposal.md` for motivation. The fleet is exactly 17 public, non-fork repositories with `main` as the default branch: 16 product repositories plus this workspace. The shared local checkout is current for 14 children; `ratatoskr-github` and `ratatoskr-vault` have newer remote commits, and existing shared worktrees for Browser Extension, Mobile, Platform, X, and Vault contain user-owned changes. The workspace currently has no `repos/`, `.gitmodules`, `workspace.toml`, or generated lock; `.workspaces/local/` is an operator-created checkout set, not the implemented target harness.

The audit found repeated drift in three forms: implemented services still described as documents-only, planned workspace pins and integration tests described as current, and migration/gate instructions that contradict the development-status rules or the files that CI actually runs. Accepted ADR decisions remain source material and are not rewritten merely to use newer wording.

## Goals / Non-Goals

**Goals:**

- Make every current-state claim traceable to remote `main` source, manifests, CI, OpenSpec, or an accepted ADR.
- Review every tracked first-party Markdown document and descriptive OpenSpec configuration in each repository, while changing only confirmed drift.
- Leave a repository-local audit record and one independently revertible commit per repository.
- Preserve user-owned dirty files and record exact remote SHAs, validation commands, workflow results, rollout, and rollback in the workspace change.

**Non-Goals:**

- No runtime, schema, contract, dependency, CI-policy, deployment, provider, or GitHub-settings change.
- No implementation of planned workspace pins, submodules, manifests, integration profiles, or the `ws` harness.
- No rewrite of accepted ADR history, no speculative documentation, and no date-only mass edit used as a substitute for factual review.
- No edit to the two remote-less legacy archives.

## Decisions

### Audit remote `main` in isolated worktrees

The coordinator fetches each child, verifies the remote head, and creates `.workspaces/refresh-fleet-documentation/repos/<repo-id>/` from that commit. Existing `.workspaces/local/` checkouts remain read-only. This avoids folding the five dirty shared worktrees into documentation commits and prevents the stale GitHub and Vault checkouts from becoming audit evidence. Reusing the shared checkouts was rejected because clean status is not equivalent to current remote state.

### Correct claims, not prose style

For each repository the writer reads `AGENTS.md`, the active or completed OpenSpec changes, accepted ADRs, source and manifests, CI, `README.md`, `DEVELOPMENT.md`, `docs/**/*.md`, deploy READMEs, and descriptive `openspec/config.yaml` text. A file changes only when a current-state assertion is wrong, an implemented fact is missing from the owning document, a planned capability is presented as current, or a command cannot be executed as written. Optional rewording and historical ADR text stay untouched.

The initial audit routes the confirmed drift as follows:

| Repository set | Required correction areas |
|---|---|
| Contracts | Crate count and AI archive contracts, current read-only gate, milestone numbering |
| Platform | Implemented milestone status, capture request shape, event roles, metric inventory |
| Extractor | Direct PDF implementation and crate inventory, implemented versus planned metrics |
| Knowledge | Implemented article analysis and OpenRouter adapter, credential wording, current OpenSpec capabilities |
| GitHub, Vault | Re-audit from their newer remote service-scaffold commits before editing; do not reuse the stale local findings |
| Telegram | Code-bearing OpenSpec context, PostgreSQL work authority, implemented versus planned flows, milestone split, no-migration wording, planned workspace pin, current recovery specification |
| Web | Mark absent workspace pin and Compose E2E as planned |
| Mobile, Browser Extension, Export Agent | Remove nonexistent product-gate contract, mark workspace integration as planned, and remove migration language where present |
| X, Instagram, Threads, ChatGPT, Claude | Describe schema as future until first persistence code, replace database-migration targets, and document the current OpenSpec-only gate |
| Workspace | Update the implemented-repository map, current producer/consumer flow, quality-gate measurements, and the distinction between target `repos/` topology and the existing local checkout set |

### Keep current specifications current without inventing behavior

Completed delta specs that describe already implemented behavior are synchronized into their repository's main specs when the repository workflow supports that operation. Archiving remains outside this change unless it is required by an existing repository instruction; an audit does not erase useful change history. No new requirement is created for a documentation correction, and this workspace change therefore sets `skip_specs: true`.

### Validate at the repository boundary and publish workspace last

Code-bearing repositories run the exact command block in their current `DEVELOPMENT.md`; documents-only repositories run both strict OpenSpec validations and their available invariant checks. Every repository also runs `git diff --check` and a final source-to-document review. Each child is committed and pushed independently after its gate passes. The workspace commit lands last and records all child SHAs and GitHub workflow conclusions. A later child remote advance pauses only that repository until its audit is replayed on the new head.

## Child publication record

The audit started from the fetched `origin/main` SHA in the Base column. The Published column is the
documentation commit that now heads that child repository's remote `main`.

| Repository | Base | Published |
|---|---|---|
| `ratatoskr-contracts` | `7f04ced73ded3de89fb344f863358d88e56ee5c5` | `3eecb5427f18c0bed35f1d95999fdcf6e035e312` |
| `ratatoskr-platform` | `c533ad7f0b4621070cec9075d933d0e2725e01d2` | `560dd3a278354a0998fb07279c31d71746c7b9f2` |
| `ratatoskr-extractor` | `2fb0ee3a5653bf2e32e9e12d919499aa9c923b71` | `4bfedae6ab2370b002b36c4f2fd07b3d3d7b4a6f` |
| `ratatoskr-knowledge` | `e4194a6a536dfeb28c3315028b85e77d31965201` | `ec8f875b45d9e4985d41c2fa6099cccf7dd9113d` |
| `ratatoskr-github` | `c326b5291faf465f1046e1bd4a3580125e8677dc` | `1843e6bf48ca9a7d7527898657c6ea6663303971` |
| `ratatoskr-vault` | `9d1afc3dd07b694ef40ece4bb03a028d7cd2ffce` | `e87a6a7ed4d6e11aba3287a917717781bd570e47` |
| `ratatoskr-telegram` | `fee55974e63897b81afec86fefdde797fe9f4b96` | `916665bdab8e6fafec91160e9d46efc3b79bd2dc` |
| `ratatoskr-x` | `7e197fc8ffb523a02e742ccf7e756ad3249c47df` | `3ab877dc83a034e74fe26fe6b5dff5777b3cab80` |
| `ratatoskr-instagram` | `e31f3c62d74833fd0dab69621243a50dd80a0f65` | `fcff7e2a22401c39a08da786abbbb56be6121619` |
| `ratatoskr-threads` | `152cb253a90e044419b479fab22c292bd60c94b4` | `61dbd37b2ed0be074d9474573ad42a6a5ad2ab85` |
| `ratatoskr-chatgpt` | `959026fef27018ba47b55644b72913146dbb11d6` | `d78de0e2f990b862c1caf32329fe36508f55b3d0` |
| `ratatoskr-claude` | `4744644f414c685aedd73cd49ff7b5e621e773db` | `33bf5865ab871d5a343c764dd157e92af3e17bbe` |
| `ratatoskr-web` | `23f19b9b334daf20e054a55c4c6e9d4d8e8a43fb` | `16f31f7515dc8776f053f9cd55b30dbf3a3585e2` |
| `ratatoskr-mobile` | `0918ac88e0a30cae2b97d9e0376d2cb86b5a398d` | `4e1d2563590dcadca8b346759a376e7e0b0cd9b8` |
| `ratatoskr-browser-extension` | `f40ec590d20698c53a5856aa801e68ac58d87b15` | `79ba2edd64d279e23f640c175ce2fafca2381f39` |
| `ratatoskr-export-agent` | `767748a55fd792022a4e8d2f9f81ab5d940617f3` | `9eaca566cbf0278d72988251a9227a5ba49eb3b0` |

### Verification result

- Every Rust child passed its full `DEVELOPMENT.md` gate and strict OpenSpec validation. Vault's
  local database suite passed against a temporary isolated PostgreSQL instance; Telegram's passed
  against the documented PostgreSQL 17 test URL.
- Web passed its full `DEVELOPMENT.md` gate and strict OpenSpec validation. The eight documents-only
  children passed `git diff --check` and both strict OpenSpec commands.
- Independent reviewers checked the service, planned-integration, and client groups. Every reported
  P2 documentation finding was corrected and the affected validation repeated.
- Every workflow triggered by the 16 child pushes completed successfully: `ci`, `fleet`, `openspec`
  and `zizmor` in code-bearing repositories, including Platform's `linux/arm64 artifact`; and
  `fleet`, `openspec` and `zizmor` in documents-only repositories.

One pre-existing fleet-policy gap remains outside this documentation-only change. GitHub, Telegram,
Knowledge and Vault have Rust but still use the non-Rust Dependabot form and have no scheduled
`advisories.yml`. The workspace drift job is expected to report that gap until a separate CI change
brings those four repositories into the Rust class. `docs/QUALITY_GATES.md` records the same limit.

## Risks / Trade-offs

- [A broad documentation sweep can turn into speculative rewriting] → Change only evidence-backed factual drift and retain no-finding files unchanged.
- [Remote branches can advance during 17-repository publication] → Fetch and compare immediately before each commit and again after each push; rebase is not used and a moved remote is re-audited in a fresh worktree.
- [Current commands can be too expensive for documents-only repositories] → Run the existing product gate only when it exists; otherwise use strict OpenSpec and invariant checks rather than inventing a gate.
- [Completed delta specs can remain invisible from main specs] → Synchronize implemented deltas where confirmed, but do not archive changes without the repository workflow requiring it.
- [Direct pushes bypass required checks for the owner] → Wait for every triggered GitHub workflow and record its final conclusion before the workspace evidence commit.

## Migration Plan

1. Create and record the 16 isolated child worktrees from current remote `main`.
2. Audit and publish Contracts first, then service repositories, then clients. One writer owns one repository worktree at a time.
3. Re-run a fleet-wide current-state and terminology scan, update workspace documentation and the SHA ledger, and publish workspace last.
4. Verify all 17 remote `main` heads and all triggered workflows.

Rollback is one normal `git revert` per affected repository in reverse publication order. The commits change documentation only, so there is no data, provider, deployment, or schema rollback.
