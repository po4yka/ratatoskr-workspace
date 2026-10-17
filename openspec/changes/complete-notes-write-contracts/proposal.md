## Why

OBS-024 tasks 3.13–3.16 remain open. Write paths still permit names that the Obsidian adapters refuse, and a group conflict event cannot name every stale file even though the conflict read API can.

## What Changes

- **BREAKING validation restriction:** reject a colon or a segment that ends in a dot or a space in every write path and target path. Keep the first contract major, under the development status and the owner request for OBS-024 3.13–3.16.
- Add optional `stale_paths` to `notes.conflict.raised.v1`, with vault-relative paths and omission when the producer has no group list. Keep `path` as the first stale file.
- Prove the strict Platform consumer accepts both forms, then emit the group list from Notes. Validate the independent fleet pin updates alongside that chain.
- Publish each reviewed child only after its local gates pass. Wait for child CI, validate the combined snapshot, then advance workspace pins.

## Capabilities

### New Capabilities

- `notes-write-contract-completion`: portable write names and the optional group conflict path list; completes the four retained OBS-024 tasks without archiving that change.

### Modified Capabilities

None. The source `notes-write-command` delta is still in the active OBS-024 change.

## Impact

Dependency order: contracts first; Platform and all Rust contracts consumers (channel-digests, chatgpt, claude, extractor, github, instagram, knowledge, sites, telegram, threads, vault and x); Notes as the conflict producer after Platform CI. Independent pin-only consumers can run alongside that chain; all child checks join before workspace integration and pins. Notes may first need a compile-only field initialization with emission disabled. Refresh affected generated snapshots in site-sdk and Web after their API producers. Inspect the other client snapshots without changing unrelated API subsets. Web, Obsidian Plugin and Export Agent acceptance covers the existing name guards and conflict read behavior.

OBS-029 is the separate coordination record. No database schema change, dependency addition, API major, production operation or real Sync-account test belongs to it. OBS-024 6.7 stays open. SEC-030 separately owns the approved ZIP security upgrade. If a gate fails, stop promotion. A corrective snapshot must retain its ZIP fixes. Stop Notes emission first; replay containing `stale_paths` requires the expanded consumer. Do not roll back that consumer while new events remain in the stream or publish ZIP 8.6.0 as a normal rollback release.
