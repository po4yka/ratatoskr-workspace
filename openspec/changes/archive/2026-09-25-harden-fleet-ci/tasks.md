## 1. Shared checks in the workspace

- [x] 1.1 Add `reusable-fleet.yml`, `reusable-zizmor.yml`, `reusable-openspec.yml`, `reusable-advisories.yml` and `reusable-dependabot-automerge.yml`, and turn the workspace's own `fleet.yml`, `zizmor.yml`, `openspec.yml`, `advisories.yml` and `dependabot-automerge.yml` into wrappers; CI configuration, so it cannot start from a failing test, and is verified by `zizmor` and a run of each wrapper
- [x] 1.2 Add the wall-clock step to `reusable-fleet.yml`; it was run against every repository's tree before it was turned on, and the hits it reported there (mobile's `ResumableUploadCoordinatorTest` among them) are the failing state it was written against
- [x] 1.3 Extend `drift.yml` with the automerge wrapper, the pinned-revision comparison and the `workspace.toml` declaration; CI configuration, verified by running its comparison against the real fleet trees
- [x] 1.4 Add the weekly schedule to the workspace `ci.yml`; a trigger change, which no test can fail first

## 2. Implementation by repository

These items record the branch each repository's change is made on; the coordinator opens the pull requests and records their links at publication. Each is CI configuration, manifests and test fixes whose failing state is the fleet wall-clock check above.

- [x] 2.1 `ratatoskr-workspace` (`chore/reusable-fleet-workflows`): reusable workflows, wrappers, drift assertions, weekly schedule, `docs/QUALITY_GATES.md`; merges first
- [x] 2.2 `ratatoskr-contracts` (`chore/fleet-hardening`): wrappers, weekly schedule, `deny` job, exact pins, wall-clock and silent-check audit
- [x] 2.3 `ratatoskr-platform` (`chore/fleet-hardening`): wrappers, weekly schedule, `deny` job, exact pins, wall-clock and silent-check audit
- [x] 2.4 `ratatoskr-extractor` (`chore/fleet-hardening`): wrappers, weekly schedule, `deny` job, exact pins, wall-clock and silent-check audit
- [x] 2.5 `ratatoskr-knowledge` (`chore/fleet-hardening`): wrappers, weekly schedule, `deny` job, exact pins, wall-clock and silent-check audit
- [x] 2.6 `ratatoskr-github` (`chore/fleet-hardening`): wrappers, weekly schedule, `deny` job, exact pins, wall-clock and silent-check audit
- [x] 2.7 `ratatoskr-vault` (`chore/fleet-hardening`): wrappers, weekly schedule, `deny` job, the `=0.23.43`-style exact pins removed, wall-clock and silent-check audit
- [x] 2.8 `ratatoskr-telegram` (`chore/fleet-hardening`): wrappers, weekly schedule, `deny` job, exact pins, wall-clock and silent-check audit
- [x] 2.9 `ratatoskr-channel-digests` (`chore/fleet-hardening`): wrappers, weekly schedule, `deny` job, exact pins, and the outbox audit made fail-closed
- [x] 2.10 `ratatoskr-x`, `ratatoskr-instagram`, `ratatoskr-threads`, `ratatoskr-chatgpt`, `ratatoskr-claude` (`chore/fleet-hardening`): wrappers, weekly schedule, `deny` job, exact pins, wall-clock and silent-check audit
- [x] 2.11 `ratatoskr-web`, `ratatoskr-browser-extension`, `ratatoskr-export-agent` (`chore/fleet-hardening`): wrappers, weekly schedule, wall-clock and silent-check audit
- [x] 2.12 `ratatoskr-mobile` (`chore/fleet-hardening`): wrappers, weekly schedule, the injected clock in `ResumableUploadCoordinatorTest` with the production `Clock.System` default removed, silent-check audit

## 3. Repository settings and documentation

- [x] 3.1 Enable Dependabot security updates and `allow_auto_merge`, and rewrite each ruleset with `fleet / invariants`, `zizmor / audit`, `openspec / specs` and every `ci.yml` job, after the wrappers have published the names; repository settings, verified by reading each one back
- [x] 3.2 State that security updates are enabled in both `dependabot.yml` forms; documentation, which no test can fail first
- [x] 3.3 Record every decision above, its motivation and its limit in `docs/QUALITY_GATES.md`; documentation, which no test can fail first
