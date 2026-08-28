## 1. Implementation by repository

- [x] 1.1 `ratatoskr-knowledge`: merge the additive search identity/effective-state/filter and read-state-only mutation change after its repository gate passes; direct authorized `main` merge: `16df57993825a42680bc922b45c2742a04964ea2`, verified on `origin/main`.
- [x] 1.2 `ratatoskr-platform`: after 1.1, merge the authenticated library façade, OpenAPI, safe Knowledge client, and capability names after its repository gate passes; direct authorized `main` merge: `070b718238c4e6e45a5b7fc08ebe719ed5374e33`, verified on `origin/main` after Knowledge.
- [x] 1.3 `ratatoskr-telegram`: after 1.2, merge the command adapter, opaque read authority, renderer, and typed Platform client after its repository gate passes; direct authorized `main` merge: `73c5ed2100bd2aa5b11bfbf6f57551ea45e828af`, verified on `origin/main` after Platform.
- [x] 1.4 `ratatoskr-workspace`: after composed verification and evidence updates, merge this coordination/integration change; direct authorized evidence merge `b275431f7a4332aa4d4c415a7584dd4971787b46` and all three child merge commits were verified on their remote default branches.

## 2. Workspace coordination and static profile

- [x] 2.1 Create `changesets/TG-011-search-read-state.yaml` naming Knowledge -> Platform -> Telegram -> Workspace dependency order, compatibility, schema/API impact, rollback, security/privacy, and required checks; cannot start from a failing behavior test because this is the required coordination manifest, so verify it with the repository's changeset/schema validator.
- [x] 2.2 RED: add `integration/tests/telegram_library_profile_test.sh::profile_declares_exact_services_ports_healthchecks_and_task_namespace`, run it before adding the profile, and confirm it fails because `integration/compose/telegram-library.yaml`, its fixtures, and runner do not exist.
- [x] 2.3 GREEN: add the task-namespaced Knowledge + Platform + Telegram + synthetic Bot API composed profile, deterministic two-tenant PostgreSQL fixtures, and exact teardown/inventory checks; rerun `telegram_library_profile_test.sh` and verify every structural assertion passes.

## 3. Composed behavior evidence

- [x] 3.1 RED replay: with the static test present, temporarily withhold `integration/run-telegram-library.sh` and confirm `telegram_library_profile_test.sh` fails with the exact missing-runner diagnostic. This replay verifies the guard but does not claim it preceded the implementation; the original combined RED stopped earlier on the missing profile.
- [x] 3.2 GREEN: implement `integration/run-telegram-library.sh` to seed one read and two unread owner items plus foreign fixtures, drive `/search`, `/unread`, a captured `/read` token, replay/foreign-token refusal, post-read `/unread`, and Knowledge-unavailable capability behavior; rerun the static test and verify its assertions pass.
- [x] 3.3 Run the composed profile against exact child revisions and record `integration/evidence/TG-011.md` with image IDs, compose digest, commands, observed Bot API payloads, Knowledge state/favorite checks, capability disappearance/recovery, exact cleanup, and the explicit synthetic-provider/not-live-Telegram boundary; verify the evidence validator and before/after Docker inventory are green.

## 4. Contract and fleet gate

- [x] 4.1 Update `integration/README.md`, workspace test documentation, and pin/lock metadata for TG-011; cannot start from a failing behavior test because these are documentation/generated coordination artifacts, so verify all referenced paths and commands with the static integration tests and workspace lock check.
- [x] 4.2 Run the complete workspace gate plus strict validation of this change and every affected repository's archived/current OpenSpec state; verify all commands in the workspace gate finish successfully before checking any task complete.
