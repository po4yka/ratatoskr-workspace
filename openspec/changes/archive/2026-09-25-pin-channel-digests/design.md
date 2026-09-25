## Context

The harness hard-codes the required fleet in `REQUIRED_REPOSITORIES` in `harness/crates/workspace-core/src/lib.rs`, and its fixtures mirror that list in `tests/support/mod.rs` and `tests/support/manifest.rs`. `committed_snapshot.rs` audits the real tree against a written list of identity, path and commit. All four have to move together, or the harness either rejects the new entry or passes a tree it never audited.

## Goals / Non-Goals

**Goals:**

- The committed snapshot pins `ratatoskr-channel-digests` and the snapshot gate proves it.
- Every manifest field for the entry is traceable to a statement in the channel-digests repository or in `contracts.toml`.

**Non-Goals:**

- No integration profile runs channel digests. `profiles` names membership only.
- No edge is added from `knowledge` to `channel-digests`. Knowledge reads manifests from the channel-digests API, but that edge would close a cycle with `channel-digests -> knowledge`, and the manifest graph must stay acyclic. The runtime read is recorded here instead.

## Decisions

- **Path `repos/integrations/channel-digests`.** Beside `telegram`, which is the other Telegram-facing integration.
- **Fields.** `kind = "service"` and `security = "private-user-data"`: two processes, owner-scoped subscriptions and an encrypted MTProto session. `commands = ["fmt", "lint", "test"]`: the three its `ci.yml` gate runs, the same set `telegram` declares. `contracts` names the exact `contracts.toml` ids it consumes or produces: the three `channel_digest.*` commands, the three `knowledge.channel_digest_recap_*` contracts, and `platform.operation_reported`, which its outbox publishes. `profiles = ["core"]`, as for `telegram`. `digest_inputs = ["Cargo.lock", "openspec/config.yaml"]`, as for every other Rust service; `Cargo.lock` carries the pinned contracts revision.
- **Edges.** `contracts` (contract crates pinned by revision), `platform` (event: the command transport and the operation report), `knowledge` (event: recap request and terminal facts), and `knowledge` again (api: the bounded read-through of recap results). Two edges to one repository are allowed by the graph and state two different couplings.
- **Commit.** The gitlink is `origin/main` at the time of the change, recorded in `committed_snapshot.rs` so the audit is exact.

## Risks / Trade-offs

- [Pins go stale as channel-digests advances] → The same as every other pin; `ws status` reports drift and a later change advances it.
- [The stale "sixteen" in `docs/QUALITY_GATES.md` and `openspec/config.yaml`] → Left for a documentation change; they describe the fleet, not the pins.
