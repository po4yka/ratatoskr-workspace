## Purpose

Defines the deployable single-host routes and least-privilege event path that let ChatGPT and Claude
accept verified archives and report terminal import truth back to Platform.

## ADDED Requirements

### Requirement: Each archive provider has one distinct loopback receipt boundary
The single-host deployment SHALL configure Platform with one ChatGPT receipt listener and one Claude
receipt listener on distinct reserved loopback ports. Each provider process SHALL bind only its own
port and fixed archive receipt path. Platform readiness SHALL report archive acceptance unavailable
for a provider whose configured receipt target is absent or invalid.

#### Scenario: Both providers start without a port collision
- **WHEN** the single-host configuration starts Platform, ChatGPT, and Claude together
- **THEN** ChatGPT and Claude each listen on their reserved loopback port and Platform advertises
  both archive routes as ready

#### Scenario: Claude receiver is absent
- **WHEN** the Claude receipt process is stopped while ChatGPT remains healthy
- **THEN** Platform refuses new Claude preparation without disabling the ChatGPT route

### Requirement: Provider operation reports traverse the secured fleet bus
ChatGPT and Claude SHALL authenticate to the secured fleet bus with separate service identities.
ChatGPT SHALL publish operation reports only on
`evt.ai-archive.chatgpt.operation.reported.v1`, and Claude SHALL publish operation reports only on
`evt.ai-archive.claude.operation.reported.v1`. These are provider-scoped runtime ingress subjects for
the unchanged `platform.operation.reported.v1` EventEnvelope document. Each identity SHALL have no
permission to publish another provider's ingress subject or subscribe to unrelated fleet traffic.
Platform SHALL consume the two-subject family, require the envelope producer to match the ingress
subject and the operation's bound provider, and durably apply valid owner-correlated terminal
reports.

#### Scenario: ChatGPT terminal report reaches Platform
- **WHEN** ChatGPT finishes a correlated synthetic import and publishes its valid terminal report
- **THEN** Platform's operation read eventually exposes that terminal state and its bounded import
  summary

#### Scenario: Claude identity cannot impersonate ChatGPT
- **WHEN** the Claude bus identity attempts to publish on the ChatGPT-only operation subject
- **THEN** the secured bus denies publication and Platform's ChatGPT operation remains unchanged

#### Scenario: Anonymous producer is rejected
- **WHEN** an archive producer connects without its configured service credential
- **THEN** the secured bus refuses its operation-report publication

### Requirement: Provider receipt completion is truthful and idempotent
Each provider SHALL verify the injected operation, digest, and size claims against the received bytes,
preserve one raw archive identity, run its existing import and completeness workflow, and publish one
terminal report for that operation. Re-delivery of the same verified operation SHALL not duplicate
raw storage, imported entities, or terminal reports with conflicting facts.

#### Scenario: Synthetic archive reaches terminal completeness
- **WHEN** a verified synthetic provider export is accepted at its receipt boundary
- **THEN** the provider stores it once, completes its import, and reports a terminal bounded summary
  for the injected operation

#### Scenario: Receipt replay is idempotent
- **WHEN** Platform repeats delivery for the same operation and exact bytes after an uncertain
  acknowledgement
- **THEN** the provider returns the prior acceptance and creates no duplicate import

### Requirement: Deployment readiness covers the complete archive path
Platform SHALL report the AI archive product path ready only when its database, secured report
consumer, and both configured provider receipt routes meet their required health contract. Provider
service readiness SHALL include its raw archive store, import worker, and authenticated report
publisher. A degraded dependency SHALL fail readiness without fabricating completed work.

#### Scenario: Report publisher loses bus authority
- **WHEN** a provider can receive archives but cannot authenticate its operation-report publisher
- **THEN** that provider is not ready and Platform does not advertise its archive route as ready

#### Scenario: Full runtime becomes ready
- **WHEN** Platform, both receipt/import paths, and their secured report publishers are healthy
- **THEN** the deployment exposes both authenticated archive routes as ready for the Export Agent
