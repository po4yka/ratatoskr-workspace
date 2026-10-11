## ADDED Requirements

### Requirement: The broker accepts 8 MiB messages and a publish failure has a class

The deployed NATS file SHALL set `max_payload: 8MB` (8388608 bytes) and leave the JetStream stream `max_msg_size` unlimited, so a message the broker accepts is a message a stream stores. A producer outbox SHALL classify a failed publish. A transient failure (broker unreachable, publish error, acknowledgement error or timeout, which is indistinguishable from a permission denial) SHALL record the attempt, a safe class and the capped backoff and SHALL NEVER dead-letter or delete the row. A permanent failure (the serialized envelope is larger than the connected server's `max_payload` minus 1 KiB of headroom, or the stored document cannot be serialized) SHALL mark the row undeliverable at once, increment `<service>_outbox_undeliverable_total{class}`, log only the class, and let the pass continue with the next rows. An undeliverable row SHALL NOT make readiness fail.

#### Scenario: The deployed file carries the limit

- **WHEN** the deployed NATS file is loaded by a real broker
- **THEN** a 4 MiB envelope published with the X identity is acknowledged, verified by `crates/eventing/tests/deployed_max_payload.rs` in `ratatoskr-platform`

#### Scenario: A broker outage outlasts the old retry budget

- **WHEN** the broker is unreachable for longer than twelve backed-off attempts
- **THEN** the extractor's outbox rows are still unpublished and not dead-lettered, and are published after the broker returns, verified by `crates/eventing/tests/outbox.rs` in `ratatoskr-extractor`

### Requirement: A relay that cannot publish makes its service not ready

Every service with an outbox relay SHALL keep one `bus` readiness check fed by the relay. The check SHALL be unhealthy when the last pass attempted a publish, at least one publish failed, and the oldest unpublished publishable row has `attempt_count >= 3` or is older than 300 seconds, and healthy again after a pass that publishes every due row or finds none. An unhealthy state SHALL NOT stop the relay or exit the process; it flips readiness and increments a labelled counter so an operator sees the denial instead of a silently ready service. This applies to X, Instagram, GitHub, Vault and the extractor; Threads, ChatGPT, Claude and Knowledge already surface a failing pass.

#### Scenario: The relay keeps running and cannot publish

- **WHEN** the permission set denies every publish of a service whose relay is running
- **THEN** after the third failed attempt of the oldest row the service reports not ready, and after the denial is lifted and a pass publishes the row it reports ready again, verified by `services/catalog/tests/bus_health.rs` in `ratatoskr-github` and `crates/x-capture/tests/outbox_relay.rs` in `ratatoskr-x`

### Requirement: Every Edge upstream with an implementation is bound by its own listener

Each `RATATOSKR__GATEWAY__ROUTES__<NAME>__LISTENER` address of Platform's Edge example whose service exists SHALL be bound by the owning repository's own deploy example on a listener that is not its operator listener: Knowledge 8091 through `RATATOSKR__API__LISTEN_ADDRESS`, GitHub 8092 through `RATATOSKR__API__LISTEN_ADDRESS`, ChatGPT 8096 and Claude 8097 through `RATATOSKR__RECEIPT__LISTEN_ADDRESS`. The operator listeners (Knowledge 9081, GitHub 9095, ChatGPT 9085, Claude 9086) serve health, metrics and version only, are host only, and SHALL differ from the upstream listener. The routes 8093 (vault), 8094 (social) and 8095 (ai-archive) have no implementing service and Edge SHALL keep reporting their capability stale.

#### Scenario: A route points at a port nobody binds

- **WHEN** an owning repository's examples do not bind the port Edge routes to, or bind it only as an operator listener
- **THEN** the harness test `every_implemented_edge_upstream_is_bound_by_its_owner` in `ratatoskr-workspace` fails and names the route, the port and the owner

#### Scenario: A new route appears

- **WHEN** Platform's example gains a route that is in neither the implemented nor the unimplemented group of the harness
- **THEN** `routes_without_a_service_are_exactly_vault_social_and_ai` fails with the reason, so the route is classified before it ships

### Requirement: Durable names agree between Platform's table and the owning service

Every fixed durable of the bus topology SHALL appear in Platform's table (`crates/eventing/src/stream.rs`) with the contract filter, and the owning repository SHALL hard-code the same name and the same filter as string literals. The three social capture durables, the Telegram notification durable and the two AI-archive projections are listed beside the eighteen service-owned durables with their owners.

#### Scenario: A durable is renamed on one side only

- **WHEN** Platform's table renames a durable, or an owner changes the filter it verifies
- **THEN** `platform_names_every_durable_with_its_contract_filter` or `every_owner_hard_codes_its_durable_name_and_filter` in `ratatoskr-workspace` fails, and a mutation test proves the scan reports a renamed durable

### Requirement: Every service ships a loadable operator example and the seed variable table is one

Each service SHALL ship `deploy/systemd/<service>.conf.example` (channel-digests ships `api.conf.example` and `worker.conf.example`) that sets every key the flow needs, with `CHANGE-ME` placeholders for secrets and absolute seed paths, and the service SHALL load the example through its own configuration loader in a test (`deployment_profile.rs` or the equivalent) that asserts the flow-enabling values. Seed variables and paths SHALL be: Edge `RATATOSKR__BUS__NKEY_SEED_PATH` at `/etc/ratatoskr/edge.nkey`; the Telegram dispatcher `RATATOSKR__NOTIFICATION_BUS__CREDENTIALS_FILE` at `/etc/ratatoskr/telegram.nkey`; ChatGPT and Claude `RATATOSKR__RECEIPT__EVENT_BUS_NKEY_SEED_PATH` (with `RATATOSKR__RECEIPT__EVENT_BUS_URL`) at `/etc/ratatoskr/chatgpt.nkey` and `/etc/ratatoskr/claude.nkey`; X, Instagram, Threads, the extractor, GitHub, Vault and channel-digests `RATATOSKR__BUS__NKEY_SEED_PATH` at `/etc/ratatoskr/<name>.nkey`; the browser worker `BROWSER_NKEY_SEED_PATH`; Knowledge `RATATOSKR__CHANNEL_RECAP__BUS_CREDENTIALS_FILE` and `RATATOSKR__INGEST__BUS_CREDENTIALS_FILE` at `/etc/ratatoskr/knowledge.nkey`.

#### Scenario: An example rots

- **WHEN** a service renames a key or a flow stops being enabled by its shipped example
- **THEN** the service's own deployment-profile test fails, for example `services/knowledge/tests/deployment_profile.rs` in `ratatoskr-knowledge` and `services/chatgpt-archive/tests/boot.rs` in `ratatoskr-chatgpt`

#### Scenario: Two examples bind one port

- **WHEN** two deploy examples bind the same port or bind a port the table does not allocate
- **THEN** `no_two_deploy_examples_bind_the_same_port_and_every_bind_is_allocated` in `ratatoskr-workspace` fails

### Requirement: Integration profiles run under the deployed NATS authorization

Every integration profile SHALL render its NATS configuration from Platform's `deploy/nats/ratatoskr.conf` at the Platform revision under test, by replacing each public-key placeholder with a generated key and writing the seeds of the identities the profile runs with mode 0600 (identities it does not run get throwaway keys with no seed kept). The only edits outside the stanzas SHALL be `jetstream.store_dir` and, when requested, `host`; `max_file_store` SHALL stay at the deployed value. A profile that needs a test-only publisher SHALL append one extra user stanza after rendering and SHALL NOT edit a service identity. Profiles SHALL run each dual-listener service with both listeners: ChatGPT 8096 and 9085, Claude 8097 and 9086, Knowledge 8091 and 9081.

#### Scenario: The rendered file differs from the deployed one only where allowed

- **WHEN** `render_nats_conf` renders the deployed file for the Edge, ChatGPT and Claude identities
- **THEN** no placeholder remains, `nats-server -t` accepts the file, thirteen distinct keys are present, the requested seeds are mode 0600, and the normalized ACL equals the deployed one, verified by `integration/tests/nats_conf_test.sh` in `ratatoskr-workspace`

#### Scenario: A test driver is added

- **WHEN** `append_nats_test_user` adds the TG-010 driver
- **THEN** the file still validates, the driver has its own stanza and key, and no line of a service identity was removed or changed
