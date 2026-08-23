## 1. Implementation by repository

- [x] 1.1 `ratatoskr-platform`: apply `preserve-operation-report-details`, run its repository gate, push the scoped commit directly to `main` as explicitly authorized, and record the remote commit SHA (no PR is created because the current user request requires direct `main` publication)
- [x] 1.2 `ratatoskr-telegram`: after Platform, apply `persist-webhook-update-before-ack`, run its repository gate, push the scoped commit directly to `main` as explicitly authorized, and record the remote commit SHA (no PR is created because the current user request requires direct `main` publication)

## 2. Coordinated verification

- [x] 2.1 Verify both remote `main` branches contain the recorded commits, record their SHAs and local gate results in this change, and validate the workspace OpenSpec change strictly; this coordination task changes records only and cannot start from a failing product test
- [x] 2.2 Commit and push only this workspace changeset to `main`, preserving unrelated work, and verify `origin/main` resolves to the new workspace commit; this publication task cannot start from a failing product test
