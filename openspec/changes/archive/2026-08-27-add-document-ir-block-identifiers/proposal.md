## Why

User highlights must refer to text that remains unambiguous when a document has repeated or reordered
blocks. The current shared Document IR has ordered blocks but no stable block identity, so a
cross-repository contract change is required before Knowledge can persist valid highlight anchors.

## What Changes

- Modify `document-ir` so every published block carries one stable block identifier in the current
  first-version contract.
- Define identity stability within one immutable document revision; no cross-revision identifier
  mapping or automatic highlight rebasing is introduced.
- Define that consumers validate `(document_id, content_digest, block_id, start_offset, end_offset)`
  against the supplied immutable Document IR revision and count offsets as Unicode scalar values.
- Roll out in dependency order: `ratatoskr-contracts` publishes the changed type and serialization;
  this workspace ratifies the contract; `ratatoskr-knowledge` consumes it for highlight validation;
  `ratatoskr-extractor` produces block identifiers. No compatibility routing or parallel contract
  version is introduced because no production Document IR deployment or retained database data exists.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `document-ir`: Blocks gain stable identifiers and bounded offset-anchor validation semantics for
  downstream annotations.

## Impact

Affected repositories, in dependency order: `ratatoskr-contracts` (contract owner, first), this
workspace (ratified specification and changeset), `ratatoskr-knowledge` (highlight consumer), and
`ratatoskr-extractor` (Document IR producer, last). Public links, multi-user annotations, legacy
imports, and any source-fetching behavior remain outside the change. Rollback before deployment is a
revert of the child changes and workspace pin; no database migration or data recovery path is needed.
