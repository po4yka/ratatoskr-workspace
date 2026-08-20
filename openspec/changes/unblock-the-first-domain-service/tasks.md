# Tasks

## Implementation by repository

One item per repository, in dependency order. An item closes only when its pull request merges, and
carries the link. This list is the only place the completeness of the change is visible.

- [ ] 1. `ratatoskr-contracts` — `OperationReported`, `BlobRef`, Document IR version one. PR:
- [ ] 2. `ratatoskr-platform` — the projection reads the published contract. PR:
- [ ] 3. `ratatoskr-extractor` — consumes the command, emits a domain event and a report. PR:

## 1. ratatoskr-contracts

- [ ] 1.1 Add a failing test `crates/operation-contracts/tests/reported.rs::a_report_without_a_status_is_refused`, asserting that deserializing a payload with no `status` fails. It fails because `OperationReported` does not exist.
- [ ] 1.2 Add `OperationReported` with `EVENT_TYPE = "platform.operation.reported.v1"`, carrying `operation_id`, `status`, optional `stage`, `progress_percent`, `results`, `error`, `warnings`, and `extensions`. Make 1.1 pass.
- [ ] 1.3 Add a failing test `crates/operation-contracts/tests/reported.rs::a_report_carries_no_snapshot_only_fields`, asserting that `kind`, `accepted_at`, `correlation_id` and `tenant_id` are not members. It fails until the type is final.
- [ ] 1.4 Make 1.3 pass, and record in the type's documentation why each absent field is absent.
- [ ] 1.5 Add a failing test `crates/identifiers/tests/blob_ref.rs::a_reference_without_a_digest_is_refused`. It fails because `BlobRef` does not exist.
- [ ] 1.6 Add `BlobRef` with the owning service, a digest and its algorithm, the media type and the byte length. Make 1.5 pass.
- [ ] 1.7 Add a failing test for Document IR round-tripping a document with two block kinds and provenance, naming the file it lands in. It fails because the type does not exist.
- [ ] 1.8 Add Document IR version one — identity, address, digest, optional title and language, ordered typed blocks, provenance — and make 1.7 pass.
- [ ] 1.9 Mark plan items 4 and 5 implemented in `docs/IMPLEMENTATION_PLAN.md`. No test: documentation.

## 2. ratatoskr-platform

- [ ] 2.1 Add a failing test `crates/operations/tests/projection.rs::a_published_report_advances_the_projection`, building the payload by serializing `OperationReported` rather than by hand, and asserting the operation reaches the reported status. It fails because the projection reads `payload.operation_id` while the contract publishes `payload.status` beside it and nothing at the old depth.
- [ ] 2.2 Change `ProgressReport::read` to deserialize the published contract. Make 2.1 pass.
- [ ] 2.3 Replace the hand-built fixture in the existing projection tests with the serialized contract. Refactor only, after 2.1 and 2.2 are green: no new test, no behaviour change.
- [ ] 2.4 Close Q3 in `docs/DEVELOPMENT.md` with the decision and a pointer to this change, and record in `docs/adr/README.md` that the event-family question is answered. No test: documentation.
- [ ] 2.5 State in `docs/ARCHITECTURE.md` S11 that Platform consumes reports and produces snapshots, and that emitting `platform.operation.progressed.v1` is not yet implemented. No test: documentation.

## 3. ratatoskr-extractor

- [ ] 3.1 Add a failing test asserting that a consumed `content.capture.requested.v1` produces one `platform.operation.reported.v1` naming the same operation. It fails because nothing consumes the command.
- [ ] 3.2 Consume the command and emit the report through the outbox. Make 3.1 pass.
- [ ] 3.3 Add a failing test asserting a stored artifact is announced by a `BlobRef` whose digest matches the bytes on disk. It fails because nothing stores an artifact.
- [ ] 3.4 Store the artifact under the service's own content-addressed path and announce it by reference. Make 3.3 pass.

## Out of this change

- Platform emitting `platform.operation.progressed.v1`. The contract keeps its meaning; the second
  consumer that needs the event does not exist.
- Extractor's fetch policy, candidate selection and quality evaluation.
- Off-host replication of blobs.
