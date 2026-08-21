# Unblock the first domain service

## Why

Platform is complete through milestone 10 and running on the deployment target. It accepts a capture
through `POST /v1/captures` and through the webhook adapter, writes an operation, and publishes
`cmd.content.capture.requested.v1` to JetStream.

Nothing consumes it. `ratatoskr-extractor`, `ratatoskr-knowledge`, `ratatoskr-github` and
`ratatoskr-vault` hold documents and no code. Every command published on the target expires unread
after seven days and every operation stays `accepted` for ever.

Extractor is the service that closes that loop — it is the only one whose documented input is the
command Platform already emits. Three things block it, and none of them is extractor's to decide:

1. **A domain service cannot report progress on a Platform operation.** The only contract for it,
   `platform.operation.progressed.v1`, carries a full `OperationSnapshot`, and a producer does not
   know most of that snapshot. Platform's own projection does not read that contract either.
2. **Document IR does not exist.** It is contracts item 5, unbuilt. It is extractor's output and
   knowledge's input.
3. **BlobStore has no owner.** Extractor, knowledge, github and vault all name it; it is not one of
   the sixteen repositories and no crate defines it.

This change decides all three at the boundary, so that extractor's proposal can be about extraction.

## What changes

- A domain service reports progress through a new small contract, `platform.operation.reported.v1`,
  carrying only what a producer can know. `platform.operation.progressed.v1` keeps its snapshot and
  becomes what Platform emits **to** clients rather than what producers emit to Platform.
- Platform's operation projection consumes the reported contract by its published field names,
  replacing a hand-written shape that nothing publishes.
- Document IR version one is the intersection of what extractor produces and knowledge consumes,
  and it is required before extractor's plan item 4 rather than before its item 1.
- A blob is a reference and a path convention, not a service. `BlobRef` is a contract; the bytes
  live under a per-service directory on the deployment target's NVMe.

## Repositories, in dependency order

| # | Repository | What it merges |
|---|---|---|
| 1 | `ratatoskr-contracts` | `OperationReported`, `BlobRef`, and Document IR version one |
| 2 | `ratatoskr-platform` | the projection reads the published contract; `docs/DEVELOPMENT.md` Q3 closes |
| 3 | `ratatoskr-extractor` | consumes the command, emits its domain event and a report |
| 4 | `ratatoskr-knowledge` | reads Document IR when it starts; nothing to merge in this change |

Contracts merges first because both consumers and producers depend on the types. Platform is second
because it is a consumer and can land before any producer exists. Extractor is third.

## What stays outside

- **Platform emitting `platform.operation.progressed.v1`.** The contract keeps its meaning and
  Platform keeps not publishing it: SSE serves clients from the projection today, and the second
  consumer that needs the event does not exist yet. Named here so it is not mistaken for an
  oversight.
- **Extractor's own design.** Fetching, SSRF policy, candidates and quality evaluation are its
  proposal, not this one.
- **Off-host blob replication.** Vault's plan item 7 is the fleet's only answer to it and this
  change does not pre-empt that decision; it only removes the assumption that a blob service exists.
- **The social, archive and client repositories.** They consume Document IR later and add nothing
  to it now.

## Rollback

None is needed and none exists. No database on the target holds data that must survive a schema
change, no consumer outside the fleet reads these contracts, and `platform.operation.reported.v1`
has no previous version to be compatible with. If the shape proves wrong it is edited in place, as
the development status allows.
