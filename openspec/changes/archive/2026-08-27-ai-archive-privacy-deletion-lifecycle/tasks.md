## 1. Implementation by repository

- [x] 1.1 `ratatoskr-contracts` — coordination cannot start from a local failing test because implementation and RED/GREEN tasks live in the child change; verify its full gate is green and record the published `main` commit (PR link omitted because the owner explicitly required direct task-branch integration)
- [x] 1.2 `ratatoskr-knowledge` — after contracts, verify the user-requested tombstone integration test and full gate are green and record the published `main` commit (PR link omitted under the same direct-integration instruction)
- [x] 1.3 `ratatoskr-chatgpt` — after Knowledge, verify privacy deletion, reparse, parser migration, fixture admission, and the full gate are green and record the published `main` commit (PR link omitted under the same direct-integration instruction)
- [x] 1.4 `ratatoskr-workspace` — after all children, record their exact compatible commits and validation results in this changeset; no failing product test applies because this repository owns only the coordination contract

## 2. Integrated lifecycle verification

- [x] 2.1 Verify the contract fixture round-trips in ChatGPT and Knowledge, the Knowledge consumer commit predates ChatGPT production, and a replayed `user_requested` tombstone removes only its named derived subject
- [x] 2.2 Sync the `ai-archive-event-lifecycle` delta, run the available workspace fleet-tree and strict OpenSpec validations, and archive this change; `DEVELOPMENT.md` has no fenced workspace command because the integration harness is not implemented in this bootstrap repository
