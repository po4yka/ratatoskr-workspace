# Web Platform Operational Integration Specification

## Purpose

Defines the observable client and integration behavior that proves Ratatoskr Web consumes the
operational and status contracts through Platform alone and remains accessible in real composition.

## Requirements

### Requirement: Web consumes generated operational and status types

Ratatoskr Web SHALL generate and commit its API types from the exact pinned Platform OpenAPI digest
that declares the operational and status routes. It SHALL make every request through its existing
Edge gateway and SHALL NOT add browser-owned wire shapes, direct database access, operator-listener
access, or casts that hide a generated-contract mismatch.

#### Scenario: Platform contract changes without regeneration
- **WHEN** the pinned Platform OpenAPI or generated TypeScript differs from the committed digest
- **THEN** the Web contract check fails before typecheck or browser tests

#### Scenario: Web loads operational data
- **WHEN** an authorized owner opens an operational view
- **THEN** every network request targets a generated public Edge route and no private Platform or service endpoint

### Requirement: Public status is outside the authenticated shell

The Web `/status` route SHALL render without session boot or capability discovery. It SHALL render
loading, operational, degraded, unavailable, stale, and transport-failure states from the sanitized
status contract, with text as well as visual treatment for every state.

#### Scenario: Anonymous visitor opens degraded status
- **WHEN** a signed-out visitor opens `/status` and Platform reports one degraded stale component
- **THEN** the page names the overall degradation, names that component's degraded and stale facts, and does not redirect to login

#### Scenario: Status transport is offline
- **WHEN** the status request loses transport
- **THEN** the page reports that current status cannot be reached and does not render an empty or operational state

### Requirement: Operational views are capability-gated and server-enforced

The Web operational navigation and routes SHALL derive availability from the three operational
capabilities. An absent capability SHALL render an explained absence; a failed capability read SHALL
remain a retryable discovery failure. Platform's forbidden response SHALL remain visible if a stale
client presentation reaches a route after grant revocation.

#### Scenario: Member cannot navigate or deep-link into operations
- **WHEN** a member receives no operational capabilities and opens the application or directly requests `/ops`
- **THEN** operational navigation is absent and the deep link renders an explained forbidden or unavailable surface without operational data

#### Scenario: Owner grant is revoked after navigation rendered
- **WHEN** an owner has an operational link, the grant is revoked, and the owner activates that link
- **THEN** the view renders Platform's forbidden state and does not treat the previously rendered link as authorization

### Requirement: Operational information remains truthful and bounded in the UI

The Web operations inspector SHALL distinguish every contracted operation lifecycle state and expose
user-safe failure codes without private diagnostics. Schedule and audit views SHALL paginate through
server cursors and SHALL distinguish loading, empty, partial, stale, forbidden, offline, and terminal
failure states rather than filtering an unbounded client collection or sharing one generic error.

#### Scenario: Failed and partially succeeded operations remain distinct
- **WHEN** the recent page contains one failed operation and one partially succeeded operation
- **THEN** the inspector renders both exact states and does not present either as clean success

#### Scenario: Empty audit page is not a failed read
- **WHEN** Platform successfully returns an empty audit page
- **THEN** the viewer renders an explicit empty state that differs from its request-failure state

### Requirement: The affected Web surfaces satisfy the accessibility acceptance

The public status page, operational routes, and existing application shell SHALL provide semantic
landmarks, a working skip path, visible focus, focus placement after route and error-state changes,
keyboard operation for every interactive control, text alternatives for non-text controls, state
labels not carried by color alone, AA contrast in both themes, and reduced-motion behavior. The
repository SHALL commit a checklist that names every audited route, method, finding, fix, and any
remaining unverified manual check.

#### Scenario: Keyboard-only owner traverses an operational route
- **WHEN** an owner uses only Tab, Shift+Tab, Enter, Space, Escape, and the skip link on `/ops`
- **THEN** every control is reachable and operable in a logical order, focus remains visible, and focus is not lost on navigation or disclosure changes

#### Scenario: Automated accessibility audit covers both themes
- **WHEN** the accessibility suite scans the status and operational routes in light and dark themes
- **THEN** it reports no accepted serious or critical violation and the committed checklist records the observed result

### Requirement: A namespaced composed profile proves the boundary end to end

The workspace SHALL provide a task-namespaced Compose profile that starts the Web production build,
Platform Edge, PostgreSQL, and NATS with isolated project, port, database, stream, and volume names.
The smoke SHALL use synthetic users and credentials only, grant one user `platform.owner`, leave one
user unprivileged, and exercise the system through public HTTP routes rather than private schemas
except for deterministic environment seeding.

#### Scenario: Composed owner and member smoke passes
- **WHEN** the profile is started from a clean task namespace
- **THEN** an anonymous browser reads `/status`, the member is denied operational data, the owner reads operations, schedules, and audit history, and the Web production build serves every exercised route

#### Scenario: Isolated dependency loss is rendered as degradation
- **WHEN** the profile's own NATS dependency is stopped after a healthy observation
- **THEN** Platform's public status becomes degraded or unavailable according to the contract and the Web status page renders that state without claiming the whole archive is healthy

#### Scenario: Profile teardown preserves unrelated environments
- **WHEN** the smoke profile is torn down
- **THEN** only resources carrying its task namespace are stopped or removed and unrelated containers, ports, databases, streams, and volumes remain untouched
