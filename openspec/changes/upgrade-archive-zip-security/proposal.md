## Why

OBS-029 stops at the ChatGPT dependency-policy gate. The existing zip 8.6.0 lock resolves RUSTSEC-2026-0367, RUSTSEC-2026-0368 and RUSTSEC-2026-0369. Claude, Instagram and Threads use the same version. Upstream names 9.0.0 as patched. These are dependency findings, not a confirmed exploit of the Ratatoskr extraction paths.

## What Changes

- Move only zip from 8.6.0 to the reviewed 9.0.0 caret range in ChatGPT, Claude, Instagram and Threads. Keep default features off and the existing deflate feature.
- Preserve all unrelated dependencies; admit only necessary, reviewed lock changes in every tracked graph, including Instagram fuzz. Review every new package before compilation. Add its locked metadata command to CI and DEVELOPMENT so a stale standalone graph fails the gate.
- Make only API compatibility edits that preserve bounded per-entry reads and the current private staging rules. Keep all product APIs and schemas at their first version.
- Run the existing archive security tests and each complete local gate, independent source review and exact-commit CI. No advisory ignore is permitted.

## Capabilities

### New Capabilities

- `archive-zip-security`: an advisory-clean ZIP dependency in the four archive readers without a change to their safety boundary.

### Modified Capabilities

None.

## Impact

SEC-030 is a prerequisite for the final OBS-029 snapshot. Four archive repositories are affected; no database, production host, wire contract or credential changes are included. The owner approved this major dependency update as a separate wave because OBS-029 excludes unrelated upgrades. The other five pin-only consumers continue independently.
