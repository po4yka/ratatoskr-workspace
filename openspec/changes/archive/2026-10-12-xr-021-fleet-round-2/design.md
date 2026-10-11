## Context

Round 2 of changeset XR-021 is the second pass over the same fifteen repositories, cut from a contract document (`CONTRACTS.md`, sections R2-01 to R2-19) that lives in a local planning directory. Behaviour that more than one repository observes belongs in the store the fleet reads, so this design says how the round 2 sections map onto specs and why the new workspace checks and the profile library have the shape they do.

## Goals / Non-Goals

**Goals:**

- Each requirement can be checked from outside one repository, and each scenario names the test layer that proves it.
- A route whose port nobody binds, and a durable that is renamed on one side only, fail the workspace harness.
- Every integration profile runs under the authorization Platform deploys.

**Non-Goals:**

- Behaviour internal to one repository (the outbox column names, the lock implementation, the exact reaper query) stays in that repository's change.
- R2-17 (Telegram sends only the forward member to Platform), R2-18 (the OpenAPI 413) and R2-19 (decisions recorded without code) are not specs: the first two are single-repository and the third is a record of what was left unwired.
- No native smoke harness is added to this repository, see the decision below.

## Decisions

- **Edge upstream check.** `edge_upstreams.rs` parses `RATATOSKR__GATEWAY__ROUTES__<NAME>__LISTENER` from Platform's `edge.conf.example` and requires, for each route with an implementing service (KNOWLEDGE, GITHUB, CHATGPT, CLAUDE), a bind of the same port in a deploy example of the owning repository. A bind under an `__ADMIN__` key never counts, because the operator listener is host only by design and the point of the check is that the two are different sockets. The routes without a service (VAULT 8093, SOCIAL 8094, AI 8095) are an allow-list with the reason, and a route that appears in neither group fails the test, so adding a route forces a decision. The bind matcher moved from `port_allocation.rs` into `tests/support/binds.rs` instead of being copied.
- **Durable check.** `bus_durables.rs` is a text scan on both sides. It cannot see a literal assembled at run time and says nothing about ack wait or `max_deliver`; the services verify those at startup and the native smoke read them from `jsz`. It carries a mutation test so the scan itself is proven to report a renamed durable.
- **NATS rendering library.** `integration/lib/nats-conf.sh` replaces each public-key placeholder of Platform's deployed file with a generated key and edits exactly two lines outside the stanzas: `jetstream.store_dir` (the deployed path is a host mount) and optionally `host`. The work order named a third override, `jetstream.max_file_store: 2GB`. The native smoke ran it and Edge refused to start with `insufficient storage resources available`, because the two streams reserve 1 GiB each beside the KV bucket, so the ceiling stays at the deployed `8GB`. A test-only publisher (the TG-010 driver) is appended as one new stanza and never edits a service identity.
- **The TG-010 driver reports as the extractor.** With the report authority of R2-02, Platform applies a report only from a producer allowed for the operation kind. The driver stands in for the extractor on a capture operation, so it publishes with producer `ratatoskr-extractor` and the owner's tenant.
- **No native smoke harness in this repository.** The work order asked for `integration/native/` (seven flow scripts, fixtures, a contract test). The flows were run by throwaway scripts outside the repository, and several of their assumptions were wrong (production ports that Edge's validation hard-codes, the `max_file_store` override, a `CARGO_PROFILE_RELEASE_DEBUG=0` build that fails on this host). Committing scripts that were never run in the committed form would present them as a proven gate, so the results are recorded in the changeset as reported, with the hops that were faked or not run, and the harness is left as a follow-up that has to be built from those findings.
- **Both new checks stay red between the first child merge and the pin advance.** They read the pinned submodules, and the pinned commits are the point of the test.
- **Dependency edges.** `workspace.toml` is unchanged: the round 2 couplings (channel-digests to Knowledge at 8091, Platform to Knowledge's API listener) follow edges that already exist in one direction, and the reverse edges would close the cycles round 1 recorded.

## Risks / Trade-offs

- [The shared report subject is still trusted by the envelope producer] -> R2-02 narrows it to the tenant and to the producers allowed for the kind; the four extraction and social producers can still report for each other's capture operations because a capture does not record which service it was dispatched to. Per-producer subjects need a contract change.
- [Platform's Edge validates its route and digest listeners against the production ports] -> A second stack on one machine, or the native smoke on non-production ports, cannot start Edge with routes. Reported as a Platform defect in the changeset, not worked around here.
- [ChatGPT can never reach `succeeded`] -> The only registered parser refuses `assets.json` and clears every asset, so the `assets_not_observed` gap is always present and the best case is `partially_succeeded` with `ai_archive.import.incomplete`. Reported by the smoke, recorded as a defect, not hidden.
- [The profiles that need Docker did not run] -> The Docker daemon is not reachable on the machine that wrote this change; the profile contract tests were run, the composed profiles were not, and the changeset says so for each.
