## MODIFIED Requirements

### Requirement: A report is applied only from a producer allowed for the operation kind

Platform SHALL record on each operation the service it was dispatched to, as a nullable column `reporter` of `operations.operations` that holds a producer name (`^ratatoskr-[a-z0-9-]{1,56}$`), and SHALL pass that lane to `platform_operations::accept` at every mint site: `POST /v1/captures` without `social`, `POST /v1/captures/blobs` and the webhook adapter's capture target pass `ratatoskr-extractor`; a capture with `social.provider` `x`, `instagram` or `threads` passes `ratatoskr-x`, `ratatoskr-instagram` or `ratatoskr-threads`; the channel-digest routes and the scheduler's occurrence operations of a channel-digests schedule pass `ratatoskr-channel-digests`; AI-archive operations pass no lane, because their binding is the acceptance record. The authority table SHALL remain the closed list of producers a kind may name, and `accept` SHALL refuse a lane that is not in the kind's list. The projection SHALL apply a report only when the envelope tenant equals the operation's owner and, for a kind with a listed row, the operation's `reporter` is present and equals the report's producer; an AI-archive import keeps its acceptance-record check, and any other kind is rejected. A test SHALL enumerate every kind Platform mints and fail when a mint site passes no lane.

#### Scenario: One capture lane reports for another

- **WHEN** the X identity publishes a well-formed report, with the owner's tenant, for an operation that was dispatched to the Instagram lane
- **THEN** the inbox records it as rejected and the operation is unchanged, verified by `crates/operations/tests/report_authority.rs` in `ratatoskr-platform` and by flow F5 of the native smoke when it is run

#### Scenario: The right producer reports

- **WHEN** the Instagram identity publishes a report for that operation with the owner's tenant
- **THEN** the report is applied

#### Scenario: A mint site passes no lane

- **WHEN** a new mint site for a kind with a listed row passes no lane
- **THEN** the enumeration test fails before any report can be dropped silently

### Requirement: The residual risk of the shared subject is stated

`evt.platform.operation.reported.v1` SHALL remain one subject trusted by the envelope producer, so a compromised producer can forge a report only for an operation of its own lane and tenant boundary. The identity that can read the subject through `ratatoskr_x_extractor_reports`, X, can still read the operation-report metadata of every tenant. Per-producer report subjects would close that and need a contract change outside this requirement. `docs/ARCHITECTURE.md` section 11.2 and the module comment of `authority.rs` in `ratatoskr-platform` SHALL state exactly these limits and no longer describe the cross-lane risk.

#### Scenario: The risk is recorded

- **WHEN** a reader looks for what the lane check does not prevent
- **THEN** `docs/ARCHITECTURE.md` section 11.2 of `ratatoskr-platform` and the changeset's residual risks name the metadata read and the shared subject
