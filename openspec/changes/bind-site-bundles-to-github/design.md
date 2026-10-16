# Design

## Context

See `proposal.md`. The current first-version `SiteManifest` and `SiteApprovalChanged` contain no
repository binding. SDK `src/cli/deploy.ts` verifies the OCI digest on the client and then uploads
raw tar. Sites `DeployStore::receive` checks file bytes and approval state but sees no signed origin.
The service unit has `MemoryHigh=384M` and `MemoryMax=512M` on the single shared host.

This is a plan. No runtime tool, credential, API or database change is made by these artifacts.

## Goals / Non-Goals

**Goals:** make the approved repository and verified build identity mandatory at storage and
activation, preserve current byte/path checks, and keep the verifier bounded within the existing
service budget.

**Non-Goals:** private registries, a new GitHub server token, a second host, live host provisioning,
new API majors, database migrations, unrelated contract repairs or an exception to signature checks.

## Decisions

### D1. Bind the repository in the first-version approval

Add `github_repository` with canonical lower-case `owner/name` and positive decimal repository ID
to the existing manifest, schema and generated types. The approval digest covers it; the approval
event carries it. During the expand step consumers decode its absence, but deploy refuses a site
without it. New approvals require it. Keep one API major. Edit current schema definitions in place.

Compare the attestation's verified certificate repository identity and numeric ID. Do not trust an
unsigned API response, request field, bundle manifest string or workflow-supplied predicate as the
identity. A transfer, rename or changed ID requires owner reapproval. The owner UI displays both.

An optional name-only string was rejected: it leaves name reuse and client claims as trust gaps.

### D2. Verify an immutable artifact on the server

The existing POST deploy route receives bounded JSON:
`{"commit":"<40 hex>","artifact_digest":"sha256:<64 hex>","attestation_bundle":<Sigstore bundle>}`.
It has no host, repository override, arbitrary URL, trusted root or command arguments. The server
constructs `ghcr.io/<approved owner/name>@<digest>` itself. Raw tar receives an unsupported-body
error; owner/primary sessions receive no exemption.

The client supplies an untrusted attestation bundle to avoid adding a server GitHub API credential.
The server fetches the raw OCI manifest at the requested digest and hashes its exact bytes. It
runs `gh attestation verify <manifest-file> --bundle <proof-file>` on those bytes, with fixed policy
flags for `--repo`, `--source-digest`, `--signer-workflow`, `--signer-digest`,
`--deny-self-hosted-runners`, the GitHub issuer, SLSA predicate and `--format json`. The verified
statement must name the same SHA-256 artifact. Repository ID comes from the verified certificate.
The approved workflow path is
`po4yka/ratatoskr-site-sdk/.github/workflows/reusable-site-bundle.yml`; its allowed full commit
is host configuration tied to a reviewed SDK release. No wildcard revision or client override.

`gh` supports local-bundle verification without its normal authentication check. A first apply
spike must demonstrate verification of the exact OCI manifest bytes against a real public artifact,
with an empty private tool configuration and no token. A fake verifier is not acceptance. If that
fails, stop for a design decision; do not add credentials or relax checks.

Fetch only the one expected tar layer after checking the OCI media type, descriptor count, sizes
and digest. Stream bounded bytes from `oras blob fetch`; do not extract registry paths or run
`oras pull` on arbitrary file descriptors. Compare its digest, then use the existing confined tar
receipt. Registry redirects must follow the registry's verified public blob flow only; never use
an untrusted request URL or forward credentials. This path must have negative SSRF tests.

The SDK can retain client verification for early feedback. It downloads the proof, resolves the
digest and sends the new request. Server verification remains authoritative.

### D3. Runtime dependencies, owner-approved 2026-10-16

Use pinned `gh` 2.102.0 (MIT) and `oras` 1.3.0 (Apache-2.0) as absolute, root-owned executables.
Both tools already occur in SDK/controller workflows but are new production runtime dependencies
of Sites. They add release tracking, signature/checksum verification, an ARM64/glibc compatibility
check, license notices and security-update maintenance. They do not add a Rust crypto library.

Run with a private empty configuration/home, no inherited token or credential helper, no shell,
fixed argv and a private staging directory. Use public GHCR anonymous access and local attestation
proofs only. Sigstore trust roots are server-controlled and updated through a reviewed, verified
artifact; a request cannot supply one. No personal credentials are read. Missing tools or roots
make readiness fail and deploy refuse; there is no fallback to the old raw-tar path.

The alternative is an in-process Sigstore/OCI library, with its own new dependency and maintenance
approval. A second alternative is server GitHub credentials; that adds a credential lifecycle and
is outside this proposal. The owner approved D3 after this plan was presented. The real proof, ABI and resource checks still gate implementation acceptance.

Primary references checked on 2026-10-16:

- [GitHub CLI verification policy and offline bundles](https://cli.github.com/manual/gh_attestation_verify).
- [CLI 2.102.0 disables its auth check for a local bundle](https://github.com/cli/cli/blob/v2.102.0/pkg/cmd/attestation/verify/verify.go).
- [GitHub CLI MIT license](https://github.com/cli/cli/blob/v2.102.0/LICENSE).
- [ORAS Apache-2.0 license](https://github.com/oras-project/oras/blob/v1.3.0/LICENSE).

### D4. Store proof and recheck authority

Keep the verified repository name/ID, artifact and source digests, signer workflow/revision,
policy version and verification timestamp with the stored deploy. Bind activation to that proof
and the current approval. Add columns in the current schema definition and create test databases
from it. Never treat an old directory without proof as verified. The current and previous links
change only after the final current-approval check and under the same serialization boundary as
activation. Test withdrawal/rebinding during a blocked verification call.

Idempotency is site plus commit plus verified artifact identity; a different digest for a stored
commit is a conflict. Concurrent requests cannot replace stored proof. A retry cannot skip proof
checks based only on an existing directory. Rollback to an approved, already verified deploy needs
no network, but still checks current approval and policy. Revocation affects later deploy/activation;
existing public serving follows the current approval projection rules.

### D5. Bound verification and fail closed

Start with one verification slot, a 120-second total deadline, a 1 MiB JSON/proof bound, 1 MiB per
metadata/output stream, at most one tar layer and the existing configured archive bound. Kill and
reap the whole subprocess group on timeout, cancellation or shutdown; clean staging on every exit.
Use streaming archive IO, not an unbounded capture. The deployment test must show both tools inside
the existing 512 MiB service limit. If it does not, stop for a budget decision instead of increasing
host limits. Record stable payload-free error codes and low-cardinality counters, never raw proof,
registry responses or environment variables in logs.

## Risks / Trade-offs

- Public GHCR availability and limits affect deployment. Fail closed and allow a bounded retry;
  existing serving stays independent of network verification.
- A valid signature from a compromised trusted workflow still passes identity checks. Pin the
  reusable workflow revision, isolate build permissions and require reviewed workflow updates.
- CLI JSON and certificate extension formats can change. Pin versions, test real proof parsing,
  and reject missing/unknown required identity claims.
- This changes a first-version body and manifest. Ship expanded consumers before producers; old
  clients fail clearly until updated. Do not add a raw-upload bypass for compatibility.
- The existing contracts pin guard makes this a fleet change even for unrelated Rust consumers.
  Their gates are required; no sibling path dependency is committed.

## Migration Plan

This heading describes rollout; no database migration file or framework is added.

1. Create the SITE-028 changeset and isolated writer worktrees. Obtain the D3 dependency decision.
2. Run the real credential-free proof spike. Add contracts in an expand step, regenerate types,
   and move every Rust consumer to one contracts commit with its own local gate and green CI.
3. Ship Sites decoding/proof verification and mandatory refusals before the updated producers and
   clients use the new request. New deploys of unbound sites fail; public serving keeps its approval
   behavior. Platform approval must require the binding before it produces new approvals.
4. Update Platform, SDK and Web, reapprove synthetic sites and exercise success, failure, race,
   cancellation, rollback and idempotency paths with real signed public evidence.
5. Validate disposable provisioning and memory bounds, then publish the verified workspace pins.
   Do not touch the frozen production host.
6. If verification fails, stop deploy writes. Preserve the last verified served bundle. A rollback
   that removes provenance enforcement requires explicit owner approval because it reopens the gap.
