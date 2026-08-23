## MODIFIED Requirements

### Requirement: Platform consumes the published contract

Platform SHALL read a progress report by the field names the published contract defines. A report that validates against `platform.operation.reported.v1` SHALL advance the operation projection, and Platform SHALL preserve every reported result reference, error, and warning in the operation snapshot without dropping typed or additive v1 fields.

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
