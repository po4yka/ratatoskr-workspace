## Why

Instagram currently reports every outbox fact as delivered through a logging-only transport and then marks it published even though no broker or consumer received it. The durable record is therefore erased from the retry lane while Platform's NATS policy simultaneously forbids the Instagram identity from publishing the three event subjects it owns.

## What Changes

- Replace Instagram's logging-only transport with a real JetStream publisher that derives one allowlisted subject from the stored typed event, waits for the server publish acknowledgement, and returns success only after that acknowledgement.
- Keep an outbox row unpublished when the broker is absent, rejects the identity, refuses the subject, times out, or fails to acknowledge; retry the identical stored envelope according to the existing durable retry policy.
- Do not start a delivery loop when no bus is configured. The service retains durable outbox rows and reports the disabled/unavailable lane instead of claiming delivery through logs.
- Reuse the configured credential-free NATS endpoint and optional seed-file credential without exposing the seed, envelope body, owner, note, or provider content in logs or metrics.
- Add a bounded operator repair command for the deployment cutover: while the old service is stopped, every SocialSource row whose `published_at` was set by the only previously shipped transport is transactionally returned to the unpublished retry lane. Repeating the command before the real publisher starts changes zero additional rows.
- Expand Platform's Instagram NKey policy with only `evt.social.source.captured.v1`, `evt.social.source.updated.v1`, and `evt.social.source.removed.v1`; prove those publishes succeed and commands, foreign facts, consumer creation, and direct event subscriptions remain denied.
- Add a real-broker integration profile/test that writes an Instagram outbox fact, observes it in `ratatoskr_events`, verifies the stored bytes and subject, and proves `published_at` changes only after JetStream acknowledgement.
- Record the previously false completion as an incident in IG-014 and update documentation so outbox commit, broker acknowledgement, Knowledge consumption, and live deployment remain distinct evidence boundaries.

## Capabilities

### New Capabilities

- `instagram-social-event-delivery`: Least-privilege, acknowledged delivery of Instagram's durable SocialSource facts from its transactional outbox into the Platform-owned event stream.

### Modified Capabilities

None.

## Impact

Dependency and publication order is: existing `ratatoskr-contracts` event types remain unchanged; `ratatoskr-platform` expands only the Instagram deployment identity and must merge first; `ratatoskr-instagram` replaces the false transport and must merge second; `ratatoskr-workspace` adds IG-014 coordination and integration evidence last. No simultaneous cutover is required: publishing still fails closed until both ACL and producer are deployed, and the outbox retains the events meanwhile.

Affected Platform surfaces are `deploy/nats/ratatoskr.conf`, its NATS permission/deployment tests, and deployment documentation. Affected Instagram surfaces are service startup/bus wiring, the concrete event transport, outbox selection/retry tests, telemetry, and operator documentation. The workspace owns the cross-repository changeset and composed broker proof.

Event payload contracts, Instagram capture/normalization logic, database schema, Knowledge's currently missing social-event consumer, provider APIs, production credentials, and production deployment stay outside this change. The historical repair uses the existing outbox columns and adds no migration file, schema version, compatibility path, or durable marker.

Rollback order is Instagram first, then Platform: restore the prior producer binary while leaving the narrow publish grants harmlessly present, then remove the three grants if desired. Already acknowledged JetStream facts are immutable delivery evidence and are not deleted during rollback; unpublished outbox rows remain available to a corrected forward deployment.
