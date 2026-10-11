## ADDED Requirements

### Requirement: Every non-Edge identity subscribes only to its own inbox prefix and every connection sets it

In `platform/deploy/nats/ratatoskr.conf` each non-Edge stanza SHALL carry `subscribe` with exactly one allow entry, `_INBOX_<name>.>`, where `<name>` is the identity name in lower case with its underscores kept: `telegram`, `chatgpt`, `claude`, `x`, `instagram`, `threads`, `extractor`, `extractor_browser_worker`, `knowledge`, `github`, `vault` and `channel_digests`. Edge keeps `_INBOX.>`: it is the one identity that creates and administers, and `_INBOX_x.>` does not match `_INBOX.>` because the broker compares whole tokens. Every NATS connection a service opens SHALL call `async_nats::ConnectOptions::custom_inbox_prefix` with the literal of its row, held as one constant beside its durable names: Knowledge on its ingest and its recap connection, the extractor on its capture consumer and its outbox publisher, the browser worker on its connection including the KV handle, channel-digests on the worker connection, Telegram on the dispatcher's notification connection, and each importer and each social service on the connection of its event pump. The twelve copies of the stanzas that services vendor SHALL stay equal to the deployed ones. A service built before this requirement cannot complete a JetStream request under the new file, because its replies arrive on a subject it may not subscribe to; NATS is reloaded and the services of one snapshot are deployed together.

#### Scenario: A stanza subscribes to more than its own prefix

- **WHEN** a non-Edge stanza lists `_INBOX.>`, a wildcard broader than its own prefix, or another identity's prefix
- **THEN** `every_non_edge_stanza_subscribes_only_to_its_own_inbox_prefix` in `ratatoskr-workspace` fails and names the identity and what it subscribes to

#### Scenario: A service forgets to set its prefix

- **WHEN** an owning repository's non-test source stops passing its prefix constant to `custom_inbox_prefix(`, or changes the constant's value
- **THEN** `the_owner_repository_uses_the_prefix_literal` fails, and the repository's own real-broker test completes a JetStream request under only its stanza and times out without the prefix, verified by `crates/eventing/tests/deployed_inbox_prefixes.rs` in `ratatoskr-platform` and the inbox-prefix test of each service repository

#### Scenario: An identity has no vendored copy

- **WHEN** a non-Edge identity has no `deploy/nats/identity.conf` copy in its owning repository
- **THEN** `every_identity_has_a_vendored_copy` fails

### Requirement: Knowledge's ack-wait keys state the values Edge fixes

Edge creates Knowledge's ingest durables with an ack wait of 120 seconds and the recap command durable with 30 seconds, and Knowledge refuses to become ready on any other value. `RATATOSKR__INGEST__ACK_WAIT_SECONDS` SHALL therefore be accepted only as 120 and `RATATOSKR__CHANNEL_RECAP__ACK_WAIT_SECONDS` only as 30, with an error that names the constant Edge fixes. The keys exist to state the value, and the example and the README say so.

#### Scenario: A plausible edit

- **WHEN** an operator sets the ingest ack wait to 60
- **THEN** the service refuses to load its configuration with a message naming 120 and the Edge table, instead of starting and never consuming, verified by the configuration tests of `ratatoskr-knowledge`
