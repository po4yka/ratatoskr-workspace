## Why

Round 1 of changeset XR-021 fixed the first set of cross-repository defects. Independent verifiers then traced each flow through the pushed code and found a second set that round 1 had hidden or created: Edge routed to listeners that no service bound (the ChatGPT receipt and Knowledge's library routes lived on operator ports, and the workspace profiles hid it by overloading those ports), any identity allowed to publish `evt.platform.operation.reported.v1` could terminate another tenant's operation, a broker limit of 1 MiB refused every large archive and document fact, a transient outage dead-lettered extractor rows for good, a digest run could stay `running` for 24 hours, tenant deletion left the channel recap tables behind, and two actors could race on one content-addressed blob. This change records, in the store the whole fleet reads, the behaviour that is true at those boundaries after round 2, adds the two workspace checks that stop the first and the last kind of drift, makes every integration profile run under the deployed NATS authorization, and advances the pins to the round 2 heads.

## What Changes

- Add requirements to `fleet-bus-topology` (broker `max_payload` and the outbox failure classes, publisher health in readiness, the operator examples and the seed variable table, every Edge upstream bound by its owner, profiles under the deployed ACL, durable names that agree), `ai-archive-receipt-binding` (dedicated receipt listeners, exact `application/zip`, the `ai_archive.facts.too_large` warning), `channel-digest-chain` (run deadline, attributable rejects, bounded redelivery, intake bounds and the page-size clamp, scheduled language, recap tenant deletion, the recap provider default, the schedule owner check), `blob-references` (one registration and erasure lock protocol) and `social-capture-lifecycle` (provider deletion removes the owner's source, provider permalink hosts).
- Add a new capability `operation-report-authority`: a report is applied only when its tenant and producer match the operation.
- Add an added requirement to `repository-analysis-intake`: GitHub originates analysis requests at runtime and bounds every provider call.
- Add `edge_upstreams.rs` and `bus_durables.rs` to the harness, and move the bind matcher of `port_allocation.rs` into a shared support module.
- Add `integration/lib/nats-conf.sh`: every integration profile renders its NATS file from Platform's deployed `ratatoskr.conf` instead of writing its own; the XPA-020, TG-010 and TG-011 profiles use it and the new dedicated listeners.
- Advance fourteen pins to the round 2 heads, regenerate `workspace.lock`, and record round 2 in the changeset together with the native smoke results exactly as reported.

## Capabilities

### New Capabilities

- `operation-report-authority`: who may report progress for which operation.

### Modified Capabilities

- `fleet-bus-topology`, `ai-archive-receipt-binding`, `channel-digest-chain` and `social-capture-lifecycle` are introduced by the open change `xr-021-fleet-cross-repo-fixes`; this change adds requirements to them and must be archived after it.
- `blob-references` and `repository-analysis-intake` are in `openspec/specs/`; this change adds one requirement to each.

## Impact

Repositories, in dependency order: `ratatoskr-contracts` first (a test that pins the registry audiences nothing wires, `5426cf3`), then the thirteen wave-2 repositories that are independent of one another (`platform`, `extractor`, `knowledge`, `channel-digests`, `github`, `vault`, `x`, `instagram`, `threads`, `chatgpt`, `claude`, `telegram`, `browser-extension`), then `ratatoskr-workspace`, which merges last because its new tests read the pinned submodules and stay red between the first child merge and the pin advance. `export-agent`, `mobile` and `web` have no round 2 work.

Hard breaks, named in the owning commits: the Knowledge operator routes (`/v1/capabilities`, `/internal/search`, `/internal/user-content/*`) moved from the operator listener to a new API listener; the ChatGPT receipt moved off its operator listener onto its own; the extractor outbox no longer dead-letters transient failures; the NATS file sets `max_payload: 8MB`; channel-digests documents Knowledge at 8091.

Rollback: stop the services, restore the previous NATS configuration, reload NATS, restart Edge, then revert the workspace pin commit. Provisioned durables are never deleted, because their cursors are the only record of what was consumed. Nothing has shipped from this snapshot and the host is frozen, so there is no deployment to roll back.

Outside this change: anything under `repos/`, host provisioning, release tags, and the exclusions listed in the changeset (fleet-wide account erasure transport, image OCR, live provider calls, the vault, social and ai-archive domain listeners, the Knowledge completion fact consumers, and the others recorded there).
