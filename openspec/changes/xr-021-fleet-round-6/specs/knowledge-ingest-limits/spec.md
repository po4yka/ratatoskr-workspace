## ADDED Requirements

### Requirement: The repository analysis waits out an operator-fixable failure and a spend-budget refusal

Knowledge's handler of `cmd.knowledge.repository_analysis.requested.v1` SHALL return a redelivery at every delivery, without consulting the five-delivery budget and without settling a `knowledge.repository_analysis.failed.v1` fact, when the repository analysis fails with a provider failure that an operator can fix (a rejected credential, an exhausted balance, a withdrawn model) or with a spend-budget refusal. Every other failure SHALL keep its disposition: a transient provider failure, a timeout, a held run, an invalid response and an unavailable README retry within the five-delivery budget and then settle the retryable `dependency_unavailable` or `source_unavailable` fact; a permanent source or integrity failure settles `contract_invalid` at once; a settlement that cannot be written is redelivered without a budget. The wait SHALL use the redelivery delay that the other families use, SHALL count into the label-free counter `knowledge_ingest_redeliveries_total` and SHALL log the delivery with the class `provider_operator_action` for an operator failure and `repository_analysis` for a budget refusal, without content. The run SHALL stay recoverable: an operator-fixable failure is a non-spent attempt and the run is reopened to `queued` on the next delivery.

#### Scenario: The provider refuses the key for longer than the old budget

- **WHEN** a repository analysis request meets a provider that refuses the key at eight consecutive deliveries and then accepts it
- **THEN** no failed fact is ever published, the redelivery counter rises, the delivery is logged with class `provider_operator_action`, and the completed fact is published once, verified by the repository-family tests in `services/knowledge/tests/ingest_bus/` of `ratatoskr-knowledge` and by flow F7 of the native smoke when it is run

#### Scenario: A README source answers 503

- **WHEN** the README source answers 503 at every delivery
- **THEN** the request is settled as a retryable failed fact at the fifth delivery, as before

### Requirement: A pending repository analysis request stays open while Knowledge waits

GitHub SHALL keep a repository analysis request `pending` from its dispatch until a terminal fact for it arrives; nothing in GitHub SHALL age, fail or re-dispatch a pending request, and a metadata change during the wait SHALL create a second request with a new idempotency key while the first stays pending. A retryable `failed` fact SHALL still close its request, with no automatic re-queue.

#### Scenario: Knowledge waits for hours

- **WHEN** a request is pending and no terminal fact arrives
- **THEN** the request is still `pending` after any interval and a later completed fact resolves it, verified by the catalog tests of `ratatoskr-github` and by flow F7 of the native smoke when it is run
