## ADDED Requirements

### Requirement: Edge exports consumer lag and stream state

Edge's observer SHALL sample, every 15 seconds and through the JetStream API Edge already holds, every fixed durable of Edge's tables and Edge's own consumers, and both streams, and export them on the operator listener (`127.0.0.1:9464`): for each durable `platform_bus_consumer_pending`, `platform_bus_consumer_ack_pending`, `platform_bus_consumer_redelivered` and `platform_bus_consumer_oldest_unacked_age_seconds` (the age of the first message after the acknowledgement floor that matches the durable's filter, `0` when the consumer is caught up) with the labels `stream` and `durable`; for each stream `platform_bus_stream_messages`, `platform_bus_stream_bytes`, `platform_bus_stream_max_bytes` and `platform_bus_stream_oldest_message_age_seconds` with the label `stream`. The label set SHALL be bounded by the durable table (at most 40 series per name). A failed sample SHALL log a warning and keep the last value, and a consumer that does not exist yet SHALL be skipped without error. The names SHALL be constants of the Platform telemetry module.

#### Scenario: A consumer that nobody runs falls behind

- **WHEN** facts that match `ratatoskr_knowledge_ai_archive` are published while Knowledge is stopped
- **THEN** within 30 seconds `platform_bus_consumer_pending{durable="ratatoskr_knowledge_ai_archive"}` equals the number published and the oldest unacknowledged age is above zero and rises; after Knowledge starts both fall to zero, verified by `consumer_lag.rs` in `ratatoskr-platform` and flow F0 of the native smoke when it is run

#### Scenario: A durable does not exist yet

- **WHEN** the sampler runs before a consumer has been created
- **THEN** it skips that consumer and keeps sampling the others

### Requirement: The lag alert rules are shipped and name only series that exist

`ratatoskr-platform` SHALL ship `deploy/monitoring/ratatoskr-bus-alerts.rules.yml`, a Prometheus-format rule file, with the alerts `RatatoskrKnowledgeConsumerLag` (oldest unacknowledged age above 3600 s for 15 minutes, warning), `RatatoskrKnowledgeConsumerNearRetention` (above 172800 s for 5 minutes, critical), `RatatoskrKnowledgeConsumerBacklog` (more than 1000 messages pending for 30 minutes, warning), `RatatoskrEventsStreamNearCapacity` (the stream above 80 percent of its byte cap for 10 minutes, warning), `RatatoskrConsumerRedeliveryStorm` (more than 100 redeliveries in 15 minutes, warning) and `RatatoskrUnacknowledgedTombstones` (a producer's oldest unacknowledged deletion fact above 86400 s for 15 minutes, critical). Every alert SHALL state `for`, `labels.severity` and `annotations.summary`. Every series an expression names SHALL be a constant of the Platform telemetry module or match the file's documented list of producer-side names (`*_oldest_unacknowledged_tombstone_age_seconds`). The file SHALL state which engine evaluates it is the operator's choice and SHALL state the retention the thresholds are measured against (seven days or 1 GiB, oldest dropped first).

#### Scenario: A series is renamed

- **WHEN** a series in the rule file stops being a Platform metric constant
- **THEN** `alert_rules.rs` in the workspace harness fails and names the alert and the series

#### Scenario: The file is loaded

- **WHEN** the rule file is parsed as YAML
- **THEN** it parses, verified by flow F0 of the native smoke when it is run
