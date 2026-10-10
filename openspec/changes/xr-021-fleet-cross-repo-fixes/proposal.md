## Why

Fifteen repositories exchange messages over one NATS broker and a handful of loopback HTTP routes, and the agreements between them were written down nowhere that more than one of them could read. The result was fleet-wide drift: a capture command with two envelopes, outbox rows that stored bare payloads and could not be published, a NATS file that gave the extractor `evt.>` and `$JS.API.>`, three services that bound the same operator port, an archive upload that Platform sent as `PUT` to receivers that accepted only `POST`, and social captures that were acknowledged and never reported. XR-021 fixes those in the repositories that own them. This change records, in the store the whole fleet can read, the behaviour that is true at the boundaries after those fixes, adds the two workspace checks that stop the port table and the bus permissions from drifting again, and advances the pins to the fixed commits.

## What Changes

- Add five capability specs and one added requirement, written from the contract sections of changeset XR-021 and checkable from outside any one repository: `ai-archive-receipt-binding`, `channel-digest-chain`, `fleet-bus-topology`, `social-capture-lifecycle`, `content-capture-command`, and a read-only cross-service blob read in `blob-references`.
- Make the `## Ports` table of `docs/DEPLOYMENT_TARGET.md` the complete allocation: the new rows, the four moved operator ports, the NATS monitoring port, the Telegram blob root and its group.
- Add `port_allocation.rs` to the harness: the table has no duplicate port and names every documented listener, every bind in a repository's deploy examples is allocated, and no two listeners claim one port.
- Add `bus_acl.rs` to the harness: Platform's `ratatoskr.conf` holds exactly the thirteen identities, every service-carried copy equals its stanza, and the permission invariants hold.
- Record the changeset in `changesets/XR-021-fleet-cross-repo-fixes.yaml`.
- Advance fifteen pins to the pushed XR-021 commits and regenerate `workspace.lock`. `web` and `mobile` are unchanged.
- Add the `vault` to `github` dependency edge to `workspace.toml`. Four other edges the fixes introduce close cycles and are recorded in the design instead.

## Capabilities

### New Capabilities

- `ai-archive-receipt-binding`: the loopback request Platform sends to the ChatGPT and Claude receivers, the capability probe, the incomplete-import reporting rule, the chunk and archive size limits.
- `channel-digest-chain`: the manifest handshake between Knowledge and the channel-digests API, the read views, the schedule registration command, the operation-report vocabulary.
- `fleet-bus-topology`: the subject table, the outbox and relay rules every publisher follows, the thirteen NATS identities, the fixed durables.
- `social-capture-lifecycle`: queued, preserved and unavailable reports for explicit social captures, the retry policy, exactly one terminal report, tenant isolation.
- `content-capture-command`: the typed `content.capture.requested.v1` envelope, the url or blob payload, and `POST /v1/captures/blobs`.

### Modified Capabilities

- `blob-references`: a consumer may read a producer's blob root read-only on the single-host target.

## Impact

Repositories, in dependency order: `ratatoskr-contracts` merged first (CONTRACTS_SHA `ad16855c4e7f3d52cd118274faa3b8f3ab4da576`); then the fourteen wave-2 repositories, which are independent of one another: `platform`, `extractor`, `knowledge`, `channel-digests`, `github`, `vault`, `x`, `instagram`, `threads`, `chatgpt`, `claude`, `telegram`, `browser-extension`, `export-agent`; then `ratatoskr-workspace`, which merges last because its tests read the pinned submodules and stay red between the first child merge and the pin advance. `web` and `mobile` are read only and unchanged.

Outside this change: any edit under `repos/`, production host provisioning (nkeys, groups, credentials), release tags, converting `docs/REQUIREMENTS.md` or its siblings into specs, and the follow-ups named in the design.

Hard breaks, named in the owning commits of the child repositories and in the changeset: `content.capture.requested.v1` moves to the typed envelope in Platform, the extractor and X together; four operator listener defaults move; several services refuse to start with a bus configured and no way to finish the work; schema definitions change in place.

Rollback: stop the services, restore the previous NATS configuration, reload NATS, restart Edge, then revert the workspace pin commit. Provisioned durables are never deleted, because their cursors are the only record of what was consumed. Nothing has shipped from this snapshot and the host is frozen, so there is no deployment to roll back.
