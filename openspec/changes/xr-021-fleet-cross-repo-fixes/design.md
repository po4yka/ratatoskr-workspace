## Context

Changeset XR-021 fixed cross-repository defects in fifteen repositories by first writing one contract document (`CONTRACTS.md`, sections S00 to S14) and then giving each repository a work order cut from it. That document lived in a local planning directory. The behaviour in it is what several repositories now rely on at once, so it belongs in the store the fleet reads. This design says how it maps onto specs, and why the workspace checks have the shape they do.

## Goals / Non-Goals

**Goals:**

- Each spec requirement can be checked from outside one repository, and each scenario names the test layer that proves it.
- The port table and the bus permissions have one reviewed home each, and a workspace test fails when a repository's copy diverges.

**Non-Goals:**

- No requirement is copied from `docs/REQUIREMENTS.md` or `docs/INTERFACES.md`.
- Behaviour internal to one repository (outbox schemas, advisory locks, deletion phase order, crash recovery) stays in that repository's own OpenSpec change.
- No host provisioning. The nkeys, the `ratatoskr-telegram-blobs` group and the external credentials are listed for the operator in the changeset.

## Decisions

- **Which sections become specs.** Only what two or more repositories observe: S01 to S04 become `fleet-bus-topology`, S06 `ai-archive-receipt-binding`, S08 `channel-digest-chain`, S10 `social-capture-lifecycle`, S11 `content-capture-command` plus the added blob requirement. S05 is not a spec; it is `docs/DEPLOYMENT_TARGET.md`, which is canonical for ports and is enforced by a test. S07, S09 and S12 are repository-internal and stay in the owners.
- **The ports test reads the example files, not the code.** A compiled default that no example documents is invisible to it, which is why the change also makes the documented table complete. Keys of the form `RATATOSKR__*__(BIND|LISTEN_ADDRESS|LISTENER)` are scanned. Platform's `GATEWAY__ROUTES__*__LISTENER` and `CHANNEL_DIGESTS__LISTENER` name the address of another service's listener, not a bind, so they must be allocated but never claim a port. Two claims collide when they name the same port and differ in repository, key, or role; the role is the stem of a `*.conf.example` file, and a bare `.env.example` documents the default of whichever role has that key.
- **The ACL test uses a plain-text splitter.** A stanza is a brace block that opens at the start of a file or after `[` or `,`. Comments are stripped string-aware, whitespace is removed, and the nkey token is cut out before two stanzas are compared. No NATS parser is a dependency, because the comparison must be byte-for-byte on what a human reviewed, not on a parsed meaning.
- **Owner map.** An identity is owned by the repository that consumes or publishes with it (EDGE `platform`, EXTRACTOR and EXTRACTOR_BROWSER_WORKER `extractor`, and so on). A missing checkout fails loudly instead of skipping, because a skipped ACL check would pass in exactly the environment where nobody looked.
- **Both checks stay red between the first child merge and the pin advance.** That is intended: they read the pinned submodules, and the pinned commits are the point of the test.
- **Dependency edges.** `vault` gains `github` (event: the backup policy lane). Four more edges the fixes describe are not added, because each closes a cycle and the manifest graph must stay acyclic (the rule recorded when `channel-digests` joined): `knowledge` to `channel-digests` (manifest read; `channel-digests` already depends on `knowledge`), `platform` to `channel-digests` (read client; the reverse edge exists), `platform` to `knowledge` and `github` to `knowledge` (each reverse edge exists). These couplings are recorded here and in the changeset, and are covered by the specs, not by the graph.

## Risks / Trade-offs

- [A composed profile cannot run here] -> The Docker daemon is not running on the machine that wrote this change, so no `integration/` profile was started. The changeset records each profile as not run, with the reason, and nothing is claimed as passed.
- [`evt.platform.operation.reported.v1` is one shared subject trusted by the envelope producer] -> Documented as residual risk in the spec; per-producer subjects need a contract change and are a follow-up.
- [The events stream drops its oldest messages when full] -> A repository analysis request is an event, so a very deep backlog could drop one after GitHub marked it published. A GitHub re-queue sweep is a recommended follow-up.
- [An oversized extracted document dead-letters in the extractor outbox because NATS caps a message at 1 MiB] -> Follow-up, recorded in the spec.
- [Telegram image capture is refusal-only] -> Tracked as a `refusal-only` issue in `ratatoskr-telegram`; the real capability needs an OCR subsystem and a Document IR block kind for images.
