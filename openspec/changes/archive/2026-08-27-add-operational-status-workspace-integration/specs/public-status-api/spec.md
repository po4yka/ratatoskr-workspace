## Purpose

Defines an anonymous sanitized status document that reports current and stale dependency health
truthfully while withholding the private topology and data of a self-hosted Ratatoskr deployment.

## ADDED Requirements

### Requirement: Public status is readable without a session

`GET /v1/status` SHALL be available without authentication and SHALL return the same sanitized
document whether an Authorization header is absent, invalid, or valid. While Edge can answer, the
route SHALL return the document with HTTP 200 so a client can render degraded and unavailable
component facts instead of reducing them to a generic transport error.

#### Scenario: Signed-out visitor reads status
- **WHEN** a request with no credential reads `/v1/status`
- **THEN** Platform returns the sanitized status document without creating or requiring a session

#### Scenario: Credential does not enrich public status
- **WHEN** an owner and an anonymous visitor read status from the same observation
- **THEN** both responses contain the same fields and component facts

### Requirement: Status vocabulary distinguishes health, degradation, outage, and uncertainty

The document SHALL contain a generation timestamp, an overall state of `operational`, `degraded`,
or `unavailable`, and a deterministic list of public component groups. Each component SHALL contain
a stable public identifier, state of `operational`, `degraded`, `unavailable`, or `unknown`, the
latest successful observation time when one exists, and an explicit stale flag. Unknown and stale
facts SHALL NOT be presented as operational.

#### Scenario: Healthy dependencies report operational
- **WHEN** every required component has a current successful observation
- **THEN** every component and the overall document report `operational` with `stale` false

#### Scenario: Lost downstream becomes degraded and stale
- **WHEN** a downstream component previously answered successfully and its latest bounded refresh fails
- **THEN** its component reports `degraded`, retains the last successful observation time, sets `stale` true, and makes the overall document at least `degraded`

#### Scenario: Never-observed component remains unknown
- **WHEN** a configured component has never produced a successful observation
- **THEN** its state is `unknown`, its observation time is absent, and the overall document is not `operational`

#### Scenario: Required dependency is unavailable
- **WHEN** the latest readiness fact says a required component cannot serve work
- **THEN** that component reports `unavailable` and the overall document reports `unavailable` when no usable public operation remains

### Requirement: Public status is sanitized and bounded

The public status document SHALL use stable product-facing component groups and SHALL NOT reveal
internal service names, hostnames, listener addresses, database or stream identifiers, versions,
raw capability documents, raw readiness reasons, provider diagnostics, user identifiers, user
content, operation data, credentials, or secret-bearing configuration. The component set and every
text field SHALL be closed or length-bounded by the wire contract.

#### Scenario: Internal readiness detail is not serialized
- **WHEN** an internal dependency failure includes an address, service name, and diagnostic text
- **THEN** the public component reports only its stable group, contracted state, observation time, and stale flag

#### Scenario: Consecutive unchanged observations are structurally stable
- **WHEN** two status reads observe unchanged health facts
- **THEN** they return components in the same order with the same identifiers and states, apart from the document generation time

### Requirement: Status freshness is not hidden by intermediaries

The status response SHALL prevent an intermediary from presenting an unlabelled old status as the
current document. A client that intentionally retains a previous successful document during a
transport failure SHALL label it stale and SHALL keep the transport failure visible.

#### Scenario: Status response is not stored as fresh
- **WHEN** Platform returns a status document
- **THEN** its cache policy prevents reuse as an unlabelled current response

#### Scenario: Client loses the status endpoint after a successful read
- **WHEN** a client has a prior document and a later status request loses transport
- **THEN** the client shows the connection failure and may show the prior facts only with an explicit stale label
