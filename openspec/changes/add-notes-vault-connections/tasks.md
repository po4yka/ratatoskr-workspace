# Tasks

## 1. Implementation by repository

Dependency order. Each item closes only after its pull request merges, and carries the link. Each
child repository works on the task branch `obs-023/notes-vault-connections`.

- [ ] 1.1 `ratatoskr-contracts`: the three event schemas, their fixtures, and the operation kind `notes.connection.connect` (group 4). It merges first, because every other repository builds against them. PR: _link_
- [ ] 1.2 `ratatoskr-notes` (new repository): the service, the secret custody, the Sync supervisor, the read group, the index, the read API and the device channel routes (groups 5 to 8). PR: _link_
- [ ] 1.3 `ratatoskr-platform`: the Edge route with the device-kind claim, the connect proxy, the two Knowledge durables, the `NOTES` identity, the device kind `obsidian_plugin` and the authority row (group 9). PR: _link_
- [ ] 1.4 `ratatoskr-knowledge`: the note intake (group 10). It merges after 1.3, because its durables must exist. PR: _link_
- [ ] 1.5 `ratatoskr-obsidian-plugin` (new repository): the `plugin` channel (group 11). PR: _link_
- [ ] 1.6 `ratatoskr-export-agent`: the `cli` channel (group 12). PR: _link_
- [ ] 1.7 `ratatoskr-web`: connections and read-only browse (group 13). PR: _link_
- [ ] 1.8 `ratatoskr-workspace`, last: fleet membership, deploy roles, `DEPLOYMENT_TARGET.md` rows, harness checks, integration profile and pins (groups 14 and 15). PR: _link_

## 2. Planning records

- [x] 2.1 Write `changesets/OBS-023-notes-vault-connections.yaml`: affected repositories, task branches, merge order, rollout and rollback as in `design.md`, with `state: planned`. No test: a planning record. Verify with `./ws manifest check` and `openspec validate add-notes-vault-connections --strict`.
- [x] 2.2 Write `docs/adr/0010-notes-and-obsidian-vault-connections.md` and `docs/NOTES_AND_SITES.md`, and list ADR-0010 in `docs/adr/README.md`. No test: documentation.
- [x] 2.3 Align the wording of ADR-0010 with design D4, D5 and D12: Edge mints only a device-kind claim and the notes service checks the owner and the channel; login and cleanup run as oneshot template units that get secrets through `LoadCredential=`; both passwords go to `ob` on standard input, so no argv fallback is needed (spike 3.2), and `PrivatePIDs=` is not used; the plugin credential never enters the vault; one device per device-channel connection; the read group `ratatoskr-notes-blobs`. No test: documentation. Verify that ADR-0010 and `docs/NOTES_AND_SITES.md` name no mechanism that design.md rejects.

## 3. Spike (no code is kept)

- [ ] 3.1 Install `obsidian-headless` at a pinned version with Node.js 22 on a linux/arm64 Debian 12 machine of the same class as the host. Log in to a test account with MFA, set up an end-to-end encrypted test vault, and run `ob sync --continuous` for 24 hours. Record resident memory, CPU and restarts. No test: investigation. Record the numbers in design D3 and in the risk entry about memory. Deferred by the owner on 2026-10-13: it needs a test account with Sync and MFA. Groups 5.8, 5.9, 6 and the stub replay in 6.5 wait for it.
- [x] 3.2 Find out whether `ob login` and `ob sync-setup` accept the password and the end-to-end password on standard input or from a file, and whether `ob` needs the password again after setup. If `ob` needs argv, mount `/proc` with `hidepid=invisible` on the test machine and record what changes for the node-exporter, vmagent and `systemctl status`. No test: investigation. Record the result in design D4 and choose step 3 or its fallback. Result (2026-10-13, `spike/3.2-obsidian-headless.md`): both passwords are read from standard input, `ob sync` never needs them again, and no `hidepid=invisible` fallback is needed; recorded in design D3 and D4.
- [ ] 3.3 With `--mode pull-only`, edit a file in the working tree and change the same file remotely at the same time. Record what `ob` does with the local edit and the remote change, for both conflict strategies. Record one pull-only session (the requests that `ob` makes and the files it writes) as the fixture that the stub `ob` of group 6 replays. No test: investigation. Record the result in design D3 for OBS-024, and keep the recorded session for 6.5. Deferred by the owner on 2026-10-13, for the same reason as 3.1.
- [ ] 3.4 Read the Obsidian terms of use and the Sync terms for automated use on a server, and ask Obsidian support if the terms do not answer it. No test: investigation. Record the result in ADR-0010. If the answer is no, revise this change with `openspec update` before any later group starts: move the `sync` channel work (tasks 5.8, 5.9, group 6 and the `sync` parts of groups 14 and 15) into a new change, so that no task here stays unticked. Status 2026-10-13: the documentation permits the use and the Terms are silent; evidence and the draft email to Obsidian support are in `spike/3.4-obsidian-terms.md`. Open until support answers.
- [ ] 3.5 Build a throwaway plugin that logs `create`, `modify`, `rename` and `delete` vault events on desktop and on iOS, including a rename of a folder. Find the protected storage outside the vault that the plugin can use on each platform for its credential. No test: investigation. Record the events and the storage per platform in design D5. Desktop part done on 2026-10-13 (`spike/obsidian-1.14.4/`, design D5); the iOS part is deferred by the owner, so this task stays open.
- [x] 3.6 Build the fixture vault of design D8 (duplicate names, aliases, headings, blocks, embeds, comments, code, NFD names, frontmatter tags), and capture `obsidian links`, `obsidian backlinks format=json`, `obsidian tags` and `obsidian properties` for every file with the current Obsidian version. No test: investigation; the output becomes the golden fixtures of group 7. Keep the vault and the outputs for 7.1. Done on 2026-10-13 with Obsidian 1.14.4: the installer on the spike machine was 1.8.10, so the data came from the engine through a recording plugin instead of the CLI; vault and outputs in `spike/obsidian-1.14.4/`.

## 4. Contracts (ratatoskr-contracts)

- [x] 4.1 RED: add fixtures under `fixtures/events/notes.vault.connected.v1`, `notes.vault.disconnected.v1` and `notes.file.changed.v1`, including one invalid fixture each with an extra field and one `file.changed` fixture of kind `deleted` that carries a `BlobRef`. Register the three types in `contracts.toml` with producer `ratatoskr-notes` and consumer `ratatoskr-knowledge`. Add `tools/contractsc/tests/fixtures.rs::notes_vault_fixtures_refuse_unknown_fields`, which asserts that every invalid fixture is refused. Confirm that it fails because the schema files do not exist.
- [x] 4.2 GREEN: add the crate `ratatoskr-notes-contracts` and the three schemas under `schemas/events/`. Verify that 4.1 passes, that the `deleted` fixture with a `BlobRef` is refused, and that `cargo test --test live_message_types` passes.

The operation kind `notes.connection.connect` needs no contracts task. `OperationKind` in
`ratatoskr-operation-contracts` is an open validated string, and contracts holds no registry of kinds
or reporter lanes, so no test there could fail first. The kind and its reporter lane
`ratatoskr-notes` are enforced by Platform's authority table, in tasks 9.3 and 9.4. (Corrected on
2026-10-13; this replaces the former tasks 4.3 and 4.4.)

## 5. Notes repository, connections and secrets (ratatoskr-notes)

- [ ] 5.1 Create the repository from the fleet template with `AGENTS.md`, `DEVELOPMENT.md`, `ci.yml`, the vendored Rust skills, `schema.sql`, `deploy/postgres/role.sql`, `deploy/nats/identity.conf` and `deploy/systemd/notes.conf.example`. No test: scaffolding. Verify that `cargo test` and the CI workflow run green on the empty service.
- [ ] 5.2 RED: `services/notes/tests/connections.rs::second_channel_for_one_vault_is_refused` asserts `409` with `notes.connection.vault_already_connected` for a `plugin` connection after a `sync` connection with the same vault key; `two_owners_may_connect_one_remote_vault` asserts that two owners each get a connection for one remote vault id. Confirm that both fail because the route does not exist.
- [ ] 5.3 GREEN: implement `notes.connections` and the uniqueness of `(owner, vault_key)` for active connections. Verify both tests of 5.2.
- [ ] 5.4 RED: `services/notes/tests/connections.rs::disconnect_removes_unit_tree_state_and_secrets` asserts that disconnect publishes one `evt.notes.vault.disconnected.v1`, stops the sync unit and starts the cleanup unit through a fake systemd bus, and that the tree, the client state and the ciphertext are gone. Confirm that it fails because disconnect does not exist.
- [ ] 5.5 GREEN: implement disconnect and ship `deploy/systemd/ratatoskr-notes-cleanup@.service`. Verify 5.4.
- [ ] 5.6 RED: `services/notes/tests/secret_custody.rs::marker_secrets_appear_nowhere_in_notes` connects with marker secrets and asserts that no marker is in any notes table except the ciphertext column, the outbox, the captured journal of the service and its units, or the published events; `wrong_e2e_password_fails_with_its_code` asserts the code `notes.sync.e2e_password_wrong` and no active connection; `stored_secret_is_ciphertext_without_mfa` asserts a ciphertext and nonce, no MFA code, and a failed decryption without the key file. Confirm that all three fail because the connect flow does not exist.
- [ ] 5.7 GREEN: implement the encryption with the key file and the connect flow with redacted errors and the four stable login codes. Verify the three tests of 5.6.
- [ ] 5.8 RED: `services/notes/tests/secret_custody.rs::login_unit_gets_secrets_only_as_credentials` asserts that the rendered login unit uses `LoadCredential=` for each secret, that the credential files are mode 0600 under a 0700 directory, and that they are gone after the unit stops; `no_secret_in_any_cmdline` runs the login against a stub `ob` that sleeps and asserts that a process of another user reads no marker from `/proc/*/cmdline`. Confirm that both fail because the login unit does not exist.
- [ ] 5.9 GREEN: ship `deploy/systemd/ratatoskr-notes-login@.service` and implement the credential files as task 3.2 decided: the unit runs as `ratatoskr-notes-sync` and gives each password to `ob` on standard input from `$CREDENTIALS_DIRECTORY`, in two steps (design D4). Verify both tests of 5.8.
- [ ] 5.10 Write the README and `DEVELOPMENT.md` sections on connections, the three template units and secret custody. No test: documentation.

## 6. Sync channel and blob root (ratatoskr-notes)

- [ ] 6.1 RED: `services/notes/tests/sync_supervisor.rs::connect_starts_one_unit_in_pull_only_mode` asserts, with a stub `ob` that records its calls, that a connect calls `sync-config --mode pull-only --configs ""` with the device name `ratatoskr-<id>` and starts `ratatoskr-notes-sync@<id>.service`. Confirm that it fails because the supervisor does not exist.
- [ ] 6.2 GREEN: implement the supervisor through the systemd D-Bus API, and ship `deploy/systemd/ratatoskr-notes-sync@.service` with `MemoryMax=` from 3.1 and one polkit rule that allows exactly the sync, login and cleanup template units. Verify 6.1, and that the polkit rule test `deploy/tests/polkit_rule.rs::rule_allows_exactly_the_three_template_units` passes.
- [ ] 6.3 RED: `services/notes/tests/sync_watcher.rs::settled_change_becomes_one_revision` writes a file in three parts within one second into a watched tree and asserts exactly one revision after the settle window. Confirm that it fails because the watcher does not exist.
- [ ] 6.4 GREEN: implement the inotify watcher, the settle window and the 15-minute rescan. Verify 6.3.
- [ ] 6.5 RED: commit the session recorded in 3.3 under `services/notes/tests/fixtures/ob-pull-only/`, and add `services/notes/tests/sync_supervisor.rs::pull_only_connection_never_pushes_a_local_edit`: the stub `ob` replays the session and logs every upload it is asked to make; a local edit in the working tree must produce no upload, and after the next replayed pull the file must hold the remote bytes. Confirm that it fails because the stub cannot yet replay a session.
- [ ] 6.6 GREEN: implement the replaying stub `ob` in the test support crate, and make the supervisor pass `--mode pull-only` on every start. Verify 6.5.
- [ ] 6.7 RED: `services/notes/tests/blob_root.rs::new_blob_is_group_readable_and_not_world_readable` prepares a blob root as the deploy role does (group `ratatoskr-notes-blobs`, mode 2750) and asserts that a new revision is mode 0640 with that group and that each new directory is mode 2750. Confirm that it fails because the service writes with the default umask.
- [ ] 6.8 GREEN: set `UMask=0027` in the service unit and in the blob store's own file creation, and keep the setgid bit on new directories. Verify 6.7, and document the read group in the README.
- [ ] 6.9 RED: `services/notes/tests/sync_supervisor.rs::auth_failure_stops_the_unit_and_waits_for_the_owner` runs a stub `ob` that logs `Failed to authenticate:` every 30 seconds under paused time, and asserts that after 5 minutes the unit is stopped once, the connection is `login_expired` with `notes.sync.login_expired`, and no login unit starts. Confirm that it fails because the connection stays `active`.
- [ ] 6.10 GREEN: read the sync unit's journal for that one line only (design D3), stop the unit after 5 minutes of repeats, and set the state. Pin the `obsidian-headless` version in the deploy role, because a release can change the line. Verify 6.9.

## 7. Index, file events and read API (ratatoskr-notes)

- [ ] 7.1 RED: commit the fixture vault and the outputs from 3.6 under `crates/notes-index/tests/fixtures/obsidian-<version>/`, and add `crates/notes-index/tests/golden.rs::index_matches_obsidian_engine_output`, which asserts that the links, backlinks, tags and properties of each fixture file equal the stored output. Confirm that it fails because the index does not exist.
- [ ] 7.2 GREEN: implement the parser and the link resolution of design D8. Verify 7.1, `crates/notes-index/tests/parse.rs::every_link_form_is_indexed`, `parse.rs::comment_links_count_and_code_links_do_not` and `crates/notes-index/tests/resolve.rs::same_folder_then_shortest_path_wins`.
- [ ] 7.3 RED: `crates/notes-index/tests/paths.rs::case_fold_collision_publishes_one` asserts one published file and a `notes.file.path_collision` status for `Note.md` and `note.md`; `obsidian_config_is_never_published` asserts no event for `.obsidian/plugins/x/data.json`; `nfd_path_is_published_as_nfc` asserts the NFC form and one `file_id` for an NFD and an NFC path. Confirm that all three fail because the path rules do not exist.
- [ ] 7.4 GREEN: implement NFC paths, path keys, collisions and exclusions. Verify 7.3.
- [ ] 7.5 RED: in `services/notes/tests/file_events.rs`, `created_file_publishes_one_event_with_blob_ref` asserts one `created` event whose `BlobRef` digest equals the revision; `blob_ref_digest_equals_revision` asserts that the bytes read through the `BlobRef` hash to the revision; `identical_bytes_publish_nothing` asserts no event for a second save with equal bytes; `connection_sequence_has_no_gaps` asserts sequences 1 to N after 100 mixed changes; `excluding_a_folder_publishes_each_file_deleted_once` asserts three `deleted` events and no later event under the excluded folder. Confirm that all five fail because no event is published.
- [ ] 7.6 GREEN: implement revisions, the blob root, the outbox, the connection sequence and the excluded-folder setting. Verify the five tests of 7.5.
- [ ] 7.7 RED: `services/notes/tests/read_api.rs::foreign_connection_is_not_found` asserts that owner B reads a file of their own connection with `200` and that owner A gets `404` for the same path; `file_routes_refuse_writes` asserts `405` and no new revision for `PUT` and `DELETE` on a file route. Confirm that both fail because the read routes do not exist, so owner B gets `404` and the writes get `404` instead of `405`.
- [ ] 7.8 GREEN: implement the read routes on the listener 8099. Verify both tests of 7.7.

## 8. Device channel routes (ratatoskr-notes)

- [ ] 8.1 RED: in `services/notes/tests/device_channel.rs`, `duplicate_batch_is_idempotent` asserts one revision and one event per change for a batch sent twice; `sequence_gap_commits_nothing` asserts `notes.channel.sequence_gap` with the committed sequence 10 for a batch that starts at 12; `oversized_batch_commits_nothing` asserts `notes.channel.batch_too_large` for 257 changes. Confirm that all three fail because the route does not exist.
- [ ] 8.2 GREEN: implement change batches, the size limit, the sequence check and the sequence gap answer. Verify 8.1.
- [ ] 8.3 RED: `services/notes/tests/device_channel.rs::foreign_connection_changes_are_not_found` asserts `404` and no change for a batch from owner A's device to owner B's connection; `export_agent_on_plugin_connection_is_channel_mismatch` asserts `notes.channel_mismatch` for an `export_agent` claim on a `plugin` connection; `second_device_for_one_connection_is_refused` asserts `notes.channel_mismatch`, the Sync hint, and an unchanged device for a second device with the same vault id. Confirm that all three fail because the route accepts any claim.
- [ ] 8.4 GREEN: implement the owner, channel and device checks from the minted claim. Verify 8.3.
- [ ] 8.5 RED: `services/notes/tests/device_channel.rs::upload_with_wrong_digest_is_refused` asserts `transfer.digest_mismatch` and no registered blob for bytes that do not match the declared SHA-256. Confirm that it fails because the blob route does not exist.
- [ ] 8.6 GREEN: implement the blob receipt of the shared transfer contract. Verify 8.5.
- [ ] 8.7 RED: `services/notes/tests/device_channel.rs::manifest_reconciles_offline_changes` asserts exactly one `updated`, one `deleted`, one `renamed` and one `created` change after a manifest of a vault with four offline changes. Confirm that it fails because the manifest route does not exist.
- [ ] 8.8 GREEN: implement the manifest reconciliation. Verify 8.7.

## 9. Platform (ratatoskr-platform)

- [ ] 9.1 RED: `crates/public-api/tests/notes_routes.rs::device_claim_names_the_device_kind` asserts that a stub notes upstream receives a minted claim with the owner, the device id and the kind `obsidian_plugin`, and no client-supplied identity header; `connect_body_is_not_persisted_or_logged` sends a connect body with marker secrets and asserts that no Platform table, the outbox, the idempotency and audit records, and the captured log output hold a marker, and that the stub received the body unchanged with the minted operation id. Confirm that both fail because the route does not exist.
- [ ] 9.2 GREEN: add the `notes` entry to the route table (`/v1/notes`, loopback 8099, `control`, and `transfer` for `/blobs`), the device kind `obsidian_plugin`, the claim that names the device kind, and the connect proxy that mints the operation id and excludes the body from idempotency storage, audit and logs. Verify both tests of 9.1.
- [ ] 9.3 RED: `crates/operations/tests/report_authority.rs::notes_connect_accepts_only_the_notes_lane` asserts that a report from the X identity for a `notes.connection.connect` operation is rejected and the status is unchanged. Confirm that it fails because the kind is not minted.
- [ ] 9.4 GREEN: add the authority row and the mint site. Verify 9.3 and `every_minted_operation_kind_has_an_authority_row`.
- [ ] 9.5 RED: extend `crates/eventing/tests/nats_permissions.rs` with the case `notes_identity_publishes_its_events_and_knowledge_reads_its_durables`, which asserts that `NOTES` can publish `evt.notes.file.changed.v1` and that Knowledge can fetch from `ratatoskr_knowledge_notes_files` and `ratatoskr_knowledge_notes_vaults`. Confirm that it fails because the identity and the durables do not exist.
- [ ] 9.6 GREEN: add the `NOTES` stanza to `deploy/nats/ratatoskr.conf` and the two durables to `crates/eventing/src/stream.rs`. Verify 9.5.

## 10. Knowledge (ratatoskr-knowledge)

- [ ] 10.1 RED: `services/knowledge/tests/notes_intake.rs::one_run_per_file_revision` delivers one `created` event three times and asserts exactly one analysis run for its `file_id` and revision; `non_markdown_file_creates_no_run` asserts no run and an acknowledged message for a PNG. Confirm that both fail because Knowledge has no consumer on `ratatoskr_knowledge_notes_files`.
- [ ] 10.2 GREEN: implement the intake on `ratatoskr_knowledge_notes_files`, with the inbox key `(file_id, revision)`. Verify both tests of 10.1.
- [ ] 10.3 RED: `services/knowledge/tests/notes_intake.rs::disconnect_removes_all_derived_data` asserts that no search result and no embedding of 30 analysed files remains after `evt.notes.vault.disconnected.v1`; `older_event_after_delete_creates_nothing` asserts no run for an `updated` event with a lower sequence after a `deleted` event. Confirm that both fail because removal does not exist.
- [ ] 10.4 GREEN: implement removal on `deleted` and on `ratatoskr_knowledge_notes_vaults`. Verify 10.3.
- [ ] 10.5 RED: `services/knowledge/tests/notes_intake.rs::missing_blob_is_transient` asserts a negative acknowledgement with the transient delay and no run when the blob is missing. Confirm that it fails because the notes blob root is not configured.
- [ ] 10.6 GREEN: read the notes blob root read-only with the configuration key `RATATOSKR__BLOBS__NOTES_ROOT`, and add `SupplementaryGroups=ratatoskr-notes-blobs` to the Knowledge unit. Verify 10.5 and the deployment-profile test with the new key.

## 11. Obsidian plugin (ratatoskr-obsidian-plugin)

- [ ] 11.1 Create the repository with the Obsidian sample plugin layout, TypeScript strict mode, the fleet `ci.yml` and the Edge client generated from the contracts. No test: scaffolding. Verify that the build and the lint run green.
- [ ] 11.2 RED: `tests/batcher.test.ts` "a rename arrives as one renamed change" feeds `rename` and `modify` events of the vault API into the batcher and asserts one `renamed` change with the old path. Confirm that it fails because the batcher does not exist.
- [ ] 11.3 GREEN: implement the batcher and the device sequence. Verify 11.2.
- [ ] 11.4 RED: `tests/batcher.test.ts` "a folder rename moves each file once" replays the recorded spike sequence (one folder `rename`, then one `rename` per file) and asserts exactly one `renamed` change per file and none for the folder; "an outside rename is paired by hash" replays `create` then `delete` 1 s apart with equal content hashes and asserts one `renamed` change. Confirm that both fail because the batcher forwards every event.
- [ ] 11.5 GREEN: skip folder `rename` events, pair `create` and `delete` with equal hashes within 3 seconds (design D5), and send NFC paths. Verify 11.4.
- [ ] 11.6 RED: `tests/credential.test.ts` "credential_never_written_to_data_json" pairs, connects and sends a batch in a test vault with a fake Edge, then reads every file under the vault folder and asserts that none contains the credential or the refresh token. Confirm that it fails because the default `saveData` path writes the credential into `data.json`.
- [ ] 11.7 GREEN: keep the credential in `app.secretStorage` on desktop (design D5), with `remote.safeStorage` as the fallback, and in memory only where neither exists. Verify 11.6.
- [ ] 11.8 RED: `tests/sync.test.ts` "a sync connection makes the plugin status-only" answers the connect request with `notes.connection.vault_already_connected` and `channel = sync`, and asserts that the plugin sends no batch. Confirm that it fails because the plugin retries the connect and then sends.
- [ ] 11.9 GREEN: implement pairing, connect, upload, batches, manifest reconciliation, the status-only mode, and the message for `notes.channel_mismatch` that points to Sync. Verify 11.8.
- [ ] 11.10 Write the README: pairing, where the credential is kept, what the plugin sends, and what Ratatoskr can read. No test: documentation.

## 12. Export agent (ratatoskr-export-agent)

- [ ] 12.1 RED: `Tests/AgentCoreTests/VaultWatcherTests.swift` `testDeleteAndCreateWithEqualHashIsRename` feeds a delete and a create with equal hashes and asserts one `renamed` change. Confirm that it fails because the vault watcher does not exist.
- [ ] 12.2 GREEN: implement the vault mode with FSEvents, the Obsidian CLI rename check, and the same batch format as the plugin. Verify 12.1.

## 13. Web client (ratatoskr-web)

- [ ] 13.1 RED: `src/features/notes/connect.test.tsx` "the end-to-end password is asked only after the server-access notice is accepted" asserts that the password field is absent until the notice is accepted. Confirm that it fails because the connect view does not exist.
- [ ] 13.2 GREEN: implement the connection list, the connect flow with the notice, the operation progress, and read-only browse with backlinks. Verify 13.1 and the existing route tests.

## 14. Workspace (ratatoskr-workspace)

- [ ] 14.1 RED: add `notes` and `obsidian-plugin` to `workspace.toml` without pins, and run `harness/crates/workspace-cli/tests/committed_snapshot.rs::committed_workspace_is_complete_and_current`. Confirm that it fails and names both repositories as unpinned.
- [ ] 14.2 GREEN: add the submodules at the merges of 1.2 and 1.5, and run `./ws lock generate`. Verify 14.1 and `./ws doctor`.
- [ ] 14.3 RED: in `harness/crates/workspace-core/tests/bus_acl.rs`, grow `IDENTITIES` and `OWNERS` from 13 to 14 entries with `NOTES` (owner `notes`), rename `platform_conf_has_exactly_the_thirteen_identities` to `platform_conf_has_exactly_the_fourteen_identities`, and add `notes` to the inbox-prefix table; in `bus_durables.rs`, grow `DOMAIN` from 23 to 25 entries with `ratatoskr_knowledge_notes_files` (`evt.notes.file.changed.v1`) and `ratatoskr_knowledge_notes_vaults` (`evt.notes.vault.>`), both owned by `knowledge`; add the notes route 8099 to the implemented group of `every_implemented_edge_upstream_is_bound_by_its_owner`. Run them against the current pins. Confirm that `platform_conf_has_exactly_the_fourteen_identities` fails because the pinned Platform configuration holds 13 identities, that `platform_names_every_durable_with_its_contract_filter` fails because the pinned Platform table has no notes durables, and that the upstream test fails because nothing binds 8099.
- [ ] 14.4 GREEN: advance the pins of 1.2, 1.3 and 1.4. Verify the tests of 14.3, `every_service_fragment_equals_its_platform_stanza`, `every_owner_hard_codes_its_durable_name_and_filter` and `no_two_deploy_examples_bind_the_same_port_and_every_bind_is_allocated`.
- [ ] 14.5 Add the rows 8099 and 9471, the storage rows, the read group, the three template units and the per-connection memory budget to `docs/DEPLOYMENT_TARGET.md`, and the server-access risk to `docs/THREAT_MODEL.md`. No test: documentation; 14.4 checks the ports.
Tasks 14.6 and 14.7 wait until `add-deployment-automation` (DPL-022) is merged and archived, because they need its Ansible tree, Molecule scenario, freeze guard, `services.json` and `deploy_inventory.rs`.

- [ ] 14.6 RED: add the Molecule verify cases `notes_sync_unit` (the three template units exist, Node.js 22 and the pinned `obsidian-headless` are installed, the user `ratatoskr-notes-sync` exists, and the polkit rule names exactly the three units) and `notes_blob_read_group` (the group `ratatoskr-notes-blobs` exists, the root is mode 2750 with that group, the Knowledge service user can read a blob, and `ratatoskr-x` cannot). Confirm that both fail because the roles do not exist.
- [ ] 14.7 GREEN: add the `notes` entry to `services.json`, a `nodejs` role with the pinned package, the group, the root and the Knowledge membership. Spike 3.2 needs no `hidepid=invisible` mount. Verify 14.6 and idempotence.

## 15. Integration

- [ ] 15.1 RED: add `integration/tests/notes_sync_connect.sh` with a recorded fake of the Sync service, which asserts that the connect operation passes through its four phases and completes with one `evt.notes.vault.connected.v1`, and `integration/tests/notes_channel_equivalence.sh`, which asserts equal path sets, hashes and index digests for the fixture vault through the three channels. Confirm that both fail before the pins of group 14, because the pinned snapshot has no notes service.
- [ ] 15.2 GREEN: run both against the pinned snapshot. Verify that both pass and that Knowledge returns the fixture notes in search.
