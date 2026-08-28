## 1. Implementation by repository

- [x] 1.1 `ratatoskr-platform`: apply and archive `provision-telegram-notification-consumer`, run its full gate, integrate its task branch into `main`, push `main`, and record the exact commit URL and green evidence in `TG-010` (the user-authorized direct integration replaces a pull-request link).
- [x] 1.2 `ratatoskr-telegram`: after the Platform revision is fixed, apply and archive `notifications-deployment-recovery-integration`, run its full gate, integrate its task branch into `main`, push `main`, and record the exact commit URL and green evidence in `TG-010` (the user-authorized direct integration replaces a pull-request link).
- [ ] 1.3 `ratatoskr-workspace`: after both child revisions are fixed, implement the port contract and composed profile below, run the workspace gate, archive this change, integrate the coordination branch into `main`, push `main`, and record the exact commit URL and green evidence in `TG-010`.

## 2. Port and deployment contract

- [x] 2.1 Add `telegram_units_match_workspace_port_and_supervision_contract` to `integration/tests/telegram_deployment_profile_test.sh`, pointing it at the exact Telegram revision and asserting `8182`, `9467`, `9468`, role exposure, `Type=exec`, `TimeoutStopSec=130s`, resource ceilings, NVMe logging, and secret-file references; run it and verify it fails because the workspace allocations are absent.
- [x] 2.2 Reserve the three Telegram ports in `docs/DEPLOYMENT_TARGET.md`, update the bounded monitoring/firewall examples without operating the host, and complete the cross-repository structural validator; verify `telegram_deployment_profile_test.sh` passes and reports no duplicate allocation.

## 3. Namespaced composed profile

- [x] 3.1 Add `integration/tests/telegram_notification_profile_test.sh` with `profile_is_task_namespaced_and_cleanup_is_exact`, asserting explicit Platform/Telegram source revisions, PostgreSQL 17, canonical internal ports/subject/durable, ephemeral loopback host mappings, synthetic-only fixtures, and an exact `tg010` teardown command; run it and verify it fails because the profile and runner do not exist.
- [x] 3.2 Add `integration/compose/telegram-notification.yaml`, bounded synthetic fixtures, and `integration/run-telegram-notification.sh`; verify the static profile test passes and `docker compose --project-name ratatoskr-tg010-structural --file integration/compose/telegram-notification.yaml config --quiet` succeeds.
- [x] 3.3 Extend the static profile test with `teardown_preserves_an_unrelated_sentinel`, using an unrelated disposable Compose resource and the runner's dry-run teardown plan; verify it fails until teardown is restricted to the exact TG-010 project/profile pair.
- [x] 3.4 Implement the guarded teardown/evidence trap in the runner and verify the sentinel test passes without broad Docker filters, shared volume names, or fixed development-host ports.

## 4. Article and notification smoke

- [x] 4.1 Add the bounded smoke assertions for `article_flow_reaches_final_projection`, `enabled_notification_is_sent_once`, `disabled_notification_is_suppressed`, and `duplicate_notification_is_not_sent_twice`; run the smoke against the pre-notification product revisions and verify it fails at the first missing observable notification decision rather than on fixture syntax or startup.
- [x] 4.2 Run the profile against the exact green Platform and Telegram task commits through `build-gate`; verify the article operation/request/final Bot API projection and all three notification assertions pass from empty PostgreSQL databases and a fresh JetStream namespace.
- [x] 4.3 Add `dispatcher_refuses_missing_or_mismatched_platform_durable` to the composed failure cases, run it with the durable removed and then foreign-filtered, and verify it fails until the profile exposes Telegram readiness as false in both cases.
- [x] 4.4 Wire the failure case to the shipped readiness surface and Platform provisioning order; verify the profile observes unready before provisioning and ready only after the exact durable exists.

## 5. Evidence and workspace gate

- [ ] 5.1 Add the generated TG-010 evidence summary with exact Contracts, Platform, Telegram, and workspace source revisions, Compose hash, image IDs, executed commands, safe decision/call counts, and explicit `hosted_ci`/`live_deployment` boundaries; configuration evidence cannot start from a failing behavior test, so verify it with the evidence schema/static checker and a secret-pattern scan.
- [x] 5.2 Update `integration/README.md`, `docs/TESTING.md`, and `TG-010` with the executable commands and observed evidence; documentation cannot start from a failing behavior test, so verify every command/path through the static profile tests and dry-run runner mode.
- [ ] 5.3 Run `openspec validate telegram-notification-deployment-integration --strict`, every workspace gate command from `docs/QUALITY_GATES.md`, and a final diff/credential scan; mark tasks complete only for observed runs and leave hosted CI/live deployment unclaimed unless separately verified.
