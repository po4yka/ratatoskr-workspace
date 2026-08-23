## Purpose

Defines the rendering contract between the extractor and the isolated browser worker: how a render
job is requested, what the worker must enforce while executing it, and what evidence it returns.
Both deployables belong to the Ratatoskr extractor fleet; the browser worker runs Chromium in a
separate process, container, and security domain.

## ADDED Requirements

### Requirement: Render jobs travel as durable commands with BlobRef evidence

The extractor SHALL request rendering by publishing `cmd.content.render.requested.v1` carrying a
unique `render_id`, the operation identity, one target URL, and finite budgets. The browser worker
SHALL consume that command from a durable JetStream work queue, execute at most one navigation per
job in a fresh browser context, store the rendered DOM bytes under its own ownership, and publish
`evt.content.render.completed.v1` announcing them by `BlobRef` together with a network-evidence
summary — final URL, redirect hops with status and media type, and blocked-request counts. A job
that cannot produce a usable document SHALL publish `evt.content.render.failed.v1` with a stable
failure class. No event SHALL carry response bodies, cookies, credentials, or storage state.

#### Scenario: a requested page renders into owned bytes

- **WHEN** a render command names a public URL inside budget
- **THEN** exactly one completion event follows with a `BlobRef` owned by the browser worker whose
  digest matches the rendered DOM bytes, plus a network-evidence summary

#### Scenario: delivery is at-least-once but a replay changes nothing

- **WHEN** the same render command redelivers after a worker crash
- **THEN** the worker either completes the job once or publishes nothing further for an already
  completed `render_id`, and no second context is opened for it

### Requirement: Every job runs isolated with denied credentials and blocked resources

The worker SHALL open a fresh browser context per job, SHALL NOT accept or inject cookies,
authorization headers, storage state, or any caller-supplied credential, SHALL disable downloads,
and SHALL close the context when the job ends however it ends. Request interception SHALL deny
images, fonts, media, and WebSocket traffic by default and allow only document, script, stylesheet,
fetch, and xhr traffic needed to hydrate the page.

#### Scenario: a caller cannot smuggle an authenticated session

- **WHEN** a render command arrives with cookie, token, or storage-state fields
- **THEN** those fields are absent from the schema, so the command cannot express them, and the
  rendered context starts without any prior site state

#### Scenario: heavy subresources never load

- **WHEN** a rendered page references images, fonts, media, or WebSocket endpoints
- **THEN** those requests are denied before leaving the browser and counted in the evidence summary

### Requirement: The worker revalidates every navigation destination

Before navigating, and again on every redirect hop, the worker SHALL validate the destination
against the same SSRF policy class the extractor applies — scheme allowlist, host and port policy,
resolved-address checks excluding loopback, private, link-local, multicast, and metadata ranges —
and SHALL fail the job with a policy failure class instead of navigating when validation refuses.
Policy refusals SHALL be distinguishable from transport failures in the failed event's class.

#### Scenario: a redirect toward internal space is refused

- **WHEN** a rendered page redirects toward an address the policy forbids
- **THEN** the worker fails the job with the policy failure class, navigates no further, and
  publishes no DOM bytes

### Requirement: Jobs are bounded end to end

The worker SHALL enforce the command's budgets: a navigation timeout, a total job timeout, and a
maximum response byte count for the captured DOM. Exceeding any budget SHALL fail the job with the
matching timeout or size failure class, never a hang. The deployment SHALL bound the worker
process's memory and process count independently of this contract.

#### Scenario: an endless page cannot hang the pipeline

- **WHEN** a target keeps loading beyond its budgets or grows past the byte cap
- **THEN** the worker publishes a failed event naming the exceeded budget within the total timeout

### Requirement: Escalation stays deterministic and rare on the extractor side

The extractor SHALL decide to escalate only from deterministic evidence about the direct attempt —
an empty JavaScript shell or a rejected low-quality extraction of hydration-shaped content — and
SHALL bound escalation frequency per host. While a render job is outstanding the original run
SHALL keep its lease renewed; on completion the extractor SHALL re-parse the returned DOM through
the ordinary HTML path with the same candidates, evaluator, provenance rules, and events; on
failure the run SHALL terminate with the render failure class carried from the worker.

#### Scenario: a hydrated page completes through the ordinary path

- **WHEN** a direct extraction rejects an empty shell and the escalated render completes
- **THEN** the extracted Document IR is produced from the rendered DOM by the same parser and
  evaluator, carries provenance naming the rendered artifact, and publishes the standard
  completion events

#### Scenario: escalation cannot loop

- **WHEN** the rendered DOM itself fails quality thresholds
- **THEN** the run terminates with an explicit degraded class and no second render is requested
