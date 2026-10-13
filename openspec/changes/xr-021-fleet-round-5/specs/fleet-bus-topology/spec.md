## MODIFIED Requirements

### Requirement: The fixed durables and the completion bucket are provisioned by Edge

Edge SHALL create, after declaring the two streams, every durable in the following table and the key-value bucket `browser_worker_completions` (maximum age 24 hours, direct get allowed). All are pull consumers with instant replay and no delivery subject. Existing durables are unchanged: `platform_edge_projection`, `platform_ai_archive_chatgpt_projection`, `platform_ai_archive_claude_projection`, `ratatoskr_telegram_notifications`, `ratatoskr_x_browser_capture`, `ratatoskr_instagram_browser_capture` and `threads_browser_capture`; `platform_schedule_registration` and `platform_stream_erasure` (the commands stream, filter `cmd.platform.stream_erasure.requested.v1`) are created by Edge's own consumers. The table holds 23 service durables.

| Stream | Durable | Filter | Ack wait | Max deliver | Owner identity |
|---|---|---|---|---|---|
| commands | `ratatoskr_extractor_capture` | `cmd.content.capture.requested.v1` | 30 s | 12 | EXTRACTOR |
| commands | `ratatoskr_browser_worker` | `cmd.content.render.requested.v1` | 300 s | 12 | EXTRACTOR_BROWSER_WORKER |
| commands | `ratatoskr_knowledge_channel_recap` | `cmd.knowledge.channel_digest_recap.requested.v1` | 30 s | unlimited | KNOWLEDGE |
| commands | `ratatoskr_channel_digest_subscriptions` | `cmd.channel_digest.subscription.set_requested.v1` | 30 s | unlimited | CHANNEL_DIGESTS |
| commands | `ratatoskr_channel_digest_runs` | `cmd.channel_digest.run.requested.v1` | 30 s | unlimited | CHANNEL_DIGESTS |
| commands | `ratatoskr_channel_digest_schedule_occurrences` | `cmd.channel_digest.schedule.occurrence_requested.v1` | 30 s | unlimited | CHANNEL_DIGESTS |
| commands | `ratatoskr_vault_backup_policy` | `cmd.vault.backup_policy.apply_requested.v1` | 30 s | unlimited | VAULT |
| events | `ratatoskr_knowledge_documents` | `evt.content.document.extracted.v1` | 120 s | unlimited | KNOWLEDGE |
| events | `ratatoskr_knowledge_social_sources` | `evt.social.source.>` | 120 s | unlimited | KNOWLEDGE |
| events | `ratatoskr_knowledge_ai_archive` | `evt.ai_archive.>` | 120 s | unlimited | KNOWLEDGE |
| events | `ratatoskr_knowledge_repository_requests` | `evt.knowledge.repository_analysis.requested.v1` | 120 s | unlimited | KNOWLEDGE |
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

Every events-stream durable other than `ratatoskr_extractor_render_awaits` uses explicit acknowledgement and delivers all messages; `ratatoskr_extractor_render_awaits` uses no acknowledgement and delivers only messages published after it is created. Knowledge's ingest acknowledgement wait SHALL equal the 120 seconds of its durables.

#### Scenario: A fresh broker starts in the documented order

- **WHEN** the operator reloads NATS with the reviewed configuration, starts Edge, and then starts the other services
- **THEN** every service finds its durable and becomes ready, verified by the real-broker matrix in `ratatoskr-platform` (`crates/eventing/tests/nats_permissions.rs`)

### Requirement: Only Edge can create topology or read the bus wholesale

Only EDGE SHALL hold `$JS.API.>`, `cmd.>` or `$JS.ACK.>` without a durable suffix. No other identity SHALL hold `$JS.API.>`, `evt.>` or `cmd.>`, or any consumer-create, durable-create, stream-create, stream-update, message-get or direct-get permission on a `ratatoskr_*` stream. No stanza other than EDGE SHALL hold a publish allow that starts with `$JS.API.STREAM.`, except the read-only `$JS.API.STREAM.INFO.KV_<bucket>` that a client needs to open a KV bucket, so that only Edge can delete a stream message (R5-12). The only wildcards a non-EDGE publish allow may contain are `$JS.ACK.<stream>.<durable>.>`, `$JS.API.DIRECT.GET.KV_<bucket>.>` and `$KV.<bucket>.>`. Each durable's consumer-info, next-message and acknowledgement permissions SHALL appear in exactly one stanza, the owner named in the durable table.

#### Scenario: A stanza gains a wide permission

- **WHEN** a non-EDGE stanza is edited to allow `evt.>`, `$JS.API.>` or any consumer-create subject
- **THEN** `bus_acl.rs::non_edge_stanzas_obey_the_permission_invariants` fails and names the identity and the subject

#### Scenario: Two identities claim one durable

- **WHEN** the same durable's permissions appear in two stanzas
- **THEN** the same test fails and names the durable

#### Scenario: A stanza gains the right to delete a stream message

- **WHEN** a non-EDGE stanza is edited to allow `$JS.API.STREAM.MSG.DELETE.ratatoskr_events` or `$JS.API.STREAM.PURGE.ratatoskr_events`
- **THEN** `bus_acl.rs::no_stanza_but_edge_publishes_under_the_stream_api_except_a_kv_info` fails and names the identity and the subject
