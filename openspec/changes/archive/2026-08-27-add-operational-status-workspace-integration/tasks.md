## 1. Implementation by repository

- [x] 1.1 `ratatoskr-contracts` — close only after tasks 2.1-2.9 are complete, its archived local
  OpenSpec change and generated artifacts are on remote `main`, and the verified commit URL is
  recorded here: https://github.com/po4yka/ratatoskr-contracts/commit/9a4df8126b495ffc3ad0647441da1690594f25bc.
  PR: not used because the user explicitly required direct task-branch integration and push to
  `main`.
- [x] 1.2 `ratatoskr-platform` — close only after tasks 3.1-3.18 are complete, its archived local
  OpenSpec change and generated OpenAPI are on remote `main`, and the verified commit URL is recorded
  here: https://github.com/po4yka/ratatoskr-platform/commit/3b6efb1942d0ebc7735faa8ceb04338a54b535db.
  PR: not used by explicit delivery direction.
- [x] 1.3 `ratatoskr-web` — close only after tasks 4.1-4.25 are complete, its archived local OpenSpec
  change, browser evidence, and current documentation are on remote `main`, and the verified commit
  URL is recorded here: https://github.com/po4yka/ratatoskr-web/commit/856d224969067a8a26c02bb5171d93858cd62d8a.
  PR: not used by explicit delivery direction.
- [x] 1.4 `ratatoskr-workspace` — close only after tasks 5.1-5.11 and the publishable parts of
  6.1-6.5 are complete, this fleet change and the executable profile are on remote `main`, and the
  verified commit URL is recorded here:
  https://github.com/po4yka/ratatoskr-workspace/commit/55bc278c6d5ee3bbb5c39989c79ee64ad2c42dc0.
  PR: not used by explicit delivery direction. The archive-only follow-up remains part of the same
  task branch and is pushed before final worktree cleanup.

## 2. ratatoskr-contracts

- [x] 2.1 Create the Contracts writer worktree from verified `origin/main` and the local OpenSpec
  change `add-operational-query-contracts` citing this fleet spec. This is planning/configuration and
  cannot start from a behavior test; verify `openspec status` reports proposal, specs, design, and
  tasks ready before editing canonical contract code.
- [x] 2.2 RED: add `crates/operational-contracts/tests/public_status.rs` test
  `public_status_rejects_unknown_or_unsanitized_components`; assert a valid operational/degraded
  round trip succeeds while unknown component/state values and diagnostic/address fields are
  rejected, run it, and record the expected behavior failure rather than a compile or fixture typo.
- [x] 2.3 GREEN: implement the public status enums, component observation, status document,
  validation, and exact capability/grant constants in `crates/operational-contracts/` until the test
  from 2.2 passes.
- [x] 2.4 RED: add `crates/operational-contracts/tests/inspection.rs` test
  `operational_pages_are_bounded_and_content_free`; assert operation, schedule, and audit pages
  accept the required identifiers/states/timestamps/cursor but reject over-limit collections,
  unbounded strings, arbitrary JSON, request payloads, and diagnostic fields; run and record the
  expected behavior failure.
- [x] 2.5 GREEN: implement operation, schedule, and audit summary/page types with field docs,
  nullability, timestamp authority, and validators until the test from 2.4 passes.
- [x] 2.6 RED: extend the generator registry test in `tools/contractsc/tests/registry.rs` with
  `operational_contract_is_registered_once`; assert the new canonical crate has one metadata family,
  JSON Schema target, TypeScript target, valid fixture set, invalid expectation set, and frozen API
  baseline; run and record its missing-family failure.
- [x] 2.7 GREEN: add the workspace member, `contracts.toml` metadata, valid/invalid/privacy fixtures,
  invalid expectations, generator registration, and reviewed public API baseline until 2.6 passes.
- [x] 2.8 Run `cargo contracts generate`, review every JSON Schema and TypeScript diff, then run
  `cargo contracts check-typescript`. Generated files cannot start from a failing behavior test;
  verify provenance, determinism, and absence of orphan artifacts.
- [x] 2.9 Run the Contracts gate in `DEVELOPMENT.md` in order through the machine-wide build gate for
  compiler-backed commands, validate and archive the local OpenSpec change, inspect the final diff,
  commit only intended paths, integrate the task branch into Contracts `main`, push `main`, and
  verify remote `main` contains the task head before recording the SHA in 1.1.

## 3. ratatoskr-platform

- [x] 3.1 Create the Platform writer worktree from verified `origin/main` and the local OpenSpec
  change `add-owner-operational-api` citing this fleet spec. This is planning/configuration and cannot
  start from a behavior test; verify all planning artifacts are ready before code.
- [x] 3.2 Pin every Contracts dependency to the full verified SHA from 2.9 and add
  `ratatoskr-operational-contracts` to the one workspace dependency block. Dependency pinning is
  configuration; verify `cargo fetch --locked` resolves one Contracts revision and review the
  lockfile diff before behavior work.
- [x] 3.3 RED: extend `crates/public-api/tests/capabilities.rs` with
  `operational_capabilities_follow_live_owner_grant`; assert a member receives none, an owner receives
  the three sorted names, revocation removes them during the same session, and a failed grant lookup
  returns a dependency error; run and record the authorization failure.
- [x] 3.4 GREEN: add the closed operational capability variants and one bounded live grant lookup,
  then filter capability discovery until 3.3 passes without caching authorization in the session.
- [x] 3.5 RED: add `crates/public-api/tests/admin_operations.rs` test
  `owner_lists_and_reads_cross_user_operations_while_member_is_denied`; assert member 403 with no
  rows, owner keyset pagination/filtering across two users, safe failure codes, cross-user owner
  detail, and unchanged ordinary-route 404 semantics; run and record the route failure.
- [x] 3.6 GREEN: add bounded operations repository queries plus the two privileged routes using
  shared contract responses and existing `OperationSnapshot` detail until 3.5 passes.
- [x] 3.7 RED: add `crates/public-api/tests/admin_schedules.rs` test
  `owner_reads_schedule_status_without_payloads`; assert member denial, deterministic pagination,
  absent last outcome before first occurrence, retained failed outcome after disable, and omission
  of command payload/configuration; run and record the missing-route failure.
- [x] 3.8 GREEN: add the schedule-status keyset query and owner-only route over Platform-owned
  `operations.schedule_status` until 3.7 passes without adding a schema or migration.
- [x] 3.9 RED: add `crates/public-api/tests/admin_audit.rs` test
  `owner_reads_stable_redacted_audit_pages`; assert member denial, newest-first tie-breaking,
  anonymous actor nullability, cursor continuity, and absence of bodies, tokens, private URLs, and
  diagnostics; run and record the missing-route failure.
- [x] 3.10 GREEN: add the bounded audit query and owner-only route using the shared audit page type
  until 3.9 passes.
- [x] 3.11 RED: add `crates/public-api/tests/status.rs` test
  `public_status_is_anonymous_degraded_and_sanitized`; assert no credential is required, valid and
  invalid credentials produce the same shape, healthy facts are operational, lost NATS/downstream
  observations become degraded/stale, never-observed is unknown, storage loss is unavailable,
  internal names/addresses/reasons are absent, and `Cache-Control` is `no-store`; run and record the
  missing-route failure.
- [x] 3.12 GREEN: expose the read-only RuntimeState observations needed by the projector, aggregate
  cached gateway facts into four public groups, and add `GET /v1/status` with no request-time I/O
  until 3.11 passes.
- [x] 3.13 RED: extend `tools/openapic` route/schema tests with
  `operational_and_status_security_is_exact`; assert `/v1/status` has no session security, every
  `/v1/admin/*` route requires a session, response schemas reference the shared contract names, all
  list bounds/cursors are documented, and the committed OpenAPI is stale before regeneration; run
  and record the expected drift failure.
- [x] 3.14 GREEN: register route docs and schemas, run `cargo run -p openapic -- generate`, review the
  full OpenAPI diff, and rerun 3.13 until it passes.
- [x] 3.15 RED: add `crates/public-api/tests/admin_authorization_matrix.rs` test
  `every_admin_route_rechecks_owner_and_fails_closed`; enumerate every privileged method/path for
  absent, member, owner, revoked-owner, and database-failure states, assert no accidental 2xx or row
  disclosure, and record any matrix failure. The first matrix run passed because the preceding
  route slices already used the shared adapter; their RED runs provide the owner-gating failures.
- [x] 3.16 GREEN: consolidate only the repeated owner-check adapter needed to make 3.15 pass; this is
  not a route-level compatibility shim and does not alter ordinary resource ownership.
- [x] 3.17 Update Platform README/DEVELOPMENT/interfaces/privacy documentation after the routes and
  checks exist. Documentation cannot start from a behavior test; verify it distinguishes public
  status from operator health and documents out-of-band `platform.owner` provisioning without a
  real identifier or credential.
- [x] 3.18 Run focused tests first, then the exact Platform gate from `DEVELOPMENT.md` with one
  `build-gate --` acquisition for each top-level Cargo build/test sequence and release jobs at most
  two; validate/archive the local OpenSpec change, inspect the final diff, commit intended paths,
  integrate into Platform `main`, push `main`, and verify remote containment before recording 1.2.

## 4. ratatoskr-web

- [x] 4.1 In the existing Web task worktree, create the local OpenSpec change
  `add-operational-status-surfaces` citing this fleet spec and record the agreed public seams:
  generated Edge gateway, browser routes, accessibility tree, and composed public HTTP boundary.
  Planning cannot start from a behavior test; verify all local artifacts are ready before code.
- [x] 4.2 Update the pinned Platform OpenAPI source/digest from the verified Platform SHA in 3.18,
  run `npm run api:check`, and record its expected generated-type drift failure. This is the required
  pre-regeneration contract red, not a compile failure.
- [x] 4.3 Run `npm run api:gen`, review the generated TypeScript diff without hand edits, rerun
  `npm run api:check`, and commit the contract pin/generated files as their own commit.
- [x] 4.4 Add only `@playwright/test` and `@axe-core/playwright` as development dependencies, add the
  Chromium-only Playwright configuration and bounded local mock-Platform runner, verify they do not
  enter the production bundle, and commit this dependency addition separately with security,
  maintenance, license, and bundle-impact rationale. Configuration cannot start from a behavior
  test.
- [x] 4.5 RED: add `src/features/status/status-page.test.tsx` and
  `e2e/public-status.spec.ts` test `anonymous degraded status stays outside session boot`; assert
  `/status` sends only `GET /v1/status`, never redirects or probes a session, renders degraded/stale
  text from the generated shape, and distinguishes offline from empty/operational; run both and
  record their route/behavior failures.
- [x] 4.6 GREEN: implement the anonymous status source, lazy top-level route, semantic page, retry,
  stale labeling, and document metadata until 4.5 passes in light and dark themes.
- [x] 4.7 RED: extend `src/components/shell/nav-gating.test.tsx` and add
  `src/app/ops-route.test.tsx` test `member cannot discover or deep-link to owner operations`; assert
  each operational capability gates its own link/route, capability-read failure stays retryable,
  and a stale rendered link still shows Platform forbidden; run and record the gating failure.
- [x] 4.8 GREEN: add the three exact capability names, grouped operational navigation, lazy route
  registry, and forbidden/absence surfaces until 4.7 passes without treating hidden UI as security.
- [x] 4.9 RED: add `src/features/operations-admin/operations-page.test.tsx` and the matching browser
  test `renders every lifecycle and safe failure without private diagnostics`; assert loading,
  empty, next-cursor, partial, offline, forbidden, failed, and partially-succeeded states plus
  generated admin paths; run and record the missing-view failure.
- [x] 4.10 GREEN: implement the operations source/list/detail presentation with URL cursor and exact
  text state labels until 4.9 passes; no unbounded client filtering or browser-owned response type.
- [x] 4.11 RED: add `src/features/operations-admin/schedules-page.test.tsx` test
  `renders unknown disabled and failed schedule truthfully`; assert loading, empty, pagination,
  absent last outcome, disabled state, failed last outcome, offline, and forbidden; run and record
  the missing-view failure.
- [x] 4.12 GREEN: implement the schedule source and responsive semantic table/list until 4.11 passes,
  with no command payload or configuration presentation.
- [x] 4.13 RED: add `src/features/operations-admin/audit-page.test.tsx` test
  `renders bounded audit actors and empty separately from failure`; assert actor absence remains
  unknown, outcome/action/target/correlation are readable, cursor pagination works, and empty,
  offline, forbidden, and terminal states differ; run and record the missing-view failure.
- [x] 4.14 GREEN: implement the audit source and viewer until 4.13 passes, without payload export,
  raw diagnostics, or private-data logging.
- [x] 4.15 RED: add `src/app/route-focus.test.tsx` and `e2e/keyboard-navigation.spec.ts` test
  `route changes and disclosures keep visible logical focus`; assert the skip link reaches main,
  route navigation focuses the new h1, background refresh does not steal focus, Tab order is
  logical, Enter/Space activates controls, Escape closes disclosures, and dialogs return focus; run
  and record the focus/keyboard failures.
- [x] 4.16 GREEN: add one route-focus manager at the shell/public-router boundary and fix affected
  composed components outside generated UI directories until 4.15 passes.
- [x] 4.17 Run the first full Playwright axe matrix over status, member `/ops`, owner operations,
  schedules, audit, login, search, and reader in both themes at 320px and 1280px; this is audit
  evidence rather than a new behavior task. Record every serious/critical finding and manual check
  honestly in `docs/ACCESSIBILITY_CHECKLIST.md`; do not mark a manual screen-reader check observed
  unless it was performed.
- [x] 4.18 For each finding from 4.17, add a named failing regression test to the local Web OpenSpec
  task list and run it before its smallest fix; rerun the route matrix until serious/critical axe
  findings are zero and keyboard, landmark, focus, contrast, reduced-motion, target-size, and mobile
  overflow checks have observed outcomes. Verify the committed checklist maps findings to fixes or
  explicit unverified residual checks.
- [x] 4.19 Run `npm run audit:ui` and rendered `shadscan --check-ui` against status and every `/ops`
  route in both themes/target viewports. This is deterministic verification, not behavior creation;
  fix only real findings through a new red-green pair and never lower the score ratchet.
- [x] 4.20 Update README, DEVELOPMENT, IMPLEMENTATION_PLAN, TESTING, ARCHITECTURE, and any affected
  ADR/current-status text to implemented reality and the still-deferred fleet decisions.
  Documentation cannot start from a behavior test; verify it no longer says the router/API/views/e2e
  suite are absent and does not claim Compose deployment or localization.
- [x] 4.21 Add `test:e2e` to the documented/hosted Web gate with Chromium installation pinned in CI
  and a parity assertion for the new command. CI configuration cannot start from a behavior test;
  verify the local command and workflow use the same bounded route matrix.
- [x] 4.22 Run the full Web gate in documented order: clean install, API check, typecheck, lint,
  format check, Vitest, Playwright e2e, `build-gate -- npm run build`, shadscan at the existing or
  raised ratchet, and production dependency audit; record exact counts and outcomes.
- [x] 4.23 Validate and archive the local Web OpenSpec change with every task checked, inspect source
  and generated diffs for scope/privacy/accessibility regressions, and create the required separate
  dependency, contract-generation, and feature/evidence commits following recent convention.
- [x] 4.24 Integrate the Web task branch into an up-to-date clean `main` context without overwriting
  the user's modified baseline `AGENTS.md`, push `main`, and verify remote `main` contains every task
  commit before recording 1.3.
- [x] 4.25 Keep the Web worktree and merged branch until the workspace composed smoke in section 5
  has passed against its exact remote SHA; verify no cleanup happens early.

## 5. ratatoskr-workspace integration

- [x] 5.1 RED: add `integration/tests/web_operational_profile_test.sh` test
  `profile_is_namespaced_bounded_and_complete`; assert the profile requires a task namespace and
  explicit child contexts, declares Web/Edge/PostgreSQL/NATS with bounded health checks, has no fixed
  global container names or secret values, and teardown selects only its Compose project; run and
  record the missing-profile failure.
- [x] 5.2 GREEN: add `integration/compose/web-operational.yaml`, bounded synthetic seed SQL, and the
  namespace/validation shell needed to make 5.1 pass without implementing the general `ws` harness
  or committing relative child dependencies.
- [x] 5.3 RED: extend `integration/tests/web_operational_profile_test.sh` with
  `smoke_has_owner_member_status_and_degraded_phases`; assert the runner has bounded startup, seeds
  one owner grant and one member, checks anonymous status and all privileged routes through public
  HTTP, stops only its own NATS service for degradation, and always tears down; run and record the
  missing-runner failure.
- [x] 5.4 GREEN: implement the smoke runner and its Playwright handoff until 5.3 passes, redacting
  fixture credentials from output and preserving logs/artifacts only inside the task evidence path.
- [x] 5.5 Inspect `docker ps`, allocated ports, and existing Compose projects, then run the profile's
  healthy phase against the exact remote Contracts, Platform, and Web SHAs. This is cross-system
  verification; record anonymous status, member 403, owner operations/schedules/audit, Web route,
  health-check, and browser outcomes without treating container startup as proof.
- [x] 5.6 Stop only WEB-012's namespaced NATS service, wait for the bounded Platform observer, run the
  degraded API and browser assertions, restart it, and verify recovery. Record timestamps and exact
  assertions; do not touch unrelated containers.
- [x] 5.7 Run the real-profile keyboard and axe smoke for `/status` and `/ops`, then compare it with
  the local-mock checklist. Record any integration-only finding and return it to a new Web red-green
  task before claiming accessibility acceptance.
- [x] 5.8 Tear down only the WEB-012 Compose project and verify unrelated containers, ports,
  databases, streams, volumes, source checkouts, and user worktrees are unchanged.
- [x] 5.9 Add `changesets/WEB-012-operational-status.yaml` with affected repositories, exact bases
  and final SHAs, dependency graph, no-schema-migration statement, compatibility, commands/results,
  profile namespace, rollout/rollback, direct-main delivery note, and remaining manual/unverified
  evidence. This is required integration evidence and cannot start from a behavior test; validate
  every referenced commit exists remotely.
- [x] 5.10 Update workspace README/DEVELOPMENT/integration documentation to say this one executable
  profile exists while `ws`, manifest, lock, general profile generation, and workspace pins remain
  absent. Documentation cannot start from a behavior test; verify no target architecture is
  mislabeled implemented.
- [x] 5.11 Run all available workspace static checks, the shell profile tests, OpenSpec strict
  validation, secret scan, and baseline cleanliness checks; inspect the final diff and evidence for
  local paths, tokens, fixture leaks, or claims unsupported by observed output.

## 6. Archive, publish, and cleanup

- [x] 6.1 Sync all three fleet delta specs into the workspace main specs and verify every added
  requirement/scenario matches before archiving; this is OpenSpec lifecycle work and cannot start
  from a behavior test.
- [x] 6.2 Mark 1.1-1.4 only after their remote-main containment and evidence conditions hold, then
  archive `add-operational-status-workspace-integration` with every task checked and run
  `openspec validate --archived`.
- [x] 6.3 Commit only the workspace profile, tests, changeset evidence, documentation, and synced
  OpenSpec artifacts; integrate `codex/web-012-operational-status` into workspace `main`, push
  `main`, and verify remote containment before the archive-only follow-up.
- [x] 6.4 From verified clean integration contexts, remove the Contracts, Platform, and Web task
  worktrees whose heads are reachable from remote `main`, then delete their merged local branches
  with `git branch -d`; leave unrelated worktrees and the user's dirty Web checkout intact. Remove
  this workspace worktree and branch only after its archive-only commit is published, because a
  running worktree cannot delete itself.
- [x] 6.5 Re-check all four remotes, baseline statuses, hosted checks that are actually available,
  existing archived OpenSpec validation, and absence of WEB-012 Compose resources; after moving
  this change, validate the new archive before its commit. Hand off local gates, composed-profile
  proof, hosted evidence, and any remaining device/manual/deployment gap as separate facts.
