## Why

The fleet documentation still describes the bootstrap snapshot from 2026-08-20, while several repositories now contain implemented services, contracts, tests, and quality gates. Operators and agents can therefore select obsolete commands, treat implemented behavior as planned, or miss current producer and consumer relationships.

## What Changes

- Audit every tracked first-party documentation file against the current `origin/main` source, manifests, CI, OpenSpec state, and accepted ADRs in all 17 repositories.
- Correct factual drift in current-versus-planned status, repository responsibilities, interfaces, data ownership, deployment notes, development commands, tests, and quality gates.
- Keep accepted decisions intact, separate target architecture from implemented behavior, and remove or mark claims that cannot be verified.
- Record one scoped documentation commit on `main` in every repository, then record the 16 child SHAs and verification results in the workspace change.
- Publish in dependency order: `ratatoskr-contracts`; `ratatoskr-platform`, `ratatoskr-extractor`, `ratatoskr-knowledge`, `ratatoskr-github`, `ratatoskr-vault`, `ratatoskr-telegram`, `ratatoskr-x`, `ratatoskr-instagram`, `ratatoskr-threads`, `ratatoskr-chatgpt`, `ratatoskr-claude`; `ratatoskr-web`, `ratatoskr-mobile`, `ratatoskr-browser-extension`, `ratatoskr-export-agent`; and `ratatoskr-workspace` last. Contracts must land first when their documentation changes; the workspace evidence commit must land last.

## Capabilities

### New Capabilities

None. This change documents existing behavior only.

### Modified Capabilities

None. The change does not alter product or fleet requirements, so delta specs are skipped.

## Impact

The change touches documentation and OpenSpec planning records in all 17 public Ratatoskr repositories. It changes no runtime code, wire contract, API, schema, dependency, deployment, provider configuration, or frozen-host state. The two local legacy archives are outside the fleet and remain untouched. Each documentation commit can be rolled back independently with `git revert`; no runtime rollback is required because nothing is deployed by this change.
