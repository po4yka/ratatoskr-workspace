## Context

See proposal.md and the three delta specs. Platform already owns the required durable facts:
`identity.grants`, `identity.audit_events`, `operations.operations`, and the
`operations.schedule_status` view. Its ordinary operation routes are correctly user-scoped; its
capability route is authenticated but does not yet apply a grant filter. Runtime readiness and
loopback capability observations are already sampled off the request path.

Web already has one gateway, generated Platform types, session boot, lazy protected routes,
capability-gated navigation, a skip link, theme support, and component tests. It has no public route
other than login, no operational list route, no browser e2e suite, and no composed workspace proof.
The workspace still documents its integration harness as target architecture; there is no
`workspace.toml`, `workspace.lock`, `ws`, or Compose profile to claim as implemented.

The source checkouts contain unrelated user work. The coordination worktree is
`/Users/po4yka/GitRep/ratatoskr-task-worktrees/WEB-012/workspace` on
`codex/web-012-operational-status`, based on workspace `c2d5e85`. The Web task worktree is
`/Users/po4yka/GitRep/ratatoskr-workspace/worktrees/ratatoskr-web-plan-item-12-operational-views`
on `codex/plan-item-12-operational-views`, based on Web `4ca1279`. Apply creates one additional
writer worktree each from Contracts `5b8bbb4` and Platform `28f3e8e`; no baseline checkout is edited.

## Goals / Non-Goals

**Goals:**

- Add one contract family for public status and privileged operational query results.
- Make authorization live, server-side, fail-closed, and compatible with the existing grant model.
- Reuse sampled readiness facts and durable Platform projections rather than adding cross-service
  request fan-out or new storage.
- Keep Web route chunks, data boundaries, UI states, and evidence independently testable.
- Provide a real, isolated composed smoke without pretending the absent general workspace harness
  has been implemented.

**Non-Goals:**

- A role hierarchy, role-management UI, bootstrap-owner API, or browser-side authorization model.
- A second job model, schedule mutation, audit export, raw telemetry, or operator-listener proxy.
- High-availability status infrastructure; one Edge process cannot report while it is unreachable.
- General workspace manifest, lock, task, PR, or release-harness implementation.
- Any legacy or fleet-follow-up surface excluded by proposal.md.

## Decisions

### D1: Shared shapes live in `ratatoskr-operational-contracts`

Contracts adds one Rust-first crate and metadata entry containing validated serializable types for:

- public component identifiers and states, `PublicStatusDocument`, and component observations;
- owner operation summaries/pages with stable safe failure codes;
- schedule status summaries/pages;
- audit event summaries/pages; and
- the three operational capability names plus the `platform.owner` grant name as exact constants.

Platform keeps route definitions and OpenAPI generation in its existing `public-api` and `api-doc`
crates, but uses the shared types as response bodies. Web continues to generate from Platform's
OpenAPI rather than importing a second TypeScript package. This matches the existing
operation-contract pattern and leaves one canonical wire shape. Keeping these as Platform-local
structs was rejected because Contracts was explicitly brought into this changeset and the same
query results are valid future mobile/operator-agent inputs. A broad generic admin contract was
rejected because the excluded legacy admin surfaces have no owner or data contract yet.

All collection lengths and free text are validated. Audit and operation shapes carry identifiers,
closed states, timestamps, and stable codes only. No schema contains arbitrary JSON, request
payloads, diagnostic strings, addresses, user content, or credentials.

### D2: "Owner" is a live capability grant, not an identity role

The existing `identity.grants` table deliberately rejects a role model. Apply uses the exact
non-expiring capability `platform.owner`, provisioned out of band like existing grants. No schema
change is required. Platform reads all relevant grants for the principal in one bounded database
query and evaluates them on every privileged request. Grant lookup failure maps to the existing
dependency-timeout envelope, never to allowed or forbidden.

Capability discovery performs the same live grant read, then intersects authorization with
deployment readiness. It adds `platform.audit.inspect`, `platform.operations.inspect`, and
`platform.schedules.inspect` to the closed capability vocabulary. Web gates each subsection from
those names; Platform repeats the owner check on every read. Encoding `owner: true` into the session
or exposing a `/me` role was rejected because revocation would remain stale for the session lifetime.

### D3: Privileged reads are separate additive routes

Platform adds:

- `GET /v1/admin/operations` and `GET /v1/admin/operations/{operation_id}`;
- `GET /v1/admin/schedules`; and
- `GET /v1/admin/audit-events`.

The ordinary `/v1/operations` routes remain exactly user-owned. Reusing them with an implicit owner
override was rejected because one path whose scope changes by hidden privilege is harder to audit and
easier to widen accidentally.

Lists default to 20 and reject limits outside 1..=100. Operations reuse the existing
`(accepted_at, operation_id)` keyset; audit uses `(occurred_at, audit_event_id)`; schedules use a
deterministic `(service_name, name, schedule_id)` keyset. Cursors are opaque, validated service
output. Queries fetch `limit + 1`, emit at most `limit`, and never count the whole table. Filters are
conjunctive and applied in SQL. Operation detail reuses the existing safe `OperationSnapshot`.

### D4: Public status is a projection of already-sampled facts

`GET /v1/status` is registered with no session security and with the existing public rate and body
policies. It does no database query and no downstream request. It projects a snapshot from the same
`RuntimeState` and cached gateway observations that readiness and capabilities already use.

The fixed public groups are `api`, `storage`, `command_delivery`, and `connected_services`:

- `api` follows startup/drain readiness while the public listener can still answer;
- `storage` follows the last database readiness observation;
- `command_delivery` follows bus configuration and the last connection observation;
- `connected_services` aggregates all configured loopback services without serializing names,
  documents, counts, addresses, or per-service diagnostics.

`api` or `storage` unavailable makes the overall state unavailable. A stale/unknown connected
service or unavailable command delivery makes it degraded while reads can still be served. All
current groups operational makes the document operational. The route returns 200 with
`Cache-Control: no-store`; losing Edge itself remains a transport failure that Web renders
separately. Query-time fan-out and exposing `/health/ready` publicly were rejected because both leak
topology and let the status request add load to the dependency it is measuring.

### D5: Web keeps public and protected routing structurally separate

The router gains a top-level lazy `/status` branch before the authenticated wildcard. It uses an
anonymous gateway whose token source is always empty and never mounts session boot or capability
discovery. The protected branch gains `/ops/operations`, `/ops/schedules`, and `/ops/audit`, with
`/ops` redirecting to the first available subsection. Each subsection declares its own capability;
the shell may group the links visually, but the registry remains the single availability source.

Each feature has a narrow source interface backed by the existing gateway and generated request and
response types. Component tests inject source adapters; browser tests intercept only the public Edge
boundary. Pagination state lives in the URL cursor, and a route change restores focus to the page
heading without stealing focus on background refresh. No query-cache dependency is added for these
read-only first pages.

### D6: Accessibility is an observed route matrix, not a prose assertion

Web adds `@playwright/test` and `@axe-core/playwright` as development-only dependencies in their own
commit. The browser suite runs a deterministic local mock Platform and covers public status,
member-gated `/ops`, owner operations, schedules, audit, login, search, and reader in light and dark
themes at phone and desktop widths. Axe serious/critical findings fail. Explicit keyboard tests
cover skip navigation, tab order, Enter/Space activation, Escape dismissal, route focus placement,
and focus return after dialogs. Shadscan's rendered-page mode supplies measured overflow,
target-size, and contrast evidence.

`docs/ACCESSIBILITY_CHECKLIST.md` records the exact commands, route/theme/viewport matrix, manual
screen-reader and keyboard observations, findings, fixes, and any check that could not be observed.
It is required because the user made it acceptance evidence; it is updated from observed results,
not pre-filled as success. Automated checks do not claim a manual screen-reader result.

### D7: The composed proof is one profile, not the absent general harness

Workspace adds `integration/compose/web-operational.yaml`, bounded seed data, and a smoke runner. The
Compose file requires explicit Contracts, Platform, and Web context/revision inputs and a task
namespace; no committed relative child dependency or host port is assumed. It builds Platform Edge
and the Web production bundle, starts PostgreSQL and NATS, waits on bounded health checks, seeds two
synthetic users/sessions plus owner grant/operations/schedule/audit rows, and runs Playwright through
the Web URL.

The runner uses a unique Compose project name and explicit timeouts. Its degraded phase stops only
that project's NATS service, waits for Platform's bounded readiness observer, verifies public and
rendered degradation, and then tears down only namespaced resources. Raw credentials are fixed
non-secret fixture values and never logged. A reusable `ws` command, workspace pins, and lockfile
are not fabricated; documentation says they remain absent.

### D8: Publication follows dependency order and the user's direct-main delivery

Apply creates local OpenSpec changes in Contracts, Platform, and Web before code. Each repository
uses one writer worktree and tests first. Contracts is committed, integrated into its `main`, pushed,
and remotely verified before Platform pins its full commit. Platform follows before Web copies and
pins the generated OpenAPI. Workspace integration runs against those exact commits, then the
workspace coordination artifacts/profile are integrated and pushed.

The workspace's normal task rule expects merged PR URLs. The user's explicit delivery instead
requires local task-branch integration and pushing `main`; tasks therefore record verified merge
commit or fast-forward SHAs and mark PR as not used by direction, rather than creating unrequested
PRs. Cleanup uses `git branch -d` only after remote `main` contains each task head. The dirty Web
source checkout is advanced only if its unrelated `AGENTS.md` edit does not overlap; otherwise a
temporary clean integration worktree performs the main update.

## Risks / Trade-offs

- [The public status route can reveal availability timing] -> Expose only four stable groups,
  no names/counts/reasons, use no-store, and add a privacy-shape contract test.
- [Grant lookup adds a database read to capability discovery and admin routes] -> Query one exact
  grant in one indexed statement; do not cache authorization across requests.
- [A status group may over-aggregate one failed connected service] -> Report the aggregate as
  degraded/stale; detailed service health remains authenticated/operator-only.
- [New contract crate lengthens rollout] -> Additive crate and endpoints allow old clients to keep
  working; Contracts merges first and Platform pins one full SHA.
- [Browser matrix increases CI time] -> Keep one Chromium project, two viewports, bounded route
  fixtures, and no screenshots unless a test fails.
- [Compose ports or containers collide with other tasks] -> Require a namespace, allocate ephemeral
  host ports, use named health checks, and inspect existing resources without deleting them.
- [Workspace harness remains absent] -> Commit only the executable profile/smoke required here and
  document the narrower implemented reality.

## Migration Plan

1. Create Contracts and Platform writer worktrees from their verified `origin/main` commits and
   create repository-local OpenSpec changes that cite this fleet spec.
2. Red-green the operational contract crate, generate artifacts, run the Contracts full gate,
   integrate and push Contracts `main`, and record the remote SHA.
3. Pin that SHA in Platform; red-green grant enforcement, queries, public status, OpenAPI, and
   privacy/authorization tests; run the gated Rust suite and full Platform gate; integrate and push
   Platform `main`.
4. Refresh Web's pinned OpenAPI from the verified Platform SHA and commit regeneration separately.
   Red-green public/protected routing, views, accessibility behavior, and browser tests; run the full
   Web gate and rendered UI audit; integrate and push Web `main`.
5. Run the workspace Compose smoke with exact child SHAs, including its isolated degraded phase;
   store commands and observed results, validate/archive OpenSpec changes, then integrate and push
   workspace `main`.
6. Verify every remote `main` contains the intended task head. Remove only merged task worktrees and
   branches, leaving baseline user changes and unrelated worktrees intact.

Rollback removes the workspace profile and deploys the previous Web and Platform commits in that
order. The additive Contracts commit may remain. If Platform rollback happens first, the new Web
renders its normalized unavailable state for missing routes; it never synthesizes operational data.
Revoke `platform.owner` before rollback when privileged access must close immediately.
