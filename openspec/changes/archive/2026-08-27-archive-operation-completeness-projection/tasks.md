## 1. Implementation by repository

- [x] 1.1 `ratatoskr-contracts` — add a failing result-association test for
  `ai_archive_import_summary`, then validate the bounded typed field shape. Verification: the
  contract fixture test passes. *(Merged as `33fd9991f1bb5c39fe779dff1369218a9e28e7e4`; hosted gates green.)*
- [x] 1.2 `ratatoskr-export-agent` — add fixture-driven consumer tests before implementation and
  then decode the summary from `GET /v1/operations/{id}`. Verification: its focused XCTest suite
  passes. *(Merged as `33d38940804dc466bcc2fa4e5d02e02cfcffcae4`; hosted gates green.)*
- [x] 1.3 `ratatoskr-chatgpt` and `ratatoskr-claude` — add failing terminal-report tests and emit
  the summary. Verification: each producer's contract test passes. *(Task commits
  `b76d7d247f15e7f12b644fb0f34c14f6b3912cd2` and
  `429644775a146d760d25e063aa1638151060eabd` are integrated on main; hosted gates green.)*
- [x] 1.4 `ratatoskr-platform` — verify generic result persistence returns the added
  fields unchanged. Verification: operation projection integration test passes against a summary
  fixture. *(Merged as `b422c323e19af606fd3371827d7fb512a6179383`; hosted gates green.)*

## 2. Integration and rollout

- [x] 2.1 Create the workspace changeset with dependency order, privacy review, rollout and
  rollback evidence. Verification: changeset is validated by the workspace harness when available.
- [x] 2.2 After child changes merge, pin the verified commits and run the available workspace
  integration checks. Verification: workspace main records the compatible snapshot. *(All recorded
  child commits have green hosted checks; workspace OpenSpec validation is the integration check.)*
