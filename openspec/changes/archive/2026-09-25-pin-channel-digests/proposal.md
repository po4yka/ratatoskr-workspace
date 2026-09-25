## Why

`ratatoskr-channel-digests` joined the fleet: it carries the fleet files, `drift.yml` reads it, and `docs/QUALITY_GATES.md` counts it. The workspace snapshot does not. `workspace.toml`, `.gitmodules`, the gitlinks and `workspace.lock` still name sixteen product repositories, and the harness rejects any manifest that names a seventeenth, so `main` cannot identify a snapshot that includes the service Platform and Knowledge now exchange channel-digest commands and recap facts with.

## What Changes

- Add `channel-digests` to the harness's required fleet, so a manifest without it fails validation and a manifest with it passes.
- Add a `[[repositories]]` entry for `channel-digests` to `workspace.toml`, with its kind, security class, commands, contracts, profiles, digest inputs and dependency edges taken from that repository's own README, AGENTS.md, docs/ARCHITECTURE.md, docs/INTERFACES.md, `.github/workflows/ci.yml` and `Cargo.toml`, and from the `channel_digest.*` rows in `ratatoskr-contracts/contracts.toml`.
- Add the submodule at `repos/integrations/channel-digests`, pinned to the current `origin/main` of `ratatoskr-channel-digests`.
- Regenerate `workspace.lock` with `./ws lock generate --output workspace.lock`.
- Update the documents that list the pinned repositories.

## Capabilities

### New Capabilities

- `workspace-fleet-membership`: which product repositories the workspace snapshot must pin, stated so that a repository joining the fleet has a checkable place to join the snapshot.

### Modified Capabilities

None.

## Impact

Repositories, in dependency order: `ratatoskr-channel-digests` is read only — its published `main` is the pinned input and it receives no change — and `ratatoskr-workspace` is the only repository written. It merges alone and last, as the workspace pins always do.

Outside this change: the channel-digests source, its CI, a Compose profile for it, the Knowledge manifest read that points the other way, and the stale fleet counts in `docs/QUALITY_GATES.md` and `openspec/config.yaml`, which describe the fleet rather than the pins.

Rollback: revert the workspace commit. It removes the manifest entry, the gitlink and the lock rows together, and the child repository is untouched. Nothing has shipped from this snapshot, so there is no deployment to roll back.
