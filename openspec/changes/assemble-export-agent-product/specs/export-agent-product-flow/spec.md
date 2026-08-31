## Purpose

Defines the observable macOS product flow that turns a user-selected provider export into a safely
retained, authenticated, and truthfully reported Ratatoskr archive import.

## ADDED Requirements

### Requirement: The installed agent becomes operational only from durable approved state
The Export Agent SHALL expose whether its Platform origin, paired device identity, credential,
selected inbox, and immutable archive location are ready. It SHALL start archive work only after all
required state is valid, restore that non-secret state after relaunch, and keep all credentials in
macOS Keychain. A smoke launch SHALL prove process startup only and MUST NOT claim operational
readiness.

#### Scenario: First launch requires onboarding
- **WHEN** the installed agent starts without a Platform origin, paired identity, or selected inbox
- **THEN** it presents the missing setup actions and sends no archive or authenticated request

#### Scenario: Relaunch restores an approved installation
- **WHEN** a previously paired installation relaunches with valid bookmarks and Keychain material
- **THEN** it resumes watching and authenticated work without asking for another pairing code

#### Scenario: Lost credential fails closed
- **WHEN** non-secret paired identity exists but its Keychain credential is unavailable
- **THEN** the agent presents re-pairing required and preserves every archive and journal entry

### Requirement: Every stable export follows one durable provider-owned pipeline
For every eligible stable file, the agent SHALL determine a supported provider, preserve the exact
bytes in its immutable local store before network delivery, and durably bind that provider,
fingerprint, local record, queue state, and backend operation to one journal entry. ChatGPT and
Claude entries SHALL route independently, and an unknown or ambiguous archive MUST remain local
until the user explicitly resolves its provider.

#### Scenario: Mixed providers route independently
- **WHEN** one stable ChatGPT export and one stable Claude export enter the selected inbox
- **THEN** each preserved entry is submitted only to its matching Platform provider route

#### Scenario: Unknown export does not guess a destination
- **WHEN** a stable archive cannot be classified as ChatGPT or Claude with sufficient evidence
- **THEN** its exact bytes remain preserved and no provider upload starts until the user chooses

#### Scenario: Duplicate bytes do not duplicate server work
- **WHEN** the same provider export bytes are observed again after an operation is already bound
- **THEN** the agent retains one content identity and does not create a second backend operation

### Requirement: Runtime work survives interruption without losing authority
The agent SHALL durably checkpoint candidate processing, upload acknowledgement, retry control, and
last valid backend observation before presenting progress. Relaunch, sleep and wake, network loss,
or process termination SHALL resume eligible work without changing its provider, fingerprint,
operation identity, or immutable local archive. Shutdown SHALL stop new work and preserve all
recoverable state.

#### Scenario: Relaunch resumes the same prepared operation
- **WHEN** delivery fails after Platform prepared an operation and the agent then relaunches
- **THEN** it resumes the remaining delivery for that operation without a second prepare request

#### Scenario: Offline work stays queued
- **WHEN** the network is unavailable during an eligible upload
- **THEN** the entry remains durably queued with bounded retry timing and the local archive intact

#### Scenario: Sleep and wake reconcile missed files
- **WHEN** a stable export appears while the Mac is asleep and the agent later receives wake
- **THEN** a bounded reconciliation discovers it exactly as normal filesystem observation would

### Requirement: The user can operate and inspect the real runtime
The application SHALL expose current pairing, folder, queue, import-history, and runtime-health
state from the same durable runtime that performs work. It SHALL provide retry, pause, cancel,
re-pair, revoke, and folder authorization actions with their documented safety semantics. Terminal
completeness SHALL come only from a valid Platform operation result; unavailable or malformed reads
SHALL retain the last known observation and MUST NOT become success.

#### Scenario: User pauses queued work
- **WHEN** the user pauses an entry before its next eligible transfer
- **THEN** no request is sent for it and its immutable local archive remains available

#### Scenario: Backend is unreachable after a known observation
- **WHEN** operation polling fails after a valid processing observation was stored
- **THEN** the UI shows that observation as last known and does not invent a terminal result

#### Scenario: Private terminal notice is emitted once
- **WHEN** a new terminal result is stored and local notification permission is authorized
- **THEN** the agent sends one generic notice containing no provider, path, filename, content, hash,
  count, credential, report reference, or backend diagnostic
