## Purpose

Keep the ZIP readers on an advisory-clean dependency without replacing their bounded per-entry extraction boundary.

## ADDED Requirements

### Requirement: The archive graph excludes the affected ZIP release

Every tracked ChatGPT, Claude, Instagram and Threads lock SHALL resolve zip 9.0.0 or a reviewed patched release, including standalone fuzz workspaces. Instagram CI and DEVELOPMENT SHALL run locked metadata for its fuzz manifest to detect drift from the archive path dependency. The dependency-policy gate SHALL pass without ignoring RUSTSEC-2026-0367, RUSTSEC-2026-0368 or RUSTSEC-2026-0369.

#### Scenario: An existing vulnerable lock is checked

- **WHEN** cargo-deny checks the existing zip 8.6.0 lock
- **THEN** it refuses that lock with the listed advisories

#### Scenario: The reviewed update is accepted

- **WHEN** every affected repository resolves the reviewed patched release
- **THEN** dependency policy, all archive tests, the full local gate and hosted CI pass

### Requirement: Existing extraction safety remains in force

The update SHALL retain bounded entry reads, path validation and private staging. It SHALL NOT introduce ZIP bulk extraction or restore archive-supplied Unix privileges. Product API and database versions SHALL remain unchanged.

#### Scenario: The updated reader handles hostile archive inputs

- **WHEN** the existing traversal, special-file and resource-limit suites run against the new graph
- **THEN** all existing refusals and valid archive behavior remain correct

### Requirement: A filename decode error is a typed refusal

An archive reader SHALL refuse an entry whose UTF-8 flag names invalid UTF-8 bytes. It SHALL map the fallible filename API to its existing typed archive error before it stages extracted entry content. It SHALL NOT replace the failed name with a lossy or empty string.

#### Scenario: A flagged UTF-8 filename is malformed

- **WHEN** a ZIP entry has the UTF-8 flag and an invalid UTF-8 filename
- **THEN** the reader returns its typed refusal without treating a replacement-character name as a valid path

#### Scenario: A standalone fuzz graph is stale

- **WHEN** the archive dependency or contracts pin changes while the fuzz lock stays on the old graph
- **THEN** the locked fuzz metadata gate refuses that snapshot until the reviewed graph is current

### Requirement: Legacy filename decoding stays stable

ChatGPT and Threads SHALL decode unflagged legacy filename bytes as CP437, as their previous reader did. A valid Unicode Path extra field SHALL retain its validated Unicode name. Flagged invalid UTF-8 SHALL remain a typed refusal.

#### Scenario: Legacy bytes are also valid UTF-8

- **WHEN** an unflagged filename contains bytes C3 A9 without a Unicode Path extra field
- **THEN** its decoded name contains `├⌐`, without a silent change to `é`
