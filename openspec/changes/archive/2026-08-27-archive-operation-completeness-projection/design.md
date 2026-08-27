## Context

See proposal.md. Platform's public operation snapshot already retains typed optional fields on every
operation result. The archive graph and raw parser output remain owned by their provider services.

## Goals / Non-Goals

**Goals:**

- Define one compact typed result field all clients can interpret.
- Preserve Platform as a generic operation projection rather than an archive reader.
- Make consumer rollout safe when an older producer has not emitted the extension.

**Non-Goals:**

- Adding a second Platform endpoint, schema, migration, or version route.
- Returning full archive snapshots, message content, titles, individual gap text, or private parser
  diagnostics from an operation response.

## Decisions

- The summary is a typed optional `OperationResultRef` field, not a new endpoint. Platform already
  durably records and returns operation results; a new route would duplicate projection and require
  cross-domain querying.
- The producer sends counts and a closed completeness class only. Those are sufficient for a local
  status UI and notifications; report detail stays behind the optional reference.
- A missing or malformed summary remains unverified. This allows the consumer to deploy before
  producers and prevents a terminal `succeeded` status from becoming a fabricated completeness
  claim.

## Risks / Trade-offs

- [Producers roll out late] -> Consumers display an explicit unverified terminal result until they
  receive the summary.
- [Unexpected summary shape] -> Consumers reject only the summary and retain the last valid
  operation observation.
- [Summary fields reveal sensitive data] -> The contract permits aggregate counts and identifiers
  only; the producer contract tests reject content-bearing fields.

## Migration Plan

1. `ratatoskr-contracts` publishes fixtures and validation for the typed field.
2. Platform validates and projects the typed field through its existing operation route.
3. `ratatoskr-export-agent` deploys as a backward-compatible consumer that accepts absent summaries.
4. A future public archive-acceptance path carries the Platform operation ID to ChatGPT and Claude;
   only then can those producers emit terminal reports for that operation.

Rollback removes producer emission; deployed consumers continue to show unverified status rather
than a false complete result. No persisted schema migration or API version rollback is required.
