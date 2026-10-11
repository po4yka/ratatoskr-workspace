## ADDED Requirements

### Requirement: An authoritative provider deletion removes the owner's source

When X's public lookup reports a post as deleted for a capture whose `(owner, provider_post_id)` already has a stored source, the terminating transaction SHALL delete that source row, enqueue one `social.source.removed.v1` envelope (producer `ratatoskr-x`, `tenant_id user:<owner>`, payload `{social_source_id, owner, reason, removed_at}`), and still report `failed` with `social.source.deleted`. The closed removal reason has no provider-deleted variant and adding one is a contract change, so the reason is `retention_policy`. An inaccessible or transient outcome SHALL remove nothing, because the app-only token cannot tell a protected post from a restricted one. A later capture of a restored post is a new source, admitted because its capture time is after the removal. The bookmark and compliance lane stays dormant and is not part of this requirement.

#### Scenario: A previously captured post is deleted at the provider

- **WHEN** an owner re-captures a post that the provider now reports deleted
- **THEN** the stored source is gone, one removal fact is published for Knowledge, and the operation ends `failed` with `social.source.deleted`, verified by `crates/x-sync/tests/public_capture/removal.rs` in `ratatoskr-x`

#### Scenario: The post is protected rather than deleted

- **WHEN** the lookup answers inaccessible
- **THEN** the stored source and Knowledge's derived state remain

### Requirement: Provider permalink hosts agree across the extension, Platform and the services

Platform's capture routing SHALL accept the four Threads hosts `threads.net`, `www.threads.net`, `threads.com` and `www.threads.com`, and the browser extension SHALL route the four Threads hosts and all six X hosts (`x.com`, `www.x.com`, `mobile.x.com`, `twitter.com`, `www.twitter.com`, `mobile.twitter.com`) to their provider lanes. The path expressions are unchanged and the Threads service keeps canonicalizing to `www.threads.net`.

#### Scenario: A Threads permalink on the current domain

- **WHEN** a user submits a `threads.com` permalink
- **THEN** Platform dispatches it to the Threads lane instead of the generic extractor, verified by `crates/public-api/tests/capture.rs` in `ratatoskr-platform`

#### Scenario: A twitter.com permalink in the extension

- **WHEN** the extension sees a `twitter.com` status permalink
- **THEN** it routes it to the X lane
