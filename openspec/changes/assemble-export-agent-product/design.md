## Context

See proposal.md - Why. The child repositories already contain most isolated building blocks, but
their boundaries currently disagree in ways unit tests do not expose:

- the macOS executable instantiates only `NSApplication` and a static status item;
- the journal cannot route mixed providers, pairing identity cannot be rediscovered after restart,
  and a failed operation-bound PUT becomes permanently ineligible;
- the production upload bypasses the existing resumable blob-transfer state machine;
- Platform's public prepare/whole-file PUT routes exist in code but its deployment example has no
  ChatGPT or Claude gateway route;
- both provider services default to the same loopback port, connect anonymously to secured NATS,
  and emit a terminal partial result immediately after raw ZIP persistence instead of after import;
- the distribution workflow retains a temporary Actions artifact while the application's manual
  update action opens GitHub Releases, where no release exists.

The existing blob-transfer documents and `ai_archive_import_summary` shape are sufficient. This
change adds an operation-bound HTTP binding and runtime semantics, not a second contract version.
All database definitions remain version 1 and are edited in place. No existing development database
is migrated. Local archives are never deleted as part of resetting incompatible development state.

## Goals / Non-Goals

**Goals:**

- Make the normal packaged executable the composition root for the already specified local workflow.
- Preserve one durable correlation from local bytes through resumable transfer and terminal import.
- Make provider import, operation reporting, deployment, readiness, and secured-bus permissions
  coherent under one exact-revision system test.
- Separate local, repository CI, system integration, Apple notarization, GitHub publication, and
  clean-machine evidence.

**Non-Goals:**

- Provider login, browser automation, cookie reuse, archive parsing in the macOS client, or access
  outside user-selected folders.
- A privileged helper, always-running daemon, inbound macOS listener, automatic updater, or silent
  application replacement.
- A new blob-transfer document family, second API version, version negotiation, migration tool, or
  dual old/new runtime path.
- Production deployment, personal provider archives, or Apple-credential creation by automation.

## Decisions

### 1. Platform owns the resumable staging session; providers own accepted raw archives

Platform will replace the whole-file public PUT with operation-scoped open, chunk, status, and
finalize routes using the current `ratatoskr-blob-transfer-contracts` types. Its current schema gains
the transfer declaration, opaque session identity, received-chunk records, and lifecycle state keyed
by operation, owner, device, and provider. Chunk files live in a bounded private staging directory
and survive Edge restart. Finalization streams and hashes the ordered chunks, then forwards the
verified ZIP to the fixed loopback provider receipt route with Platform-injected correlation.
Successful provider acceptance seals the staging session; retention cleanup removes only staged
chunks after their operation-safe retention period, never provider raw storage or client archives.

This decision explicitly supersedes the byte-staging non-goal in the still-active
`accept-ai-archive-operations` design. That earlier change delivered the development-only direct
proxy path; XPA-020 replaces that path in place because restart-safe, same-operation resume requires
Platform to own durable staging behind the existing device authority boundary.

This keeps the public client behind Platform's device authority and prevents provider session tokens
from becoming client bearer credentials. Proxying a provider-owned resumable session was rejected:
it would require storing or exposing an upstream bearer token, coordinating two session expiries,
and recovering a distributed open operation. Retrying a single whole-file PUT was rejected because
large uploads restart from byte zero and the existing journal bug can permanently strand the bound
operation.

Preparation and transfer opening are one database transaction because Platform owns both records.
Idempotent prepare returns the original operation and session. If an open session expires before
finalization, Platform creates a replacement session under the same operation and immutable
declaration. It never creates a second operation for transfer recovery.

### 2. Provider raw receipt is progress; only completed import is terminal

Each provider receipt handler will validate Platform-injected operation, digest and size, publish
the raw ZIP atomically to its content-addressed store, and enqueue one durable import job in the same
transaction or equivalent crash-consistent boundary. The service runtime owns a restart-safe worker
that runs the existing parser/import pipeline and completeness calculation. Only that worker emits
the terminal Platform report. Raw persistence updates progress/stage but never reports
`partially_succeeded`.

If the digest already exists, the receipt associates the new Platform operation with the existing
archive/import result or schedules missing import work. It must still emit a terminal report for the
new operation. Returning a duplicate outcome before correlation was rejected because it leaves a
fresh Platform operation accepted forever. Treating `unknown` completeness as a terminal gap result
was rejected because absence of import evidence is not evidence of gaps.

### 3. Archive producers use separate least-privilege NATS identities

The Platform NATS configuration will define one credential for ChatGPT and one for Claude. ChatGPT
publishes operation reports only on `evt.ai-archive.chatgpt.operation.reported.v1`; Claude publishes
them only on `evt.ai-archive.claude.operation.reported.v1`. These are provider-scoped runtime ingress
subjects for the unchanged `platform.operation.reported.v1` EventEnvelope document; they do not add
a second wire-document version. Platform's durable consumer filters the two-subject family and
rejects any envelope whose producer does not match both the ingress subject and the provider bound
to the operation. Each provider may otherwise publish only its existing owned event subjects and
subscribe only to its explicitly owned command/event inputs. Neither may subscribe to the global
event wildcard or publish the other provider's ingress subject. Credentials are generated or
installed as root-readable deployment files, referenced by service configuration, and excluded
from repositories and logs. Anonymous fallback is removed.

Provider readiness includes database/raw-store health, import-worker liveness, and authenticated
report-publisher connectivity. Platform exposes each archive route's health through its existing
admin readiness projection and refuses preparation for only the unavailable provider; XPA-020 does
not invent a new public capability token. A route is available only when its configured loopback
target and report-consumer path are healthy. A best-effort anonymous publisher was rejected because
it turns terminal results into write-only outbox rows while the service still claims ready.

### 4. The macOS app has one actor-owned runtime and one durable state graph

`AgentCore` will gain a production runtime/coordinator API while the executable remains a thin AppKit
composition root. The runtime owns configuration and non-secret paired identity, bookmark handles,
the journal/archive store, watcher, candidate processor, upload scheduler, operation poller,
reminders, notifications, and their cancellation. UI controllers receive read-only async projections
and bounded action closures from that same runtime; they do not construct separate registries or
journals.

The current version-1 journal entry is changed in place to carry provider, classification decision,
archive policy, processing checkpoint, operation id, transfer-session checkpoint, retry control,
and last backend observation. The candidate path is:

1. stable-file observation;
2. bounded classification or explicit user resolution;
3. streaming fingerprint and immutable local publication;
4. durable journal reservation;
5. operation prepare and resumable transfer;
6. operation polling and one terminal notification.

Every transition is persisted before the next external side effect. A per-entry provider replaces
the queue-wide provider. Existing development documents with the old incomplete journal shape are
rejected rather than migrated; their managed archive files remain untouched and diagnostics name the
recovery action without exposing paths.

### 5. Authentication is request-scoped and restart-restorable

The app stores the HTTPS Platform origin and `PairedDeviceIdentity` as non-secret configuration and
stores device root/access/refresh credentials only in the non-synchronizing Keychain record. Runtime
startup loads both and refuses authenticated work if either side is absent. Network transports ask
the shared session coordinator for a usable access credential per request, so refresh or replacement
rotation is visible to later chunks and polls; they do not freeze one access token at construction.

Settings becomes onboarding plus operations: endpoint validation, pairing code exchange,
re-pair/revoke, folder/archive selection, launch-at-login preference, queue/history status and
retry/pause/cancel. Revocation removes the Keychain record and stops new network work while retaining
local state. A hidden credential copy in configuration was rejected.

### 6. Runtime scheduling is bounded, cancellable, and lifecycle-aware

The app delegate starts exactly one runtime after AppKit finishes launching and stops it during
termination. Queue, polling and reminder loops use independent bounded cadences over durable state,
with one in-flight task per entry and cancellation-safe checkpoints. Wake and network recovery
trigger reconciliation but do not bypass retry eligibility or rate limits. Smoke mode starts the
same composition shell with external side effects disabled, reports only startup, and exits within
its existing bound.

User-controlled launch at login uses `SMAppService.mainApp`; no helper executable or LaunchAgent is
added. The main menu-bar app remains the worker while running. This is preferred over an XPC helper:
there is no privileged work, a second executable would duplicate signing/lifecycle state, and direct
distribution already supports a login item for the main app.

### 7. Deployment fixes ports and capability wiring at one source of truth

The Platform-owned single-host examples and units assign ChatGPT receipt to `127.0.0.1:8096` and
Claude receipt to `127.0.0.1:8097`, matching `docs/DEPLOYMENT_TARGET.md`. Edge configuration names
both routes and their fixed receipt path. Provider configs have no shared `9084` fallback in the
deployment profile. Static config tests and an executable local profile assert the same mapping so a
documentation-only correction cannot pass.

### 8. Workspace acceptance uses exact clean revisions and real processes

The workspace will add an `XPA-020` task-namespaced profile following the existing executable
profiles rather than waiting for the general `ws` harness. Required full-SHA inputs point to clean
checkouts contained by each `origin/main`; the unchanged Contracts revision is recorded as an input.
The profile launches disposable PostgreSQL, secured NATS, real Platform, ChatGPT and Claude
processes, then a macOS system-test host using the production `AgentRuntime` composition and a
temporary user-selected directory/Keychain namespace.

Two synthetic provider ZIPs exercise pairing, mixed routing, immutable preservation, a forced chunk
interruption and process restart, duplicate replay, true parser/import completion, terminal polling,
privacy-safe diagnostics, and exact project teardown. The packaged app gets a separate smoke and
clean-machine acceptance; the workspace profile does not pretend its local system-test host proves
Apple signing or UI picker interaction.

### 9. GitHub Release is the manual update publication boundary

The existing manual distribution workflow will build the exact integrated Export Agent revision,
perform its fail-closed signing/notarization/stapling/Gatekeeper sequence, create an immutable GitHub
Release for the explicit version, and attach the final ZIP and SHA-256 file. Workflow permissions are
limited to release publication, all secret material remains temporary, and a pre-existing tag or
asset mismatch fails closed. Temporary Actions artifacts may remain diagnostic copies but are not the
product channel.

A separate clean-machine checklist/script installs that exact release ZIP and records Gatekeeper,
first launch, folder authorization, pairing, relaunch restoration, interrupted upload, terminal
summary, update-link, and rollback observations. Lack of Apple credentials blocks this release
phase, not repository implementation or synthetic integration, and must be reported as such.

## Risks / Trade-offs

- [Platform staging increases Edge disk and database responsibility] → Bound total size, chunk count,
  session lifetime and per-owner concurrency; store only temporary verified transfer material; test
  crash recovery and cleanup without deleting accepted provider archives.
- [A crash between provider acceptance and client acknowledgement repeats delivery] → Provider
  receipt is idempotent by operation and digest and always returns or recreates the operation result.
- [Provider parser failure strands accepted raw data] → Persist import jobs durably, expose worker
  readiness, retry only classified transient failures, and report a safe terminal failure for a
  permanent parse result while retaining raw bytes.
- [NATS credential rotation interrupts terminal reporting] → Keep outbox rows durable, make
  publisher health part of readiness, and verify recovery publishes the same event id exactly once.
- [Changing the development journal shape makes old bootstrap state unreadable] → Fail closed,
  preserve every managed archive file, and provide a diagnostic recovery path; do not add migration
  code or a parallel schema.
- [macOS lifecycle may suspend timers] → Treat timers as hints and reconcile durable state on
  startup/wake; never make an in-memory timer the authority for progress.
- [Owner Apple credentials remain unavailable] → Complete and publish all credential-free code,
  CI and integration evidence; mark notarization/publication/clean-machine acceptance blocked and do
  not fabricate a release.

## Migration Plan

1. Implement and merge Platform's operation-scoped transfer, readiness, secured-bus identities,
   deployment routes, and fixtures against the unchanged contract revision.
2. Implement ChatGPT and Claude receipt/import/report fixes in parallel; merge each after its secure
   NATS and real import tests pass against Platform fixtures.
3. Run the server-only exact-revision profile and verify both providers reach truthful terminal
   summaries, including duplicate and restart cases.
4. Implement and merge Export Agent runtime, onboarding, durable routing/recovery, and resumable HTTP
   client against the published server revisions.
5. Add the workspace profile, record exact SHAs and reviewed evidence, then advance the compatible
   workspace snapshot.
6. When owner Apple credentials are available, dispatch the explicit release, verify the published
   digest, and perform clean-machine acceptance before announcing availability.

Rollback proceeds in reverse dependency order. Disable new archive preparation first, stop the
provider units, restore the prior Platform deployment/configuration, roll back workspace inputs, and
manually reinstall the last accepted application if one exists. Preserve local archives, provider
raw archives, journal/operation records, release evidence, and Apple tickets. Remove only the exact
task-namespaced integration resources during test teardown.
