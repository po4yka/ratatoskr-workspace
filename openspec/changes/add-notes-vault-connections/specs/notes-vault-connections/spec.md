# Spec Delta

## Purpose

Defines how an owner connects an Obsidian vault to Ratatoskr and disconnects it, the rule that one
connection has one channel, how Obsidian secrets are kept, and what other repositories can observe
about a connection.

## ADDED Requirements

### Requirement: A vault connection has exactly one channel

Every vault connection SHALL name exactly one channel: `sync`, `plugin` or `cli`. `ratatoskr-notes`
SHALL refuse to create a connection when the same owner already has an active connection with the
same vault key, whatever the channel of either connection. The refusal SHALL be the contract error
envelope with the stable code `notes.connection.vault_already_connected`, and it SHALL name the
existing connection id and its channel.

#### Scenario: A plugin tries to connect a vault that already syncs

- **WHEN** an owner has an active `sync` connection for a vault, and a paired plugin sends `POST /v1/notes/connections` with `channel = plugin` and the same vault key
- **THEN** the response is `409` with `notes.connection.vault_already_connected`, the existing connection id and `channel = sync`, and no second connection exists, verified by `services/notes/tests/connections.rs::second_channel_for_one_vault_is_refused` in `ratatoskr-notes`

#### Scenario: Two owners connect the same remote vault

- **WHEN** two different owners each connect a shared Obsidian Sync vault with the same remote vault id
- **THEN** both connections exist, because the rule applies per owner, verified by `services/notes/tests/connections.rs::two_owners_may_connect_one_remote_vault` in `ratatoskr-notes`

### Requirement: Connecting a vault is an operation that only notes reports

`POST /v1/notes/connections` SHALL return `202` with an operation of kind
`notes.connection.connect` whose reporter lane is `ratatoskr-notes`. The operation SHALL report the
phases `login`, `setup`, `first_sync` and `indexing` that apply to the channel, and it SHALL complete
only after the first full scan of the vault is indexed. Platform's authority table SHALL list
`ratatoskr-notes` as the only producer for this kind.

#### Scenario: A sync connection completes

- **WHEN** an owner connects a test Sync vault of 50 files through the web client
- **THEN** the operation passes through `login`, `setup`, `first_sync` and `indexing` and completes, and `evt.notes.vault.connected.v1` is published once, verified by `integration/tests/notes_sync_connect.sh` in `ratatoskr-workspace`

#### Scenario: Another lane reports on a connect operation

- **WHEN** an identity other than `NOTES` publishes a report for a `notes.connection.connect` operation
- **THEN** Platform rejects the report and the operation is unchanged, verified by `crates/operations/tests/report_authority.rs::notes_connect_accepts_only_the_notes_lane` in `ratatoskr-platform`

### Requirement: Edge proxies the connect request and keeps none of its body

Edge SHALL forward the body of `POST /v1/notes/connections` to `ratatoskr-notes` unchanged, and
SHALL add only the operation id that it mints. Edge SHALL NOT write any part of the body to its
database, its outbox, its idempotency records, its audit records or its logs.

#### Scenario: Edge handles a connect request with marker secrets

- **WHEN** a test sends a connect request whose password fields hold known markers through Edge to a stub notes upstream, and then searches every Platform table, the outbox, the idempotency and audit records and the captured Edge log output for the markers
- **THEN** no marker is found, and the stub upstream received the body unchanged with the minted operation id, verified by `crates/public-api/tests/notes_routes.rs::connect_body_is_not_persisted_or_logged` in `ratatoskr-platform`

### Requirement: Obsidian secrets never leave the notes service

The Obsidian account password, the MFA code and the end-to-end encryption password SHALL NOT appear
in any event, operation report, log line, error envelope or metrics label that `ratatoskr-notes`
produces.

#### Scenario: A secret is searched for in the notes service after a connect

- **WHEN** a test connects a Sync vault with known marker secrets, and then searches every notes table except the ciphertext column, the outbox, the captured journal of the service and its units, and the published events for the markers
- **THEN** no marker is found, verified by `services/notes/tests/secret_custody.rs::marker_secrets_appear_nowhere_in_notes` in `ratatoskr-notes`

### Requirement: The login runs as a oneshot unit that receives secrets as credentials

The Obsidian login and the cleanup of a connection SHALL run as the oneshot template units
`ratatoskr-notes-login@<connection id>.service` and `ratatoskr-notes-cleanup@<connection id>.service`.
The account password and the end-to-end password SHALL reach the login unit only as systemd
credentials, and SHALL NOT appear in the command line of any process. Only the one-time MFA code
MAY appear in the command line of the login unit.

#### Scenario: The login unit runs

- **WHEN** the login unit runs `ob login` and `ob sync-setup` against a stub `ob` that sleeps, and a process of another user reads `/proc/*/cmdline` during the run
- **THEN** neither marker password is read, verified by `services/notes/tests/secret_custody.rs::no_secret_in_any_cmdline` in `ratatoskr-notes`

#### Scenario: The login unit receives its secrets

- **WHEN** the login unit for a connection is rendered
- **THEN** it loads each secret with `LoadCredential=` from a file that only the notes service user can read, and the file no longer exists after the unit stops, verified by `services/notes/tests/secret_custody.rs::login_unit_gets_secrets_only_as_credentials` in `ratatoskr-notes`

### Requirement: Secrets are kept as ciphertext and a failed login has a stable code

`ratatoskr-notes` SHALL store the account password and the end-to-end password only as ciphertext,
and SHALL NOT store the MFA code. A failed login SHALL be reported with exactly one of the stable
codes `notes.sync.login_failed`, `notes.sync.mfa_required`, `notes.sync.e2e_password_wrong` or
`notes.sync.vault_not_found`.

#### Scenario: The end-to-end password is wrong

- **WHEN** the owner gives a wrong end-to-end password
- **THEN** the operation fails with `notes.sync.e2e_password_wrong`, and no connection becomes active, verified by `services/notes/tests/secret_custody.rs::wrong_e2e_password_fails_with_its_code` in `ratatoskr-notes`

#### Scenario: The stored secret is read from the database

- **WHEN** a test reads the row of a connection in `notes.connection_secrets`
- **THEN** it holds ciphertext and a nonce, it holds no MFA code, and decryption without the key file fails, verified by `services/notes/tests/secret_custody.rs::stored_secret_is_ciphertext_without_mfa` in `ratatoskr-notes`

### Requirement: The host is a named Sync device in pull-only mode

A `sync` connection SHALL appear in the Obsidian Sync history under the device name
`ratatoskr-<connection id>`, and SHALL run in pull-only mode until a later change enables writes. It
SHALL NOT sync the `.obsidian` configuration of the vault.

#### Scenario: A file is edited in the working tree on the host

- **WHEN** a test edits a file in the working tree of a `sync` connection, and the stub `ob` replays the pull-only session that the spike recorded and logs every upload it is asked to make
- **THEN** no upload is logged, and after the next replayed pull the file holds the remote bytes again, verified by `services/notes/tests/sync_supervisor.rs::pull_only_connection_never_pushes_a_local_edit` in `ratatoskr-notes`

#### Scenario: A connection is configured

- **WHEN** a `sync` connection is set up
- **THEN** the stub `ob` records `sync-config --mode pull-only --configs ""` and the device name `ratatoskr-<connection id>`, verified by `services/notes/tests/sync_supervisor.rs::connect_starts_one_unit_in_pull_only_mode` in `ratatoskr-notes`

### Requirement: An expired Sync login stops the connection and waits for the owner

When the `sync` client of a connection reports an authentication failure for 5 minutes,
`ratatoskr-notes` SHALL stop that connection's sync unit, SHALL mark the connection `login_expired`
with the code `notes.sync.login_expired`, and SHALL NOT start a new login by itself.

#### Scenario: The stub client keeps failing to authenticate

- **WHEN** a stub `ob` logs `Failed to authenticate:` every 30 seconds for 5 minutes of paused time
- **THEN** the unit is stopped once, the connection state is `login_expired`, and no login unit is started, verified by `services/notes/tests/sync_supervisor.rs::auth_failure_stops_the_unit_and_waits_for_the_owner` in `ratatoskr-notes`

### Requirement: Connection events name the connection and never its secrets

`ratatoskr-notes` SHALL publish `evt.notes.vault.connected.v1` once when a connection becomes active,
and `evt.notes.vault.disconnected.v1` once when it is removed. Each event SHALL carry the owner as
`tenant_id` `user:<id>`, the connection id, the channel and the vault display name, and nothing else
about the vault.

#### Scenario: A connection is removed

- **WHEN** the owner removes a connection
- **THEN** one `evt.notes.vault.disconnected.v1` is published, the sync unit of a `sync` connection is stopped, the cleanup unit deletes its working tree and its client state, and the stored ciphertext is deleted, verified by `services/notes/tests/connections.rs::disconnect_removes_unit_tree_state_and_secrets` in `ratatoskr-notes`

#### Scenario: The event schema is checked

- **WHEN** `ratatoskr-contracts` validates the fixtures of `notes.vault.connected.v1` and `notes.vault.disconnected.v1`
- **THEN** a fixture with any field outside the schema fails, verified by `tools/contractsc/tests/fixtures.rs::notes_vault_fixtures_refuse_unknown_fields` in `ratatoskr-contracts`
