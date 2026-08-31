## Why

Ratatoskr Export Agent builds and packages, but its normal executable starts only a static menu-bar
shell: the implemented watcher, immutable archive store, journal, device authentication, upload
queue, operation polling, notifications, and reminders are never composed into a running workflow.
The service side is also not deployable as that workflow today because archive delivery is not
restart-resumable, the ChatGPT and Claude receipt listeners are not wired into the single-host
Platform gateway, and their terminal operation reports cannot traverse the secured fleet bus.

## What Changes

- Assemble one long-lived, app-owned Export Agent runtime that restores user-approved folders and a
  paired Platform identity, detects stable exports, classifies and preserves their exact bytes,
  uploads them through the matching provider route, polls the bound operation, and projects truthful
  terminal status through the menu, history, diagnostics, reminders, and private notifications.
- Make each archive journal entry own its provider, processing state, operation binding, and
  resumable transfer checkpoint so mixed ChatGPT and Claude exports route independently and a crash
  or network failure resumes the same operation without a second prepare or duplicate import.
- Complete onboarding and operations UI for Platform endpoint configuration, pair/re-pair/revoke,
  folder selection, queue/history inspection, and retry/pause/cancel while keeping credentials only
  in Keychain and retaining every immutable local archive.
- Bind the existing chunked blob-transfer discipline, without changing its document shapes, to a
  Platform-owned AI archive operation, with
  authenticated open/chunk/status/finalize endpoints and an operation result that cannot become
  successful until the owning provider has accepted and processed the verified bytes.
- Configure Platform's single-host deployment with distinct loopback ChatGPT and Claude receipt
  routes, and give each archive producer a least-privilege secured-bus identity that can publish its
  terminal operation report but cannot read or write unrelated subjects.
- Make raw-receipt persistence a non-terminal stage: each provider runs its restart-safe parser and
  importer before emitting the one truthful terminal operation summary, including when exact archive
  bytes already exist from an earlier operation.
- Add an exact-revision, task-namespaced workspace profile that runs the packaged application against
  real Platform, ChatGPT, and Claude processes using synthetic archives and proves pairing,
  preservation, interruption/resume, duplicate suppression, terminal completeness, restart
  recovery, and isolated teardown.
- Publish the verified application through the existing fail-closed Developer ID/notarization path
  to the release page used by the manual update action, and record clean-machine acceptance. Owner
  Apple credentials remain an explicit external prerequisite; no artifact is called releasable or
  notarized without that evidence.

## Capabilities

### New Capabilities

- `export-agent-product-flow`: A user-operable macOS agent carries a selected provider export from
  stable local discovery through immutable preservation, authenticated delivery, backend import,
  durable terminal presentation, and restart recovery.
- `operation-bound-resumable-archive-transfer`: One Platform archive operation owns a chunked,
  resumable, digest-verified transfer and remains the sole idempotent correlation for retries and
  the provider's terminal report.
- `ai-archive-single-host-runtime`: Platform, ChatGPT, Claude, and the secured fleet bus expose the
  least-privilege loopback and event topology required for live AI archive imports.
- `export-agent-release-acceptance`: The exact integrated Export Agent commit is published at the
  manual-update destination only after fail-closed notarization and clean-machine product
  acceptance.

### Modified Capabilities

None. Existing `ai-archive-operation-summary` semantics already require truthful producer reports;
this change makes that contract reachable in the deployed product rather than changing its shape.
Provider-specific NATS ingress subjects are deployment authorization boundaries for that unchanged
EventEnvelope document, not new contract documents or API versions.

## Impact

Repository order is `ratatoskr-platform` first for public resumable endpoints, secure report intake,
gateway configuration, and deployment; `ratatoskr-chatgpt` and `ratatoskr-claude` next as independent
receivers/producers; `ratatoskr-export-agent` after the compatible server boundary exists; and
`ratatoskr-workspace` last for the exact-revision profile, changeset evidence, and compatible
snapshot. ChatGPT and Claude can be implemented in parallel after Platform's fixtures are fixed, but
Platform must merge before either production deployment and before Export Agent.

The change touches the public Platform AI archive HTTP binding, current database schema definitions,
OpenAPI and generated fixtures, secured NATS permissions, systemd/example configuration,
the Swift journal and application lifecycle, distribution workflow, and workspace integration
assets. It adds no provider-login automation, provider credentials, broad filesystem access,
privileged helper, automatic updater, second API/database version, migration, personal export, or
live deployment. `ratatoskr-contracts` is an unchanged exact-revision integration input because its
current blob-transfer and operation-summary documents already cover the required wire data;
Knowledge and the other ten product repositories remain outside the change.

Rollback stops new archive acceptance, restores the previous Platform and provider service units,
and rolls the workspace snapshot and manually installed application back to the last compatible
published set. It never deletes local archives, journal entries, server raw archives, or operation
history, and it does not revoke an already notarized ticket. Before any release is published there
is no user-install rollback; task-namespaced integration resources are removed by their exact
Compose project name only.
