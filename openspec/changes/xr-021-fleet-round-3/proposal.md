## Why

Rounds 1 and 2 of changeset XR-021 are merged. Round 2's native smokes and the independent verifiers then found a third set of defects at the boundaries between repositories: every non-Edge NATS identity could subscribe to the shared `_INBOX.>` namespace and read the JetStream deliveries of every other service, a report for an Instagram capture was accepted from X, a receiver's refusal left an upload operation `accepted` for an hour while its 401 made the export agent drop a valid pairing, Claude could not receive anything until an operator inserted an account row by hand, ChatGPT could never reach `succeeded`, Knowledge dead-lettered a deletion tombstone after five deliveries and indexed internal ids and prompt scaffold as searchable text, channel-digests reported a truncated acquisition as an empty success and logged nothing, the examples named PostgreSQL roles and databases that nothing created, the Telegram assertion key could only be made with an openssl and xxd snippet that macOS does not support, and ChatGPT and Claude pinned a different contracts revision from everyone else. This change records, in the store the whole fleet reads, the behaviour that is true at those boundaries after round 3, adds the workspace checks that stop each kind of drift, puts the last Docker profile under the deployed ACL, writes the native smoke harness that round 2 specified and never built, and advances the pins to the round 3 heads.

## What Changes

- Add requirements to `fleet-bus-topology` (a per-service inbox prefix for every non-Edge identity and one `custom_inbox_prefix` call on every connection; Knowledge's ack-wait keys state the values Edge fixes), `ai-archive-receipt-binding` (a user a receiver does not map is refused with 403 and the refused delivery ends the operation; an upstream 401 never reaches a device; both receivers create the account on first mapped receipt; a duplicate of a failed import is reported failed), `channel-digest-chain` (an incomplete acquisition is reported as incomplete; an accepted run is queued until acquisition starts; both binaries log) and `social-capture-lifecycle` (one permalink grammar table; X can trust an operator-supplied CA; a terminal capture is not a pending retry).
- Modify `operation-report-authority`: a report must come from the lane the operation was dispatched to, recorded on the operation, and the cross-lane residual risk is closed.
- Add the capabilities `ai-archive-import-completeness` (a gap names something the export contained and the importer could not store; deleting an export keeps the records a retained export holds), `postgres-provisioning` (one database, one role and one checked-in file per service, in a fixed order) and `assertion-key-procedure` (the Telegram webhook creates the assertion key and derives its public half).
- Add four checks to the harness (`contracts_pin.rs`, `postgres_roles.rs`, `shared_secrets.rs`, and the inbox checks of `bus_acl.rs` with twelve vendored copies) and record what each cannot see in `docs/QUALITY_GATES.md`.
- Put `web-operational` under the deployed ACL, add `no_unauthenticated_broker_test.sh`, take the Telegram assertion key from the webhook's command in both Telegram profiles, and mark `XPA-020.md` superseded.
- Add `integration/native/`: the Docker-free multi-service smoke harness (`run.sh`, flows F0 to F7, fixtures, fakes) and its contract test. None of its flows has been run through `run.sh` as committed.
- Update `docs/DEPLOYMENT_TARGET.md` (inbox prefixes, PostgreSQL provisioning order and roles, the production-port rule for smokes, the assertion-key procedure), advance fourteen pins to the round 3 heads, regenerate `workspace.lock`, and record round 3 in the changeset together with the native smoke results exactly as reported.

## Capabilities

### New Capabilities

- `ai-archive-import-completeness`: when an AI-archive import is complete, and what survives a deletion.
- `postgres-provisioning`: how the shared database and the per-service roles are provisioned.
- `assertion-key-procedure`: how the Telegram assertion signing key is created and published to Edge.

### Modified Capabilities

- `fleet-bus-topology`, `ai-archive-receipt-binding`, `channel-digest-chain`, `social-capture-lifecycle` and `operation-report-authority` are introduced by the open changes `xr-021-fleet-cross-repo-fixes` and `xr-021-fleet-round-2`; this change adds to or modifies them and must be archived after both.

## Impact

Repositories, in dependency order: the contracts repository has no round 3 commit (ChatGPT and Claude move their dependency on it back to `ad16855`, see the breaks), then the thirteen repositories that changed (`platform`, `extractor`, `knowledge`, `channel-digests`, `github`, `vault`, `x`, `instagram`, `threads`, `chatgpt`, `claude`, `telegram`, `browser-extension`) and `export-agent`, then `ratatoskr-workspace`, which merges last because its new checks read the pinned submodules and stay red between the first child merge and the pin advance. `mobile` and `web` have no round 3 work.

Hard breaks, named in the owning commits: a service built before this round times out under the new ACL because it still replies on the shared inbox, so NATS is reloaded and the services of one snapshot are deployed together; `platform_operations::accept` gained a `reporter` parameter and `operations.operations` a `reporter` column; a Platform user a receiver does not map now gets 403 and an upstream 401 becomes a 502 at Edge; ChatGPT no longer produces the three `*_not_observed` gaps; Knowledge refuses ack-wait values other than 120 and 30; a tombstone that cannot succeed is rejected with a closed class where it used to retry five times; an accepted on-demand digest run is reported `queued` until acquisition starts; the example databases changed; ChatGPT and Claude return to the contracts revision `ad16855`.

Rollback: stop the services, restore the previous NATS configuration, reload NATS, restart Edge, then revert the workspace pin commit. Provisioned durables are never deleted. Nothing has shipped from this snapshot and the host is frozen, so there is no deployment to roll back.

Outside this change: anything under `repos/`, host provisioning, release tags, a CI job that runs the native smoke, and the exclusions listed in the changeset (a notification producer, the fleet-wide account-erasure transport, image OCR, live provider calls, the dormant X bookmark lane, a consumer-lag alert, unit files for services that ship only an example, pagination cursors, and the others recorded there).
