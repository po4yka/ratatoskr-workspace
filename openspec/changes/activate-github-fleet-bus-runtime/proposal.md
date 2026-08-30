## Why

GitHub Catalog persists commands, events, and inbox handlers, but its production process never connects to the fleet bus, publishes the outbox, consumes any durable, runs due analysis dispatch, or reconciles dirty backup policy. The process can therefore report ready while every cross-service workflow is permanently stalled.

## What Changes

- **BREAKING**: make `github_catalog.outbox_events.subject` and `inbox_events.subject` store the exact transport subject, including the `cmd.` or `evt.` class prefix, and make outbox payloads the complete final wire envelope rather than an unclassified domain payload. All current call sites and tests change together; no compatibility path or second version is retained.
- Provision four fixed GitHub durables for scheduled sync commands, Knowledge completion facts, Knowledge failure facts, and Vault policy acknowledgements.
- Add a least-privilege GitHub NKey that may fetch and acknowledge only those durables and may publish only the current Knowledge analysis-request and Vault desired-policy subjects.
- Add validated, redacted GitHub bus configuration and connect the service runtime to the Platform-owned streams and durables without granting topology creation authority.
- Run bounded supervised workers for transactional outbox publication, all four inbound deliveries, due repository-analysis dispatch, and trailing backup-policy reconciliation.
- Repair sync-command recovery so a provider or process failure after the durable inbox claim remains retryable instead of being misclassified as a completed duplicate.
- Couple JetStream acknowledgements to committed inbox state, preserve deterministic message IDs on publish, record terminal invalid deliveries without poison redelivery, and leave transient failures available for bounded redelivery.
- Make readiness require the expected bus topology and live worker supervisor; expose bounded lag, retry, duplicate, terminal-rejection, and dead-letter telemetry.
- Add the GitHub systemd role and configuration example needed to run the bus-enabled process under the accepted single-host deployment boundary.
- Add a composed fixture profile proving scheduled sync, outbox publication, Knowledge/Vault feedback, restart recovery, and redaction without claiming live GitHub, Knowledge, Vault, or production-host acceptance.
- Record coordinated change `GHB-017` and advance workspace pins only after child commits and integration evidence are complete.

## Capabilities

### New Capabilities

- `github-fleet-bus-runtime`: Defines GitHub Catalog's exact fleet-bus subjects, fixed durable topology, least-privilege identity, transactional delivery semantics, supervised workers, truthful readiness, deployment role, and cross-boundary integration proof.

### Modified Capabilities

None.

## Impact

Repositories are changed and merged in this dependency order:

1. `ratatoskr-platform` merges first, provisioning GitHub's fixed durables and least-privilege identity on the existing command and event streams.
2. `ratatoskr-github` merges second, adopting that topology, changing its current schema in place, and activating its publisher, consumers, due workers, readiness, telemetry, and systemd role.
3. `ratatoskr-workspace` merges last, adding changeset `GHB-017`, the integration profile and evidence, and the verified compatible child pins.

No shared payload contract changes are required. Scheduled sync continues to carry the canonical command envelope; Knowledge terminal facts and Vault acknowledgements continue to carry canonical event envelopes. The existing repository-analysis request contract remains an event describing GitHub's durable request for Knowledge admission, while desired backup policy is carried as the payload of a canonical Vault command envelope. The single current envelope major and subject versions remain unchanged.

The change affects Platform JetStream topology and deployment permissions; GitHub Cargo dependencies, schema, configuration, event adapters, service supervision, readiness, metrics, deployment artifacts, and documentation; and workspace integration fixtures, evidence, changeset, lockfile, and pins.

Outside this change are live provider synchronization, implementation or deployment of Knowledge and Vault consumers, changing analysis or backup-policy payload semantics, OAuth, production credentials, production-host operation, and proof that a downstream analysis or backup actually completed. Fixture counterparts verify GitHub's transport boundary without pretending to be those deployables.

Rollback disables Platform's GitHub schedules and stops the GitHub bus-enabled unit before returning the GitHub binary, unit configuration, and workspace pins to their previous commits. Outbox/inbox rows and all four durable cursors remain intact so rollback does not discard accepted work. The Platform identity and durables may remain provisioned but unused; deleting or resetting them is an explicit later operator action, never automatic rollback.
