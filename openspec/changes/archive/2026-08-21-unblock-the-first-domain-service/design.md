# Design

Three decisions. Each is recorded with what was checked, because two of them contradict something a
document already said.

## 1. A producer reports; Platform snapshots

### What is true today

`ratatoskr-contracts` ships `OperationProgressed`, the payload of
`platform.operation.progressed.v1`. It carries one member: a full `OperationSnapshot`, whose required
fields are `operation_id`, `kind`, `status`, `retryable`, `correlation_id`, `accepted_at` and
`status_changed_at`, plus optional `stage`, `progress_percent`, `results`, `errors`, `warnings`,
`tenant_id` and `terminated_at`.

`ratatoskr-platform` reads a progress event in `crates/operations/src/projection.rs` and takes
`payload.operation_id` and `payload.status` — one level above where the published contract puts them,
which is `payload.operation.operation_id`. The test that covers it builds its own flat fixture with a
`message` field the snapshot does not have.

So the projection has never consumed the contract it names, and nothing has published that contract.
The mismatch is invisible because both sides of it are Platform's.

### The decision

**A domain service does not emit `platform.operation.progressed.v1`.**

It cannot emit it honestly. `kind` is the operation's kind, chosen by whoever accepted the request;
`accepted_at` is when Platform accepted it; `correlation_id` and `tenant_id` belong to the request
that created it. Extractor is handed an operation identifier and knows what it then did. Requiring a
producer to fill the snapshot would require every domain service to hold a copy of Platform's
operation record, which is the cross-context read `ARCHITECTURE.md` S4.2 forbids.

Two contracts, in opposite directions:

- **`platform.operation.reported.v1`** — producer to Platform. Its payload is exactly what a producer
  can know: the operation, the status it reached, and optionally a stage, a percentage, result
  references, and one error or several warnings.
- **`platform.operation.progressed.v1`** — Platform to clients. Unchanged, still the snapshot, still
  state-carried so a consumer needs no prior event.

Platform's projection consumes the first and keeps producing the second's content through
`GET /v1/operations/{id}` and the SSE stream.

### What was rejected

| Option | Outcome |
|---|---|
| Producers emit the snapshot | **Rejected.** It asks a producer for facts it does not hold, and buys them by copying Platform's record into every domain service. |
| Platform projects from each domain event directly | **Rejected.** Platform would have to understand `content.document.extracted.v1`, `github.repository.observed.v1` and every later one. That is domain knowledge in the control plane, which S4.2 and S10 both refuse. |
| Flatten the snapshot so producers can fill part of it | **Rejected.** A contract whose required half is filled by one party and whose optional half is filled by another is two contracts wearing one name, and the validation cannot say which one it is checking. |
| Leave the projection's hand-written shape and document it | **Rejected.** It is not published anywhere. The first producer would implement the contract, and the projection would silently ignore every event. |

### The consequence worth stating

A domain event and a report are two messages about one step. That is deliberate: the domain event is
a fact about the domain, addressed to whoever cares about documents; the report is a fact about the
operation, addressed to Platform. Collapsing them would put an operation identifier — Platform's
identifier — into the middle of every domain contract, and would make Platform a consumer of every
domain vocabulary.

## 2. Document IR blocks extractor's item 4, not its item 1

`ratatoskr-contracts` item 5, "Implement Document IR and provenance", is not built; the repository
ships four crates and none of them is it. Extractor's plan reaches the IR at item 4, "HTML parse-once
and Document IR primitives". Items 1 to 3 — scaffold, URL normalisation and SSRF policy, streaming
fetch and the raw artifact — touch no IR at all.

**So extractor starts now and contracts item 5 lands before extractor item 4.** Sequencing it as a
precondition of the whole service would hold three weeks of work behind a contract nobody has a
concrete use for yet, and a shape chosen with no implementation pressure on it is the shape that gets
rewritten.

Version one is the intersection of what extractor produces and what knowledge consumes, and nothing
else. Everything a single service needs and no other reads stays inside that service.

## 3. A blob is a reference, not a service

`BlobStore` is named in the documents of extractor, knowledge, github and vault. It is not one of the
sixteen repositories, no crate defines it, and no plan item in any repository creates it. Four
services depend on a component nobody owns.

**The decision: there is no blob service.** On the deployment target there is one host and one NVMe
device, so a blob service would be an HTTP hop to a local filesystem — a process to supervise, a port
to allocate, and a second copy of every byte in flight, in exchange for nothing.

What genuinely crosses a repository boundary is the **reference**: how a service names a stored byte
range so another service can find it and prove it is the right one. That is a contract, `BlobRef`,
and it carries the owning service, a content digest and the media type.

The bytes live under `/mnt/nvme/ratatoskr/blobs/<service>/` on the target, content-addressed, written
and read by the owning service alone. A second service that holds a `BlobRef` reads the file if it
runs on the same host and asks the owner otherwise; today everything runs on the same host.

Platform does not own it, and this is the one place that could be misread: `ARCHITECTURE.md` S4.2
says Platform does not own extracted documents, summaries or embeddings. A blob store inside Platform
would make it the owner of every one of them.

### What this does not decide

Off-host replication. Vault's plan item 7 is the fleet's only answer to a copy leaving the machine,
and it now has a simpler problem to solve: a directory tree rather than a service's API.
