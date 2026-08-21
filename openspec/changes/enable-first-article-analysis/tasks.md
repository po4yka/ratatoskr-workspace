## Implementation by repository

- [x] 1. `ratatoskr-knowledge` — implement local change `build-first-article-analysis` on `main`, pass its full repository gate, and record the full pushed commit SHA here. Direct `main` delivery is explicitly authorized for this change, so there is no pull request.
  Commit: `9e4c4d9fde9f843de85557061ad52c21c4c97514`

## 1. Workspace completion

- [x] 1.1 After the Knowledge commit is reachable from its remote, replace `pending` above with the full SHA and verify it with `git ls-remote`. No test: cross-repository delivery record.
- [x] 1.2 Re-read the published Document IR dependency, confirm Knowledge pins that contract and writes no Extractor table, and run `openspec validate enable-first-article-analysis --strict`. No separate RED: this is compatibility and planning verification.
