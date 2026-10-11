## ADDED Requirements

### Requirement: A report is applied only for the operation's own tenant

Before applying a report carried by `evt.platform.operation.reported.v1`, Platform SHALL load the operation and SHALL reject the report unless the envelope `tenant_id` is present and equals `user:<operations.owner_user_id>`. A rejected report SHALL be recorded in the inbox as rejected, SHALL NOT change the operation's status, and SHALL log only the operation identifier and a safe class. The one exception is an AI-archive import, whose reports carry no tenant: Platform's acceptance record binds the owner for it, and its existing provider and producer check is unchanged.

#### Scenario: A report names another tenant's operation

- **WHEN** an identity allowed to publish the subject publishes a report for an operation owned by a different user
- **THEN** the operation's status is unchanged and the inbox records the rejection, verified by `crates/operations/tests/report_authority.rs` in `ratatoskr-platform`

#### Scenario: A report has no tenant

- **WHEN** a report for a capture operation carries no `tenant_id`
- **THEN** it is rejected the same way

### Requirement: A report is applied only from a producer allowed for the operation kind

The envelope `producer` SHALL be in the allow-list for the operation's kind: `content.capture.submit` allows `ratatoskr-extractor`, `ratatoskr-x`, `ratatoskr-instagram` and `ratatoskr-threads`; `channel_digest.subscription.set`, `channel_digest.run` and `channel_digest.schedule.occurrence` allow `ratatoskr-channel-digests`; `ai_archive.import` is bound to its provider by the acceptance record. A kind that is not in the table allows no producer and its reports are rejected until a row is added. The table SHALL be one constant next to the projection, and a test SHALL enumerate every operation kind Platform mints and fail when a minted kind has no row.

#### Scenario: A new operation kind is minted without a row

- **WHEN** Platform mints a kind that the authority table does not list
- **THEN** `every_minted_operation_kind_has_an_authority_row` fails before any report can be silently dropped

#### Scenario: A producer outside the list reports

- **WHEN** a producer that is not in the list for the operation's kind publishes a report
- **THEN** the report is rejected and the status is unchanged

### Requirement: The residual risk of the shared subject is stated

The four capture producers SHALL be documented as able to report for each other's capture operations, because a capture operation does not record which service it was dispatched to. Closing it needs per-producer report subjects, which is a contract change outside this requirement.

#### Scenario: The risk is recorded

- **WHEN** a reader looks for what the table does not prevent
- **THEN** `docs/ARCHITECTURE.md` section 11.2 of `ratatoskr-platform` and the changeset's residual risks name it
