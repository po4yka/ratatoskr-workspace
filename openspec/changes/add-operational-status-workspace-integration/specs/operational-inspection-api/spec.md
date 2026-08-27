## Purpose

Defines the bounded owner-authorized projections that let clients inspect Platform operations,
schedules, and audit history without reading private schemas or treating presentation as security.

## ADDED Requirements

### Requirement: Operational inspection is authorized by a live owner grant

Platform SHALL treat a currently live `platform.owner` grant as the authorization required for
deployment-wide operational inspection. It SHALL enforce that grant on every privileged request
and SHALL NOT add a role claim or rely on client-side route hiding as enforcement.

#### Scenario: Member is denied every operational projection
- **WHEN** an authenticated principal without a live `platform.owner` grant requests any operational inspection endpoint
- **THEN** Platform returns the stable forbidden error and reveals no operation, schedule, or audit row

#### Scenario: Revocation takes effect during a live session
- **WHEN** a principal's `platform.owner` grant is revoked after its session was established
- **THEN** the next privileged request is forbidden without requiring that session to expire

#### Scenario: Authorization storage is unavailable
- **WHEN** Platform cannot determine whether the principal holds the owner grant
- **THEN** Platform reports a dependency failure and does not misreport the request as either allowed or forbidden

### Requirement: Capability discovery reflects owner-authorized operational surfaces

The authenticated capability document SHALL expose `platform.operations.inspect`,
`platform.schedules.inspect`, and `platform.audit.inspect` only when the caller holds the live owner
grant and the dependency required by that surface is currently available. The document SHALL remain
the client's presentation input; direct endpoint authorization SHALL remain authoritative.

#### Scenario: Owner receives operational capabilities
- **WHEN** an owner reads capabilities while Platform's operational database is available
- **THEN** all three operational capability names are present in deterministic order

#### Scenario: Member receives no operational capability
- **WHEN** a member without the owner grant reads capabilities
- **THEN** none of the three operational capability names is present

#### Scenario: Capability disappears with its dependency
- **WHEN** the operational database is unavailable at the latest readiness observation
- **THEN** the operational capability names are absent even for an owner

### Requirement: Owners can inspect bounded recent operations

`GET /v1/admin/operations` SHALL return a cursor-paginated, newest-accepted-first list across users
to an authorized owner. It SHALL accept bounded page size and exact lifecycle-state, operation-kind,
and owner-user filters. Each row SHALL contain identity, owner, kind, lifecycle state, accepted and
status-change times, and only bounded user-safe failure codes; it SHALL NOT contain request payloads,
provider diagnostics, credentials, private URLs, or user content.

#### Scenario: Owner reads recent operations across users
- **WHEN** an owner requests the first page and operations owned by two users exist
- **THEN** Platform returns both users' rows in newest-accepted-first order with a continuation cursor when more rows exist

#### Scenario: Operation filters are exact and server-side
- **WHEN** an owner filters by lifecycle state, exact kind, or owner user identifier
- **THEN** every returned row satisfies every supplied filter and the client is not required to fetch an unbounded collection

#### Scenario: Failed operation is truthful but redacted
- **WHEN** a failed operation has a stable user-safe error code and a private diagnostic payload
- **THEN** its summary exposes the stable code and excludes the private payload

### Requirement: Owners can inspect one operation without changing user ownership semantics

`GET /v1/admin/operations/{operation_id}` SHALL return the existing operation snapshot shape for an
authorized owner regardless of which user owns the operation. The existing
`GET /v1/operations/{operation_id}` route SHALL continue to return a snapshot only to that
operation's owner.

#### Scenario: Owner reads another user's failed operation
- **WHEN** an owner requests the privileged detail route for another user's failed operation
- **THEN** Platform returns its user-safe snapshot, including its terminal failure and retryability facts

#### Scenario: Member cannot widen an ordinary operation read
- **WHEN** a member requests another user's operation through either the ordinary or privileged route
- **THEN** Platform reveals no snapshot through either route

### Requirement: Owners can inspect bounded schedule status

`GET /v1/admin/schedules` SHALL return a cursor-paginated deterministic list of schedule status to
an authorized owner. Each row SHALL contain the schedule identifier, stable service label, schedule
name, owner user identifier, enabled state, next due time, and last operation outcome when one
exists. It SHALL NOT expose arbitrary command payloads, credentials, internal listener addresses, or
provider configuration.

#### Scenario: Schedule with no occurrence remains unknown
- **WHEN** an enabled schedule has not produced an occurrence yet
- **THEN** its row reports its next due time and no last outcome rather than synthesizing success

#### Scenario: Disabled schedule remains visible
- **WHEN** a schedule is disabled after a failed occurrence
- **THEN** its row remains visible with `enabled` false and the recorded failed last outcome

### Requirement: Owners can inspect bounded audit history

`GET /v1/admin/audit-events` SHALL return a cursor-paginated, newest-first audit trail to an
authorized owner. Each row SHALL be limited to the audit event identifier, occurrence time, actor
user and session identifiers when present, stable action, target kind and identifier when present,
outcome, and correlation identifier. It SHALL NOT expose request bodies, bearer material, provider
responses, private URLs, user content, or internal diagnostics.

#### Scenario: Audit order is stable across equal timestamps
- **WHEN** two audit events share the same occurrence timestamp
- **THEN** pagination uses the event identifier as a deterministic tie-breaker and neither event is duplicated or skipped

#### Scenario: Anonymous system event remains attributable without fabrication
- **WHEN** an audit event has no actor user or session
- **THEN** the corresponding fields are absent and the client does not invent an owner or actor
