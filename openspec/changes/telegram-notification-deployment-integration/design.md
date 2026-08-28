## Context

See `proposal.md` for motivation. The workspace is the fleet contract and integration owner; it does not implement Telegram policy or Platform stream topology. Product repositories remain independently versioned, and their source-of-truth checkouts are read-only during cross-repository work. The accepted single-host profile is frozen: this change can reserve ports and validate artifacts, but cannot install units, alter the firewall, register a webhook, or operate the host.

The notification payload already exists in `ratatoskr-contracts`. Platform owns the `ratatoskr_events` stream and NATS authorization. Telegram owns recipient/chat authorization, preferences, quiet hours, deduplication, and Bot API delivery. The composed proof must use real product binaries at exact task revisions but synthetic identities and provider responses.

## Goals / Non-Goals

**Goals:**

- Preserve an explicit contracts → Platform → Telegram → integration → workspace-pins order.
- Prove the existing article interaction flow and the new notification path in one reproducible, task-namespaced profile.
- Make the port/deployment cross-check executable without requiring systemd as PID 1.
- Record evidence with exact revision and environment boundaries.

**Non-Goals:**

- Live host deployment, public DNS/tunnel/firewall changes, webhook registration, or real Telegram delivery.
- New producer adoption or synthetic evidence presented as a live domain-provider fact.
- Channel digests, schedule ownership, or model-selection controls.
- Editing pinned child repositories from the workspace worktree.

## Decisions

### 1. The changeset carries three writable lanes and one immutable contract dependency

`TG-010` records the existing Contracts revision without changing it, then Platform's consumer topology branch, Telegram's notification/deployment branch, and finally the workspace coordination branch. Each writable repository is implemented, gated, committed, and pushed before its exact revision is recorded in the next dependent lane.

Treating Platform provisioning as undocumented host setup was rejected because Telegram's least-privilege identity cannot create its own consumer. Letting Telegram hold broad JetStream authority was rejected at the security boundary.

### 2. One canonical subject maps to one Platform-owned durable

The cross-repository route is fixed as:

`platform.notification.raised.v1` → `evt.platform.notification.raised.v1` → `ratatoskr_events` / `ratatoskr_telegram_notifications` → Telegram preference decision → durable outbound sender.

The producer's quiet-hours fields remain hints. Telegram is the final policy authority because it owns the destination and user/channel preferences. No Telegram-specific producer command or direct Bot API path is added.

### 3. The TG-010 profile uses actual Platform and Telegram binaries with bounded fakes

The profile composes PostgreSQL 17 databases created from each repository's current `schema.sql`, JetStream, the relevant Platform roles, Telegram webhook/dispatcher, and a fake Bot API server. A small synthetic domain driver publishes only the operation progress facts needed to complete the already-accepted article flow; a synthetic notification publisher emits the existing canonical contract.

The smoke submits a synthetic `/article https://example.invalid/tg-010` update, observes Platform operation creation and final Telegram projection, then exercises one enabled notification and one disabled-class suppression. It asserts database rows and captured outbound calls rather than matching logs.

Replacing product binaries with a fixture was rejected because it would not prove workspace integration. Calling a real article extractor or Telegram was rejected because those providers are outside the acceptance boundary and would introduce credentials and nondeterminism.

### 4. Isolation is enforced by project name, ephemeral ports, and owned paths

The runner derives a validated Compose project name containing `tg010`, publishes public/operator ports to ephemeral loopback host ports, allocates unique database names and NATS resources inside the project, and writes evidence to a newly created TG-010 directory. Cleanup always uses the exact project/profile pair and never broad Docker filters or shared names.

This follows the existing `web-operational` profile pattern while keeping its resources independent. Fixed host ports inside service containers still match `8182`, `9467`, and `9468`; dynamic host mappings avoid collisions on development machines.

### 5. Deployment validation compares repositories, not copied constants

A workspace test receives an explicit Telegram source path/revision, parses its two unit/environment artifacts, and compares their public/operator ports, role separation, stop timeout, resource ceilings, logging path, secret-file boundary, and exposure policy against `docs/DEPLOYMENT_TARGET.md`. It fails when the source revision differs from the changeset.

Copying unit values into a workspace fixture was rejected because the fixture could drift while both local tests remained green.

### 6. Evidence is generated, reviewed, then summarized without secrets

The runner records Compose configuration hash, product commit SHAs, image IDs, test timestamps, captured safe Bot API request summaries, database decision counts, and final container state. The committed changeset/evidence summary names the executed commands and exact revisions. Raw credentials, raw update bodies, message content, and transient database volumes are excluded.

Composed success is labelled separately from hosted CI and live deployment. Synthetic publisher evidence is explicitly not producer-adoption evidence.

## Risks / Trade-offs

- **[Building Platform and Telegram makes the profile slow on ARM64]** → Reuse BuildKit caches, cap build parallelism through `build-gate`, and keep only the necessary runtime roles in this profile.
- **[A synthetic progress publisher drifts from the canonical envelope]** → Compile it against the pinned contract crate or validate its fixture with the repository contract validator before Compose starts.
- **[Dynamic host ports obscure the production allocation]** → Keep canonical ports inside containers and validate Telegram units directly against the workspace table.
- **[Cleanup could affect unrelated Docker resources]** → Require a validated `tg010` project name and exact Compose file; test teardown against an unrelated sentinel resource.
- **[A product branch changes after evidence is recorded]** → Require clean exact SHAs, compare them to `TG-010`, and refuse the runner on a mismatch.

## Migration Plan

1. Verify the unchanged notification contract revision and publish the Platform topology/NATS identity change.
2. Record Platform's exact green commit in `TG-010`, then implement and publish Telegram against that topology.
3. Record Telegram's exact green commit, add the workspace port allocation and TG-010 profile, and run static isolation tests.
4. Run the composed smoke from an empty namespace through `build-gate`, review the generated evidence, and record exact hashes and outcomes.
5. Run the full workspace gate, commit and push the workspace revision, then advance compatible repository pins/snapshot as the final coordination step.
6. Rollback removes only the TG-010 workspace/profile changes before live deployment. After a consumer has processed events, stop Telegram before revoking its NKey and preserve the durable cursor plus Telegram deduplication rows. No rollback step operates the frozen host.
