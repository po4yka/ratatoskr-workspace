# Spec Delta

This delta requires `add-notes-write-back` (OBS-024) to be archived first.

## ADDED Requirements

### Requirement: The sites identity consumes its durables and publishes only its own events

The SITES stanza SHALL hold the consumer-info, next-message and acknowledgement permissions of the
four `ratatoskr_sites_*` durables, SHALL allow the publication of `evt.sites.release.published.v1`
and `evt.platform.operation.reported.v1`, and SHALL NOT allow any `cmd.` subject. Only EDGE SHALL
publish `cmd.sites.release.build_requested.v1`.

#### Scenario: The sites stanza carries its permissions

- **WHEN** `harness/crates/workspace-core/tests/bus_acl.rs::sites_stanza_allows_its_durables_and_events` reads the pinned Platform configuration
- **THEN** the SITES stanza holds the permissions of its four durables, allows both event subjects, and allows no `cmd.` subject

#### Scenario: The sites service tries to publish a command

- **WHEN** a client connected with only the SITES stanza publishes to `cmd.sites.release.build_requested.v1` on a real broker
- **THEN** the publish is not acknowledged, and a publish of `evt.sites.release.published.v1` is acknowledged, verified by `crates/eventing/tests/nats_permissions.rs::sites_identity_reads_its_durables_and_publishes_only_its_events` in `ratatoskr-platform`

## RENAMED Requirements

- FROM: `### Requirement: There are fourteen NATS identities in one reviewed file`
- TO: `### Requirement: There are fifteen NATS identities in one reviewed file`

## MODIFIED Requirements

### Requirement: The fixed durables and the completion bucket are provisioned by Edge

Edge SHALL create, after declaring the two streams, every durable in the following table and the key-value bucket `browser_worker_completions` (maximum age 24 hours, direct get allowed). All are pull consumers with instant replay and no delivery subject. Existing durables are unchanged: `platform_edge_projection`, `platform_ai_archive_chatgpt_projection`, `platform_ai_archive_claude_projection`, `ratatoskr_telegram_notifications`, `ratatoskr_x_browser_capture`, `ratatoskr_instagram_browser_capture` and `threads_browser_capture`; `platform_schedule_registration`, `platform_stream_erasure` (the commands stream, filter `cmd.platform.stream_erasure.requested.v1`) and `platform_notes_conflict_projection` (the events stream, filter `evt.notes.conflict.>`, ack wait 30 s, unlimited deliveries, explicit acknowledgement, owner EDGE, which projects note conflicts onto `notes.file.write` operations) are created by Edge's own consumers. The table holds 30 service durables.

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

### Requirement: There are fifteen NATS identities in one reviewed file

`ratatoskr-platform/deploy/nats/ratatoskr.conf` SHALL be the only deployed authorization file and SHALL hold exactly fifteen identities: EDGE, TELEGRAM, CHATGPT, CLAUDE, X, INSTAGRAM, THREADS, EXTRACTOR, EXTRACTOR_BROWSER_WORKER, KNOWLEDGE, GITHUB, VAULT, CHANNEL_DIGESTS, NOTES and SITES. Each public nkey is a unique placeholder `UREPLACE_ME_WITH_THE_PUBLIC_NKEY_OF_RATATOSKR_<NAME>_<X+>`, where the name is split from the filler at the last underscore. Every identity except EDGE SHALL subscribe only to `_INBOX.>` and SHALL have no `deny` block. A service that carries a copy of its own stanza in `deploy/nats/identity*.conf` SHALL carry one that equals the reviewed stanza once comments, whitespace and the nkey token are ignored. The extractor's earlier wide permission file SHALL NOT exist.

#### Scenario: The reviewed file holds exactly the thirteen identities

- **WHEN** `harness/crates/workspace-core/tests/bus_acl.rs::platform_conf_has_exactly_the_fifteen_identities` reads the pinned Platform configuration
- **THEN** it finds those fifteen names, each with a distinct placeholder, and every owning repository is checked out

#### Scenario: A service copy drifts from the reviewed stanza

- **WHEN** `bus_acl.rs::every_service_fragment_equals_its_platform_stanza` compares the extractor, browser worker, Knowledge, channel-digests, GitHub, Vault, notes and sites copies with their stanzas
- **THEN** every pair is equal, and a copy that differs fails the test and names the identity

#### Scenario: The old extractor file is gone

- **WHEN** `bus_acl.rs::extractor_permissions_conf_is_gone` looks for `deploy/nats/extractor-permissions.conf` in the extractor checkout
- **THEN** the file does not exist

### Requirement: The shared operation-report subject is documented as trusted by its envelope producer

`evt.platform.operation.reported.v1` is one subject published by the extractor, X, Instagram, Threads, channel-digests, notes and sites, and its authenticity rests on the envelope `producer` field. An identity allowed to publish it can therefore forge reports for another, and X can read every tenant's report metadata through its durable. The lane check of `operation-report-authority` limits a forged report to the forger's own lanes; the sites lane is the kind `sites.release.build`, reported only by `ratatoskr-sites`. The specification SHALL state this limit wherever those permissions are granted, and no code or test SHALL claim the subject is attributable beyond the envelope field. Closing the limit needs per-producer subjects and a contract change, and is a follow-up.

#### Scenario: The limit is stated where the permission is granted

- **WHEN** a reader reviews the identities that may publish `evt.platform.operation.reported.v1`
- **THEN** this requirement names the seven identities and the forgery limit

### Requirement: Every Edge upstream with an implementation is bound by its own listener

Each `RATATOSKR__GATEWAY__ROUTES__<NAME>__LISTENER` address of Platform's Edge example whose service exists SHALL be bound by the owning repository's own deploy example on a listener that is not its operator listener: Knowledge 8091 through `RATATOSKR__API__LISTEN_ADDRESS`, GitHub 8092 through `RATATOSKR__API__LISTEN_ADDRESS`, notes 8099 through `RATATOSKR__API__LISTEN_ADDRESS`, sites 8100 through `RATATOSKR__API__LISTEN_ADDRESS`, ChatGPT 8096 and Claude 8097 through `RATATOSKR__RECEIPT__LISTEN_ADDRESS`. The operator listeners (Knowledge 9081, GitHub 9095, notes 9471, sites 9472, ChatGPT 9085, Claude 9086) serve health, metrics and version only, are host only, and SHALL differ from the upstream listener. The routes 8093 (vault), 8094 (social) and 8095 (ai-archive) have no implementing service and Edge SHALL keep reporting their capability stale.

#### Scenario: A route points at a port nobody binds

- **WHEN** an owning repository's examples do not bind the port Edge routes to, or bind it only as an operator listener
- **THEN** the harness test `every_implemented_edge_upstream_is_bound_by_its_owner` in `ratatoskr-workspace` fails and names the route, the port and the owner

#### Scenario: A new route appears

- **WHEN** Platform's example gains a route that is in neither the implemented nor the unimplemented group of the harness
- **THEN** `routes_without_a_service_are_exactly_vault_social_and_ai` fails with the reason, so the route is classified before it ships

### Requirement: Durable names agree between Platform's table and the owning service

Every fixed durable of the bus topology SHALL appear in Platform's table (`crates/eventing/src/stream.rs`) with the contract filter, and the owning repository SHALL hard-code the same name and the same filter as string literals. The three social capture durables, the Telegram notification durable and the two AI-archive projections are listed beside the thirty service-owned durables with their owners, and Edge's own consumers, including the notes conflict projection, are checked by name in Platform's sources.

#### Scenario: A durable is renamed on one side only

- **WHEN** Platform's table renames a durable, or an owner changes the filter it verifies
- **THEN** `platform_names_every_durable_with_its_contract_filter` or `every_owner_hard_codes_its_durable_name_and_filter` in `ratatoskr-workspace` fails, and a mutation test proves the scan reports a renamed durable

#### Scenario: The notes write durable is hard-coded on both sides

- **WHEN** the harness scans Platform's table and the notes checkout after OBS-024
- **THEN** both name `ratatoskr_notes_write_requests` with the filter `cmd.notes.file.write_requested.v1`, Platform's `DOMAIN_CONSUMERS` declares the rows this requirement counts, and Platform's sources hold the literal `platform_notes_conflict_projection`, verified by `every_owner_hard_codes_its_durable_name_and_filter`, `the_service_table_length_equals_the_durables_the_harness_lists` and `platform_names_every_durable_with_its_contract_filter` in `harness/crates/workspace-core/tests/bus_durables.rs` of `ratatoskr-workspace`

#### Scenario: The sites durables are hard-coded on both sides

- **WHEN** the harness scans Platform's table and the sites checkout after SITE-025
- **THEN** both name the four `ratatoskr_sites_*` durables with their filters, and Platform's `DOMAIN_CONSUMERS` declares thirty rows, verified by `every_owner_hard_codes_its_durable_name_and_filter` and `the_service_table_length_equals_the_durables_the_harness_lists` in `harness/crates/workspace-core/tests/bus_durables.rs` of `ratatoskr-workspace`

### Requirement: Every service ships a loadable operator example and the seed variable table is one

Each service SHALL ship `deploy/systemd/<service>.conf.example` (channel-digests ships `api.conf.example` and `worker.conf.example`) that sets every key the flow needs, with `CHANGE-ME` placeholders for secrets and absolute seed paths, and the service SHALL load the example through its own configuration loader in a test (`deployment_profile.rs` or the equivalent) that asserts the flow-enabling values. Seed variables and paths SHALL be: Edge `RATATOSKR__BUS__NKEY_SEED_PATH` at `/etc/ratatoskr/edge.nkey`; the Telegram dispatcher `RATATOSKR__NOTIFICATION_BUS__CREDENTIALS_FILE` at `/etc/ratatoskr/telegram.nkey`; ChatGPT and Claude `RATATOSKR__RECEIPT__EVENT_BUS_NKEY_SEED_PATH` (with `RATATOSKR__RECEIPT__EVENT_BUS_URL`) at `/etc/ratatoskr/chatgpt.nkey` and `/etc/ratatoskr/claude.nkey`; X, Instagram, Threads, the extractor, GitHub, Vault, channel-digests, notes and sites `RATATOSKR__BUS__NKEY_SEED_PATH` at `/etc/ratatoskr/<name>.nkey`; the browser worker `BROWSER_NKEY_SEED_PATH`; Knowledge `RATATOSKR__CHANNEL_RECAP__BUS_CREDENTIALS_FILE` and `RATATOSKR__INGEST__BUS_CREDENTIALS_FILE` at `/etc/ratatoskr/knowledge.nkey`.

#### Scenario: An example rots

- **WHEN** a service renames a key or a flow stops being enabled by its shipped example
- **THEN** the service's own deployment-profile test fails, for example `services/knowledge/tests/deployment_profile.rs` in `ratatoskr-knowledge` `services/chatgpt-archive/tests/boot.rs` in `ratatoskr-chatgpt` and `services/sites/tests/deployment_profile.rs` in `ratatoskr-sites`

#### Scenario: Two examples bind one port

- **WHEN** two deploy examples bind the same port or bind a port the table does not allocate
- **THEN** `no_two_deploy_examples_bind_the_same_port_and_every_bind_is_allocated` in `ratatoskr-workspace` fails

### Requirement: Integration profiles run under the deployed NATS authorization

Every integration profile SHALL render its NATS configuration from Platform's `deploy/nats/ratatoskr.conf` at the Platform revision under test, by replacing each public-key placeholder with a generated key and writing the seeds of the identities the profile runs with mode 0600 (identities it does not run get throwaway keys with no seed kept). The only edits outside the stanzas SHALL be `jetstream.store_dir` and, when requested, `host`; `max_file_store` SHALL stay at the deployed value. A profile that needs a test-only publisher SHALL append one extra user stanza after rendering and SHALL NOT edit a service identity. Profiles SHALL run each dual-listener service with both listeners: ChatGPT 8096 and 9085, Claude 8097 and 9086, Knowledge 8091 and 9081, sites 8100 and 9472.

#### Scenario: The rendered file differs from the deployed one only where allowed

- **WHEN** `render_nats_conf` renders the deployed file for the Edge, ChatGPT and Claude identities
- **THEN** no placeholder remains, `nats-server -t` accepts the file, fifteen distinct keys are present, the requested seeds are mode 0600, and the normalized ACL equals the deployed one, verified by `integration/tests/nats_conf_test.sh` in `ratatoskr-workspace`

#### Scenario: A test driver is added

- **WHEN** `append_nats_test_user` adds the TG-010 driver
- **THEN** the file still validates, the driver has its own stanza and key, and no line of a service identity was removed or changed

### Requirement: Every non-Edge identity subscribes only to its own inbox prefix and every connection sets it

In `platform/deploy/nats/ratatoskr.conf` each non-Edge stanza SHALL carry `subscribe` with exactly one allow entry, `_INBOX_<name>.>`, where `<name>` is the identity name in lower case with its underscores kept: `telegram`, `chatgpt`, `claude`, `x`, `instagram`, `threads`, `extractor`, `extractor_browser_worker`, `knowledge`, `github`, `vault`, `channel_digests`, `notes` and `sites`. Edge keeps `_INBOX.>`: it is the one identity that creates and administers, and `_INBOX_x.>` does not match `_INBOX.>` because the broker compares whole tokens. Every NATS connection a service opens SHALL call `async_nats::ConnectOptions::custom_inbox_prefix` with the literal of its row, held as one constant beside its durable names: Knowledge on its ingest and its recap connection, the extractor on its capture consumer and its outbox publisher, the browser worker on its connection including the KV handle, channel-digests on the worker connection, notes on the connection of its outbox relay, sites on its consumer and its outbox connection, Telegram on the dispatcher's notification connection, and each importer and each social service on the connection of its event pump. The fourteen copies of the stanzas that services vendor SHALL stay equal to the deployed ones. A service built before this requirement cannot complete a JetStream request under the new file, because its replies arrive on a subject it may not subscribe to; NATS is reloaded and the services of one snapshot are deployed together.

#### Scenario: A stanza subscribes to more than its own prefix

- **WHEN** a non-Edge stanza lists `_INBOX.>`, a wildcard broader than its own prefix, or another identity's prefix
- **THEN** `every_non_edge_stanza_subscribes_only_to_its_own_inbox_prefix` in `ratatoskr-workspace` fails and names the identity and what it subscribes to

#### Scenario: A service forgets to set its prefix

- **WHEN** an owning repository's non-test source stops passing its prefix constant to `custom_inbox_prefix(`, or changes the constant's value
- **THEN** `the_owner_repository_uses_the_prefix_literal` fails, and the repository's own real-broker test completes a JetStream request under only its stanza and times out without the prefix, verified by `crates/eventing/tests/deployed_inbox_prefixes.rs` in `ratatoskr-platform` and the inbox-prefix test of each service repository

#### Scenario: An identity has no vendored copy

- **WHEN** a non-Edge identity has no `deploy/nats/identity.conf` copy in its owning repository
- **THEN** `every_identity_has_a_vendored_copy` fails
