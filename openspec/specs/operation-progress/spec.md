# Operation progress across repositories

## Purpose

Defines how domain services report work to Platform and how Platform owns the complete operation
snapshot exposed to clients.

## Requirements

### Requirement: A producer reports only what it knows

A service that performs work for a Platform operation SHALL report progress by publishing
`platform.operation.reported.v1`. The payload SHALL carry the operation identifier and the status
reached, and MAY carry a stage, a progress percentage, result references, one error and any number of
warnings. It SHALL NOT carry the operation's kind, its acceptance time, its correlation identifier or
its tenant, because the producer does not hold them.

#### Scenario: a producer reports a status it reached

- **WHEN** a service finishes work for an operation it was handed and publishes
  `platform.operation.reported.v1` naming that operation and the status `succeeded`
- **THEN** Platform records the operation as `succeeded`, and a client reading the operation sees
  that status without the producer having named the operation's kind or acceptance time

#### Scenario: a report omitting the status is refused

- **WHEN** a producer publishes `platform.operation.reported.v1` with no status
- **THEN** the payload fails contract validation, and Platform applies nothing

### Requirement: Platform consumes the published contract

Platform SHALL read a progress report by the field names the published contract defines. A report
that validates against `platform.operation.reported.v1` SHALL advance the operation projection, and
Platform SHALL preserve every reported result reference, error, and warning in the operation
snapshot without dropping typed or additive v1 fields.

#### Scenario: a contract-shaped report advances the projection

- **WHEN** a payload serialized from the published `OperationReported` type arrives on `evt.>`
- **THEN** Platform applies it, rather than ignoring it for want of a field at a different depth

#### Scenario: an unknown status is not guessed

- **WHEN** a report carries a status outside the operation status vocabulary
- **THEN** Platform applies nothing and records that it could not act on the message

#### Scenario: a successful report retains its result

- **WHEN** a producer reports `succeeded` with a result containing a structured `BlobRef`
- **THEN** a client reading the operation receives the same result target and complete `BlobRef`

#### Scenario: a failed report remains readable

- **WHEN** a producer reports `failed` with a typed error
- **THEN** a client reading the operation receives a valid failed snapshot containing that error and its retryability

#### Scenario: warnings retain their contract data

- **WHEN** a producer reports warnings with an operation outcome
- **THEN** a client reading the operation receives those warnings without losing their field paths or additive fields

### Requirement: The snapshot event is Platform's to emit

`platform.operation.progressed.v1` SHALL be produced by Platform and carry the full operation
snapshot. No domain service SHALL publish it.

#### Scenario: a domain service publishing the snapshot event is a defect

- **WHEN** a repository other than Platform declares `platform.operation.progressed.v1` among the
  events it emits
- **THEN** that declaration contradicts this specification and the change that introduces it is
  refused
