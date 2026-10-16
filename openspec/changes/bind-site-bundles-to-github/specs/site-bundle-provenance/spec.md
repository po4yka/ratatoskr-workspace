# Site bundle provenance

## Purpose

Binds each stored and activated site bundle to the repository that the owner approved and to a
verified build identity, so deployment authority alone cannot replace signed provenance.

## ADDED Requirements

### Requirement: Approval binds one repository identity

The site manifest SHALL carry one GitHub repository name and immutable numeric repository ID. The approval digest and approval event SHALL bind both values. A name or ID change SHALL require a new owner approval before another deploy can be stored or activated.

#### Scenario: A repository changes without approval

- **WHEN** a deploy names a repository different from the current approved name or ID
- **THEN** the server refuses it, stores no deploy and changes no current or previous link

#### Scenario: A repository name is reused

- **WHEN** a valid attestation has the approved name but a different immutable repository ID
- **THEN** the server refuses it as a repository mismatch

### Requirement: The server verifies the artifact identity

Before storage, the server SHALL verify a signed attestation binding the actual OCI artifact digest to the approved repository, requested source commit and allowed workflow identity and revision. The issuer SHALL be GitHub Actions, the predicate SHALL be SLSA provenance, and the runner SHALL be GitHub-hosted. Client assertions alone SHALL confer no trust.

#### Scenario: The approved build is deployed

- **WHEN** a request carries a valid attestation for the exact fetched digest, approved repository and allowed build identity
- **THEN** the server stores the checked bundle and its verified provenance

#### Scenario: A provenance claim is substituted

- **WHEN** the signature, issuer, repository, digest, source commit, workflow identity, workflow revision or runner type fails verification
- **THEN** the server refuses the deploy and stores no deploy or activation state

### Requirement: Unverified upload paths are closed

The deploy route SHALL require the immutable artifact request and its bounded proof. Raw tar, missing proof and an owner or primary session SHALL NOT bypass provenance verification. The existing deploy authority checks SHALL also apply.

#### Scenario: A raw archive is submitted

- **WHEN** an authorized caller sends a raw tar archive to the deploy route
- **THEN** the route refuses it before storing any deploy

#### Scenario: An owner submits an unsigned bundle

- **WHEN** the owner's valid session submits a request without verifiable provenance
- **THEN** it is refused by the same provenance policy as a deployer session

### Requirement: Fetches use an approved immutable registry path

The server SHALL construct the public GHCR repository path from the current approval and fetch only by a validated SHA-256 digest. A client SHALL NOT choose a host, URL, redirect target, repository path, credential source or mutable tag.

#### Scenario: A client supplies another origin

- **WHEN** a request supplies a URL, host, arbitrary path or tag in place of the digest
- **THEN** validation fails before an outbound request

#### Scenario: The tag moves during deployment

- **WHEN** the original tag moves after the client resolves its digest
- **THEN** the server checks and stores only the artifact at the requested immutable digest

### Requirement: Fetched bytes match the verified artifact

The server SHALL check the raw OCI manifest digest, its allowed media type and one expected archive layer. It SHALL check that layer's digest and size, then apply all existing bundle manifest, site, path, file digest and size checks. No fetched file path SHALL bypass those checks.

#### Scenario: A registry returns changed bytes

- **WHEN** the OCI manifest, archive layer or a listed bundle file differs from its verified digest or size
- **THEN** the deploy is refused and no complete bundle becomes visible

### Requirement: Activation uses the current approval

Storage and activation SHALL recheck the current approval. Stored provenance SHALL match its repository binding and allowed workflow policy. Withdrawal or rebinding during verification SHALL prevent storage and activation. Unverified historical deploys SHALL NOT become current through rollback or idempotency paths.

#### Scenario: Approval changes during verification

- **WHEN** the owner withdraws or changes the approval while a deploy is verified
- **THEN** the pending deploy cannot be stored or activated under the old approval

#### Scenario: An old deploy is activated after rebinding

- **WHEN** activation or rollback names a deploy whose verified repository differs from the current approval
- **THEN** it is refused and the current and previous links do not change

### Requirement: An idempotent deploy cannot replace provenance

The same site, commit and verified artifact identity SHALL return the stored deploy. A request for the same site and commit with another artifact identity SHALL be refused as a conflict, including under concurrent requests.

#### Scenario: A commit is supplied with another digest

- **WHEN** a stored site's commit is submitted with a different artifact digest
- **THEN** the server returns a conflict and preserves the stored bytes and provenance

### Requirement: Verification has bounded resource use

Verification SHALL have finite time, concurrency, metadata, output and archive limits. Timeout, cancellation, unavailable proof, tool failure and exhausted capacity SHALL refuse or defer the request without accepting it or leaking child processes or temporary bytes. Failure SHALL NOT enable a verification bypass.

#### Scenario: Verification exceeds its deadline

- **WHEN** a fetch or verifier does not finish before its configured deadline
- **THEN** the request fails, its child processes stop, its temporary files are removed and no deploy is stored

#### Scenario: Metadata or archive exceeds its bound

- **WHEN** a proof, tool output, OCI descriptor or archive exceeds its configured bound
- **THEN** verification stops and the request cannot store or activate a deploy

#### Scenario: A request is cancelled

- **WHEN** a caller disconnects or the service stops during verification
- **THEN** the pending work stops and cannot later publish a deploy
