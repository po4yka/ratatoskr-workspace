## Purpose

Defines the evidence required before an integrated Export Agent build is published at the manual
update destination and described as an installable Ratatoskr product.

## ADDED Requirements

### Requirement: Release publication is bound to an integrated exact revision set
An Export Agent release SHALL identify the exact unchanged Contracts input and the Platform,
ChatGPT, Claude, Export Agent, and workspace revisions that passed the synthetic product flow. The
artifact source revision MUST be contained by the recorded integrated Export Agent revision, and the
release MUST NOT be published from dirty, local-only, or moving revision inputs.

#### Scenario: Integrated revisions are publishable inputs
- **WHEN** the exact clean revisions have passed the task-namespaced product profile and are recorded
  in the workspace changeset
- **THEN** the owner-authorized release workflow may build the Export Agent artifact from that exact
  source revision

#### Scenario: Unintegrated client revision is refused
- **WHEN** a requested release source has not passed the recorded exact-revision product profile
- **THEN** the release workflow fails before signing or publishing an artifact

### Requirement: Published application trust is fail-closed
Every published application SHALL carry the stable product identity, exact sandbox entitlements,
hardened Developer ID Application signature with secure timestamp, accepted and stapled Apple
notarization ticket, successful signature validation, and successful Gatekeeper assessment. Missing
owner credentials or any failed trust check SHALL publish nothing described as signed, notarized, or
release-ready.

#### Scenario: Apple accepts the integrated build
- **WHEN** valid owner credentials are available and every signing, notarization, stapling,
  signature, and Gatekeeper check succeeds
- **THEN** the workflow may publish the digest-addressed ZIP and its checksum

#### Scenario: Owner credentials are absent
- **WHEN** one or more required signing or notarization secrets are unavailable
- **THEN** the workflow reports the missing secret names and publishes no release artifact

### Requirement: Clean-machine acceptance exercises the installed product flow
Before a release is called accepted, its published ZIP SHALL be installed on a compatible clean Mac
and SHALL pass first launch, explicit folder authorization, Platform pairing, relaunch restoration,
synthetic upload, terminal status, manual-update navigation, and uninstall or rollback observation.
The acceptance record SHALL distinguish Apple trust, clean-machine behavior, and workspace
integration evidence.

#### Scenario: Fresh installation completes a synthetic import
- **WHEN** the published application is installed on a clean compatible Mac and paired to the
  synthetic integrated environment
- **THEN** one selected synthetic archive reaches truthful terminal status and remains locally
  preserved across an application relaunch

#### Scenario: Local packaging is not clean-machine evidence
- **WHEN** only an ad hoc or development bundle has passed tests on the build Mac
- **THEN** no acceptance record labels it notarized, published, or clean-machine verified

### Requirement: Manual update destination resolves to the published release
The application's fixed manual-update action SHALL open a release destination containing the exact
accepted artifact and checksum. A workflow artifact with temporary retention SHALL NOT be the sole
published update channel.

#### Scenario: Accepted release is discoverable from the app
- **WHEN** a user invokes the manual update action after publication
- **THEN** the opened release page identifies the accepted version and exposes its ZIP and checksum

#### Scenario: No release exists
- **WHEN** no accepted release has been published
- **THEN** the application and documentation do not claim that a downloadable update is available
