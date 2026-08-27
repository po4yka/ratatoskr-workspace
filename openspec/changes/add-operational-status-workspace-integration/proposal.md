## Why

Ratatoskr Web can inspect only the signed-in user's operations today; the public Edge contract has
no owner-authorized operational projections and no anonymous sanitized status document. Plan item
12 cannot be shipped truthfully until Contracts, Platform, Web, and the workspace integration
profile agree on those boundaries and verify them together.

## What Changes

- Add bounded wire contracts for owner-authorized operation inspection, schedule status, and audit
  history, with pagination and redacted user-safe failure data.
- Treat "owner" as the existing non-expiring `platform.owner` authorization grant rather than
  adding a role table. Platform remains the enforcement boundary; its capability document exposes
  each operational surface only to a principal that currently holds the grant.
- Add owner-only Edge reads for recent operations, operation failure detail, schedule status, and
  audit history. Existing per-user operation routes keep their current ownership semantics.
- Add an unauthenticated `GET /v1/status` document derived from already-sampled readiness facts. It
  reports operational, degraded, or unavailable components without internal addresses, service
  payloads, user data, versions, credentials, or provider diagnostics.
- Add the Web `/ops` surfaces and public `/status` route from generated API types, with truthful
  loading, empty, partial, stale, offline, forbidden, and terminal-failure states. Add the requested
  focus, landmark, contrast, and keyboard hardening plus committed accessibility evidence.
- Add a task-namespaced Compose profile and Playwright smoke that exercises the real Web build
  against Platform, including anonymous status, owner denial/allowance, and one degraded status
  observation.
- Update the current-state documentation and implementation plan only after the corresponding
  behavior and evidence exist.

## Capabilities

### New Capabilities

- `operational-inspection-api`: Owner-authorized, paginated operation, schedule, and audit
  projections with server-side enforcement and capability discovery.
- `public-status-api`: An anonymous, sanitized, truthful system-status document with explicit
  degraded, unavailable, and stale observations.
- `web-platform-operational-integration`: The generated-contract client behavior and composed
  profile proof joining Platform's operational and status APIs to Ratatoskr Web.

### Modified Capabilities

None.

## Impact

Repositories, in dependency order:

1. `ratatoskr-contracts` defines and generates the new wire types and compatibility fixtures. It
   merges first.
2. `ratatoskr-platform` pins that contract revision, enforces the `platform.owner` grant, serves the
   new Edge routes, and regenerates OpenAPI.
3. `ratatoskr-web` pins the Platform OpenAPI digest, regenerates TypeScript, implements the routes
   and accessibility fixes, and adds browser-level tests.
4. `ratatoskr-workspace` provides the namespaced Compose profile, records integration evidence, and
   pins the verified child commits when the workspace pinning mechanism exists.

The change adds two Web-only development dependencies for browser and accessibility tests; neither
ships in the browser bundle. It adds no database migration and no second API version. The existing
`identity.grants`, `identity.audit_events`, `operations.operations`, and
`operations.schedule_status` storage remains authoritative.

Outside this change: LLM cost dashboards, user administration, system-backup controls, credentials
catalog administration, digest/RSS/signals/chat-agent surfaces, EN/RU localization infrastructure,
the command palette, and the global agent dock. "Jobs" is not invented as a second lifecycle model;
the inspector uses Platform operations and exposes schedules only through their owned projection.

Rollback proceeds in reverse order: remove the workspace profile, deploy the previous Web build,
then deploy the previous Platform build. The additive contract revision may remain pinned because
older producers and consumers ignore the new types. Revoking `platform.owner` immediately removes
operational capabilities and makes every privileged route return forbidden; the anonymous status
route contains no privileged data. Nothing in this change has shipped yet.
