## Why

Telegram can accept and project user interactions, but the fleet still has no verified path from the canonical notification fact to a preference-filtered Telegram message, and the single-host contract allocates no ports for the Telegram roles. Plan item 10 closes that fleet-visible gap and records an executable composed proof without operating the frozen deployment target.

## What Changes

- Reserve single-host ports `8182` for the Telegram webhook listener, `9467` for the webhook operator listener, and `9468` for the dispatcher operator listener in the workspace deployment contract.
- Define the fleet-visible route `evt.platform.notification.raised.v1` from the existing `ratatoskr-notification-contracts` event through a Platform-pre-provisioned, least-privilege durable Telegram consumer; producer hints remain advisory and Telegram remains authoritative for preferences, quiet hours, deduplication, and channel choice.
- Add a task-namespaced composed profile and smoke that publishes a synthetic notification and demonstrates the existing plan-item-5 article flow from Telegram webhook admission through Platform operation progress to the final Bot API projection.
- Record dependency order, compatibility, rollback, privacy boundaries, exact child/workspace revisions, and the distinction between composed evidence and live-host deployment evidence.
- Keep channel digests, producer-side notification adoption, LLM model controls, live webhook registration, and live deployment outside this change.

## Capabilities

### New Capabilities

- `telegram-notification-integration`: Fleet-visible notification routing, ownership, compatibility, and composed delivery evidence.
- `single-host-telegram-deployment`: Canonical single-host port allocation and deploy-profile compatibility for the two Telegram runtime roles.

### Modified Capabilities

(none)

## Impact

- Repository order: the already-published `ratatoskr-contracts` payload remains unchanged; `ratatoskr-platform` adds the fixed consumer topology and least-privilege NATS identity; `ratatoskr-telegram` implements the consumer and deployment artifacts against it; `ratatoskr-workspace` then updates the canonical port contract, composed profile, changeset evidence, and compatible snapshot.
- `ratatoskr-platform`: pre-provisions `ratatoskr_telegram_notifications` with the exact filter and supplies a Telegram NKey permission stanza that cannot create arbitrary consumers or publish domain messages.
- `ratatoskr-telegram`: consumes `evt.platform.notification.raised.v1`, enforces preferences, supplies two systemd units and recovery/runbook tooling, and exposes no new public domain API.
- `ratatoskr-workspace`: updates `docs/DEPLOYMENT_TARGET.md`, adds the namespaced integration profile, records `TG-010`, and verifies exact child revisions without editing pinned child checkouts.
- Compatibility is additive: producers may continue emitting nothing, an idle pre-provisioned durable has no delivery side effects, and Telegram can start after Platform topology is ready without changing any producer.
- Rollback before Telegram deployment leaves or removes the empty durable explicitly. After notifications are consumed, stop Telegram before revoking its NKey, roll back the binaries, and retain both the durable cursor and Telegram preference/deduplication rows so replay cannot create duplicate delivery.
