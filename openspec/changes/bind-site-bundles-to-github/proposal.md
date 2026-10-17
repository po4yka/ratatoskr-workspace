# Proposal

## Why

At change start, a site approval bound no GitHub repository, and the Sites server accepted a tar archive
without checking its signed origin. The owner chose server verification so a paired deployer cannot
substitute a foreign or unsigned bundle.

## What Changes

- Bind one GitHub repository identity to each site manifest and owner approval.
- Make the server verify the immutable artifact digest, source commit and trusted reusable workflow
  before it stores or activates a deploy. Refuse missing or unverifiable provenance.
- **BREAKING**: replace the raw-tar deploy request with an immutable GHCR artifact reference on the
  existing first-version route. Update the SDK, approval UI and integration fixtures together.
- Keep verified provenance with each stored deploy, and refuse activation after repository rebinding
  or approval withdrawal until the deploy satisfies the current approval.
- Plan a bounded verifier on the one host. Adding runtime tools or credentials requires a separate
  explicit owner decision; this proposal does not authorize their installation.

## Capabilities

### New Capabilities

- `site-bundle-provenance`: the server enforces the approved repository and verified build identity
  at deploy storage and activation.

### Modified Capabilities

None. `site-bundles` and `site-manifest` are active, unarchived changes. This additive capability
supersedes their weaker raw-upload boundary when implemented; those deltas must be reconciled
before either change is archived. The existing `release-artifacts` spec covers service binaries,
not site bundles, and is unchanged.

## Impact

Contracts merge first. Then all consumers move to the same contracts commit, followed by producers,
clients and the verified workspace snapshot:

1. `ratatoskr-contracts`: first-version manifest, approval event, deploy request, schemas and types.
2. `ratatoskr-sites`: approval projection, provenance verification, stored proof and activation checks.
3. `ratatoskr-platform`: approved repository identity, approval digest/event and deploy request proxy.
4. `ratatoskr-site-sdk`: immutable artifact request and trusted workflow policy.
5. `ratatoskr-web`: display and approve the repository binding and its changes.
6. `ratatoskr-extractor`, `ratatoskr-knowledge`, `ratatoskr-github`, `ratatoskr-vault`, `ratatoskr-x`,
   `ratatoskr-instagram`, `ratatoskr-threads`, `ratatoskr-chatgpt`, `ratatoskr-claude`,
   `ratatoskr-telegram`, `ratatoskr-channel-digests`, `ratatoskr-notes`: contracts pin only, with each
   repository's own gate. The fleet requires one contracts revision.
7. `ratatoskr-workspace`: changeset SITE-028, integration, verifier provisioning tests and final pins.

Generated TypeScript consumers in the SDK and Web move with their owners. The apply discovery must
check for other generated consumers before changing contracts. No repository imports sibling paths.

Outside scope: real Obsidian Sync/iOS, support terms, live production provisioning, private GitHub
repositories, new API major versions, database migrations and unrelated historical contracts tasks.

The child implementation is published. SITE-028 records its commits and checks; workspace pin
promotion and final acceptance are tracked there separately. During implementation, consumers accept the new optional
binding before producers emit it, then enforcement requires it and rejects raw tar. Existing sites
without a binding cannot accept a new deploy after enforcement. No parallel major API is added.
Rollback stops deploy writes and restores the prior verified snapshot as a set; restoring the old
raw-tar endpoint is a security downgrade and requires explicit owner approval. Do not present it as
a transparent safe rollback.
