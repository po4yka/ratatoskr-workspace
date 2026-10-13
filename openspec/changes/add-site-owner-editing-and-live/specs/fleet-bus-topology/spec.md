# Spec Delta

This delta requires `add-site-gateway-hosting` (SITE-026) to be archived first.

## MODIFIED Requirements

### Requirement: The fixed durables and the completion bucket are provisioned by Edge

Edge SHALL create, after declaring the two streams, every durable in the following table and the key-value bucket `browser_worker_completions` (maximum age 24 hours, direct get allowed). All are pull consumers with instant replay and no delivery subject. Existing durables are unchanged: `platform_edge_projection`, `platform_ai_archive_chatgpt_projection`, `platform_ai_archive_claude_projection`, `ratatoskr_telegram_notifications`, `ratatoskr_x_browser_capture`, `ratatoskr_instagram_browser_capture` and `threads_browser_capture`; `platform_schedule_registration`, `platform_stream_erasure` (the commands stream, filter `cmd.platform.stream_erasure.requested.v1`) and `platform_notes_conflict_projection` (the events stream, filter `evt.notes.conflict.>`, ack wait 30 s, unlimited deliveries, explicit acknowledgement, owner EDGE, which projects note conflicts onto `notes.file.write` operations) and `platform_site_events` (the events stream, filters `evt.sites.release.published.v1` and `evt.sites.draft.changed.v1`, ack wait 30 s, unlimited deliveries, explicit acknowledgement, owner EDGE, which feeds the site event stream `/v1/sites/{site}/events`) are created by Edge's own consumers. The table holds 30 service durables.

| Stream | Durable | Filter | Ack wait | Max deliver | Owner identity |
|---|---|---|---|---|---|
| commands | `ratatoskr_extractor_capture` | `cmd.content.capture.requested.v1` | 30 s | 12 | EXTRACTOR |
| commands | `ratatoskr_browser_worker` | `cmd.content.render.requested.v1` | 300 s | 12 | EXTRACTOR_BROWSER_WORKER |
| commands | `ratatoskr_knowledge_channel_recap` | `cmd.knowledge.channel_digest_recap.requested.v1` | 30 s | unlimited | KNOWLEDGE |
| commands | `ratatoskr_channel_digest_subscriptions` | `cmd.channel_digest.subscription.set_requested.v1` | 30 s | unlimited | CHANNEL_DIGESTS |
| commands | `ratatoskr_channel_digest_runs` | `cmd.channel_digest.run.requested.v1` | 30 s | unlimited | CHANNEL_DIGESTS |
| commands | `ratatoskr_channel_digest_schedule_occurrences` | `cmd.channel_digest.schedule.occurrence_requested.v1` | 30 s | unlimited | CHANNEL_DIGESTS |
| commands | `ratatoskr_vault_backup_policy` | `cmd.vault.backup_policy.apply_requested.v1` | 30 s | unlimited | VAULT |
| commands | `ratatoskr_notes_write_requests` | `cmd.notes.file.write_requested.v1` | 30 s | unlimited | NOTES |
| events | `ratatoskr_knowledge_documents` | `evt.content.document.extracted.v1` | 120 s | unlimited | KNOWLEDGE |
| events | `ratatoskr_knowledge_social_sources` | `evt.social.source.>` | 120 s | unlimited | KNOWLEDGE |
| events | `ratatoskr_knowledge_ai_archive` | `evt.ai_archive.>` | 120 s | unlimited | KNOWLEDGE |
| events | `ratatoskr_knowledge_repository_requests` | `evt.knowledge.repository_analysis.requested.v1` | 120 s | unlimited | KNOWLEDGE |
| events | `ratatoskr_knowledge_notes_files` | `evt.notes.file.changed.v1` | 120 s | unlimited | KNOWLEDGE |
| events | `ratatoskr_knowledge_notes_vaults` | `evt.notes.vault.>` | 120 s | unlimited | KNOWLEDGE |
| events | `ratatoskr_github_analysis_completed` | `evt.knowledge.repository_analysis.completed.v1` | 30 s | unlimited | GITHUB |
| events | `ratatoskr_github_analysis_failed` | `evt.knowledge.repository_analysis.failed.v1` | 30 s | unlimited | GITHUB |
| events | `ratatoskr_github_policy_acknowledged` | `evt.vault.backup_policy.acknowledged.v1` | 30 s | unlimited | GITHUB |
| events | `ratatoskr_x_extractor_reports` | `evt.platform.operation.reported.v1` | 30 s | unlimited | X |
| events | `ratatoskr_channel_digest_recap_completed` | `evt.knowledge.channel_digest_recap.completed.v1` | 30 s | unlimited | CHANNEL_DIGESTS |
| events | `ratatoskr_channel_digest_recap_failed` | `evt.knowledge.channel_digest_recap.failed.v1` | 30 s | unlimited | CHANNEL_DIGESTS |
| events | `ratatoskr_chatgpt_deletion_acks` | `evt.knowledge.deletion.acknowledged.v1` | 30 s | unlimited | CHATGPT |
| events | `ratatoskr_claude_deletion_acks` | `evt.knowledge.deletion.acknowledged.v1` | 30 s | unlimited | CLAUDE |
| events | `ratatoskr_x_deletion_acks` | `evt.knowledge.deletion.acknowledged.v1` | 30 s | unlimited | X |
| events | `ratatoskr_instagram_deletion_acks` | `evt.knowledge.deletion.acknowledged.v1` | 30 s | unlimited | INSTAGRAM |
| events | `ratatoskr_threads_deletion_acks` | `evt.knowledge.deletion.acknowledged.v1` | 30 s | unlimited | THREADS |
| events | `ratatoskr_extractor_render_awaits` | `evt.content.render.>` | 30 s | unlimited | EXTRACTOR |
| commands | `ratatoskr_sites_release_builds` | `cmd.sites.release.build_requested.v1` | 300 s | unlimited | SITES |
| events | `ratatoskr_sites_note_changes` | `evt.notes.file.changed.v1` | 120 s | unlimited | SITES |
| events | `ratatoskr_sites_vault_disconnections` | `evt.notes.vault.disconnected.v1` | 30 s | unlimited | SITES |
| events | `ratatoskr_sites_approvals` | `evt.platform.site_approval.changed.v1` | 30 s | unlimited | SITES |

Every events-stream durable other than `ratatoskr_extractor_render_awaits` uses explicit acknowledgement and delivers all messages; `ratatoskr_extractor_render_awaits` uses no acknowledgement and delivers only messages published after it is created. Knowledge's ingest acknowledgement wait SHALL equal the 120 seconds of its durables.

#### Scenario: A fresh broker starts in the documented order

- **WHEN** the operator reloads NATS with the reviewed configuration, starts Edge, and then starts the other services
- **THEN** every service finds its durable and becomes ready, verified by the real-broker matrix in `ratatoskr-platform` (`crates/eventing/tests/nats_permissions.rs`)

#### Scenario: The notes write durables are provisioned

- **WHEN** Edge starts against a fresh broker with the reviewed configuration
- **THEN** `ratatoskr_notes_write_requests` exists on the commands stream with the filter `cmd.notes.file.write_requested.v1` and `platform_notes_conflict_projection` exists on the events stream with the filter `evt.notes.conflict.>`, each with an ack wait of 30 s, verified by `crates/eventing/tests/stream_table.rs::notes_write_durables_are_provisioned` in `ratatoskr-platform`

#### Scenario: The sites durables are provisioned

- **WHEN** Edge starts against a fresh broker with the reviewed configuration
- **THEN** the four `ratatoskr_sites_*` durables exist with the filters and ack waits of the table, and the sites service finds them and reports ready, verified by `crates/eventing/tests/stream_table.rs::sites_durables_are_provisioned` in `ratatoskr-platform`

#### Scenario: The site events durable is provisioned

- **WHEN** Edge starts against a fresh broker with the reviewed configuration
- **THEN** `platform_site_events` exists on the events stream with the two filters `evt.sites.release.published.v1` and `evt.sites.draft.changed.v1`, an ack wait of 30 s and explicit acknowledgement, and the table still holds 30 service durables, verified by `crates/eventing/tests/stream_table.rs::site_events_durable_is_provisioned` in `ratatoskr-platform`

### Requirement: Durable names agree between Platform's table and the owning service

Every fixed durable of the bus topology SHALL appear in Platform's table (`crates/eventing/src/stream.rs`) with the contract filter, and the owning repository SHALL hard-code the same name and the same filter as string literals. The three social capture durables, the Telegram notification durable and the two AI-archive projections are listed beside the thirty service-owned durables with their owners, and Edge's own consumers, including the notes conflict projection and the site events projection, are checked by name in Platform's sources.

#### Scenario: A durable is renamed on one side only

- **WHEN** Platform's table renames a durable, or an owner changes the filter it verifies
- **THEN** `platform_names_every_durable_with_its_contract_filter` or `every_owner_hard_codes_its_durable_name_and_filter` in `ratatoskr-workspace` fails, and a mutation test proves the scan reports a renamed durable

#### Scenario: The notes write durable is hard-coded on both sides

- **WHEN** the harness scans Platform's table and the notes checkout after OBS-024
- **THEN** both name `ratatoskr_notes_write_requests` with the filter `cmd.notes.file.write_requested.v1`, Platform's `DOMAIN_CONSUMERS` declares the rows this requirement counts, and Platform's sources hold the literal `platform_notes_conflict_projection`, verified by `every_owner_hard_codes_its_durable_name_and_filter`, `the_service_table_length_equals_the_durables_the_harness_lists` and `platform_names_every_durable_with_its_contract_filter` in `harness/crates/workspace-core/tests/bus_durables.rs` of `ratatoskr-workspace`

#### Scenario: The sites durables are hard-coded on both sides

- **WHEN** the harness scans Platform's table and the sites checkout after SITE-025
- **THEN** both name the four `ratatoskr_sites_*` durables with their filters, and Platform's `DOMAIN_CONSUMERS` declares thirty rows, verified by `every_owner_hard_codes_its_durable_name_and_filter` and `the_service_table_length_equals_the_durables_the_harness_lists` in `harness/crates/workspace-core/tests/bus_durables.rs` of `ratatoskr-workspace`

#### Scenario: The site events projection is checked by name

- **WHEN** the harness scans Platform's sources after SITE-027
- **THEN** they hold the literal `platform_site_events` with the filters `evt.sites.release.published.v1` and `evt.sites.draft.changed.v1`, Platform's `DOMAIN_CONSUMERS` still declares thirty rows, and a mutation that drops one filter fails, verified by `platform_names_every_durable_with_its_contract_filter` and `the_service_table_length_equals_the_durables_the_harness_lists` in `harness/crates/workspace-core/tests/bus_durables.rs` of `ratatoskr-workspace`

### Requirement: The sites identity consumes its durables and publishes only its own events

The SITES stanza SHALL hold the consumer-info, next-message and acknowledgement permissions of the
four `ratatoskr_sites_*` durables, SHALL allow the publication of `evt.sites.release.published.v1`,
`evt.sites.draft.changed.v1` and `evt.platform.operation.reported.v1`, and SHALL NOT allow any `cmd.` subject. Only EDGE SHALL
publish `cmd.sites.release.build_requested.v1`.

#### Scenario: The sites stanza carries its permissions

- **WHEN** `harness/crates/workspace-core/tests/bus_acl.rs::sites_stanza_allows_its_durables_and_events` reads the pinned Platform configuration
- **THEN** the SITES stanza holds the permissions of its four durables, allows the three event subjects, and allows no `cmd.` subject

#### Scenario: The sites service tries to publish a command

- **WHEN** a client connected with only the SITES stanza publishes to `cmd.sites.release.build_requested.v1` on a real broker
- **THEN** the publish is not acknowledged, and publishes of `evt.sites.release.published.v1` and `evt.sites.draft.changed.v1` are acknowledged, verified by `crates/eventing/tests/nats_permissions.rs::sites_identity_reads_its_durables_and_publishes_only_its_events` in `ratatoskr-platform`
