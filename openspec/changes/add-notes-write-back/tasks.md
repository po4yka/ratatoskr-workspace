# Tasks

## 1. Implementation by repository

Dependency order. Each child item is worked on the task branch `obs-024/notes-write-back`, closes
only after its pull request merges, and carries the link. Archive this change only after
`add-notes-vault-connections` (OBS-023) is archived, and OBS-023 only after `xr-021-fleet-round-5`,
because the `fleet-bus-topology` delta modifies the text those two leave.

- [ ] 1.1 `ratatoskr-contracts`: `notes/write-request.v1`, `notes/conflict.v1`, fixtures, generated types and registry rows (group 3). It merges first, because every other repository builds against these types. PR: _link_
- [ ] 1.2 `ratatoskr-notes`: the write consumer, pending writes, conflicts, write mode, `sync` delivery, the device queue, echo suppression, link rewrite and the durable check (groups 4–9). PR: _link_
- [ ] 1.3 `ratatoskr-platform`: the Edge routes, the operation kinds and their authority rows, the two durables and the NATS ACL lines (group 10). PR: _link_
- [ ] 1.4 `ratatoskr-obsidian-plugin`: pull, apply and report for the `plugin` channel (group 11). PR: _link_
- [ ] 1.5 `ratatoskr-export-agent`: apply and report for the `cli` channel (group 12). PR: _link_
- [ ] 1.6 `ratatoskr-web`: the editor, the write-mode switch and the conflict view (group 13). PR: _link_
- [ ] 1.7 `ratatoskr-workspace`, last, on `main`: the harness checks, the pins, the integration profile and the documentation (group 14). PR or pushed head: _link_

## 2. Planning records

- [x] 2.1 Write the changeset `changesets/OBS-024-notes-write-back.yaml`: affected repositories, task branches, merge order, rollout and rollback as in `design.md`. No test: a planning record. Verify with `./ws manifest check` and `openspec validate add-notes-write-back --strict`.
- [x] 2.2 Record in `docs/NOTES_AND_SITES.md` the seventh write operation `resolve_conflict`, the `origin` field, the upload-first rule, the routes `.../writes`, `.../write-mode`, `.../device-operations` and `/v1/notes/conflicts/{id}`, the operation kinds and the two durables. No test: documentation. Verify that the subject, route and durable tables agree with the specs of this change.

## 3. Contracts (ratatoskr-contracts)

- [ ] 3.1 RED: add `crates/notes-contracts/tests/write_request.rs` with `two_operations_are_refused`, `origin_has_two_forms`, `update_requires_base_hash`, `custom_resolution_requires_content`, `paths_stay_inside_the_vault` and `content_is_a_blob_ref`, over the invalid fixtures `two-operations.json`, `empty-site-origin.json`, `unknown-origin.json`, `update-without-base-hash.json`, `custom-resolution-without-content.json`, `parent-segment.json`, `absolute-path.json`, `config-folder.json` and `inline-content.json`, and one valid fixture per operation kind. Each test asserts that the Rust deserializer and the generated JSON Schema both refuse its fixtures. Confirm that the file fails to find `notes/write-request.v1`, and not for a typo.
- [ ] 3.2 GREEN: add `schemas/json-schema/notes/write-request.v1.schema.json` and the Rust type with `origin`, the seven operations and content as a notes-owned `BlobRef`. Verify that 3.1 passes and that the generated TypeScript matches.
- [ ] 3.3 RED: add `crates/notes-contracts/tests/conflict.rs::attachment_conflict_with_proposal_is_refused` and `text_conflict_round_trips`, the first asserting that a conflict event for a binary media type that carries a merge proposal is refused. Confirm that they fail because `notes/conflict.v1` does not exist.
- [ ] 3.4 GREEN: add `notes/conflict.v1` (raised and resolved, hashes only, with `origin`). Verify 3.3.
- [ ] 3.5 RED: add `tools/contractsc/tests/live_message_types.rs::notes_write_request_has_one_producer`, asserting that `notes.file.write_requested.v1` is registered with exactly the producer `ratatoskr-platform` and the consumer `ratatoskr-notes`, and that `notes.conflict.raised.v1` and `notes.conflict.resolved.v1` name the producer `ratatoskr-notes` and the consumer `ratatoskr-platform`. Confirm that it fails because the types are not registered.
- [ ] 3.6 GREEN: register the three types in `contracts.toml`. Verify 3.5, and document the types in the contracts `README.md` subject table.

## 4. Queue, base check, content and authority (ratatoskr-notes)

- [ ] 4.1 RED: add `services/notes/tests/bus_durables.rs::verifies_write_request_durable`, asserting that the consumer looks up `ratatoskr_notes_write_requests` with the filter `cmd.notes.file.write_requested.v1` and an ack wait of 30 s and refuses readiness on any other value. Confirm that it fails because no write consumer exists.
- [ ] 4.2 GREEN: add the consumer with the durable name and filter as string literals and the custom inbox prefix of OBS-023. Verify 4.1.
- [ ] 4.3 RED: add `services/notes/tests/write_queue.rs::chained_edits_apply_in_order`: send `update` A on H0 and `update` B on A's expected hash before A is acknowledged; assert that B is not delivered before A's acknowledgement and that both end `succeeded`. Confirm that it fails.
- [ ] 4.4 GREEN: implement the per-file queue in `schema.sql` (edited in place) and the head-of-queue scheduler. Verify 4.3.
- [ ] 4.5 RED: add `services/notes/tests/write_base_hash.rs` with `stale_base_makes_a_conflict` (current revision unchanged, no `file.changed`, outcome `conflict`) and `case_folded_create_collision` (exactly one of `Ideas/Plan.md` and `ideas/plan.md` is delivered). Confirm that both fail.
- [ ] 4.6 GREEN: implement the base check and the case-folded NFC create check at the head of the queue. Verify 4.5.
- [ ] 4.7 RED: add `services/notes/tests/write_pending.rs` with `refused_delivery_publishes_nothing`, `acknowledged_write_publishes_once` and `device_base_mismatch_raises_conflict`, against a fake channel. Confirm that the first fails because the revision becomes current before delivery.
- [ ] 4.8 GREEN: keep the write's bytes as a blob named by the pending write, and make the revision current and publish `evt.notes.file.changed.v1` only on the acknowledgement. Verify 4.7.
- [ ] 4.9 RED: add `services/notes/tests/write_content.rs` with `missing_blob_fails_the_write`, `uploaded_blob_is_not_a_revision`, `session_cannot_send_change_batches` and `foreign_session_upload_is_not_found`. Confirm that the first fails because notes refuses a session claim on the blob route.
- [ ] 4.10 GREEN: accept owner-session uploads on the blob route, check the `BlobRef` of a write, and refuse a change batch from a session with `notes.channel_mismatch`. Verify 4.9.
- [ ] 4.11 RED: add `services/notes/tests/write_idempotency.rs` with `retry_returns_same_revision` and `reused_key_with_other_content_is_invalid`. Confirm that both fail.
- [ ] 4.12 GREEN: store the idempotency record per connection and key. Verify 4.11.
- [ ] 4.13 RED: add `services/notes/tests/write_authority.rs` with `foreign_connection_is_not_found` and `write_mode_off_is_refused`, asserting the codes `notes.connection.not_found` and `notes.write.disabled` and that no revision changes. Confirm that they fail.
- [ ] 4.14 GREEN: check the tenant and the write mode on consumption. Verify 4.13.
- [ ] 4.15 RED: add `services/notes/tests/write_operation.rs` with `write_reports_to_success` (`running` with stages `queued` then `delivering`, then `succeeded` with the revision hash) and `conflict_fails_with_its_id`. Confirm that they fail.
- [ ] 4.16 GREEN: report through `evt.platform.operation.reported.v1`, and serve `GET /v1/notes/conflicts/{conflict_id}`. Verify 4.15, and document the stages and codes in `ratatoskr-notes/README.md`.

## 5. Conflicts and merge (ratatoskr-notes)

- [ ] 5.1 RED: add `services/notes/tests/conflict_merge.rs` with `conflict_event_carries_hashes_only`, `conflict_repeats_the_origin`, `disjoint_edits_merge_cleanly` and `attachment_conflict_has_no_proposal`. Confirm that they fail because no conflict record exists.
- [ ] 5.2 GREEN: implement the conflict record, the diff3 proposal for Markdown and text, and `evt.notes.conflict.raised.v1`. Verify 5.1.
- [ ] 5.3 RED: add `conflict_merge.rs::resolution_races_vault_change`: resolve while a newer revision arrives; assert a second conflict and no overwrite. Confirm that it fails.
- [ ] 5.4 GREEN: implement `resolve_conflict` as a queued write with `evt.notes.conflict.resolved.v1` on acknowledgement. Verify 5.3, and document the resolution choices in `ratatoskr-notes/README.md`.

## 6. Write mode (ratatoskr-notes)

- [ ] 6.1 RED: add `services/notes/tests/write_mode.rs` with `turning_on_enables_writes`, `turning_off_fails_waiting_writes` and `foreign_toggle_is_not_found`. Confirm that they fail because the route does not exist.
- [ ] 6.2 GREEN: implement `PUT /v1/notes/connections/{id}/write-mode` in the notes domain API, off by default, reporting the operation `notes.connection.write_mode`. Verify 6.1.
- [ ] 6.3 RED: add `services/notes/tests/sync_mode.rs` with `write_mode_off_sets_pull_only` and `write_mode_on_sets_bidirectional`, against a fake `ob` that records its arguments. Confirm that they fail.
- [ ] 6.4 GREEN: set the Headless client mode and conflict strategy from the write mode. Verify 6.3.

## 7. Delivery and echo (ratatoskr-notes)

- [ ] 7.1 RED: add `services/notes/tests/echo.rs` with `own_write_is_acknowledged_once` and `different_ack_hash_becomes_current`, against a fake `sync` channel. Confirm that the first fails with two events.
- [ ] 7.2 GREEN: treat an inbound change with the path and hash of a pending write as its acknowledgement, and make the acknowledged bytes current with the warning `notes.write.transformed` when the hash differs. Verify 7.1.
- [ ] 7.3 RED: add `services/notes/tests/delivery_plugin.rs` with `offline_device_delivers_on_reconnect`, `queue_keeps_order` and `foreign_device_reads_nothing`. Confirm that they fail because no device queue exists.
- [ ] 7.4 GREEN: implement the ordered device queue, its cursor and the result endpoint. Verify 7.3, and document the queue endpoints in `ratatoskr-notes/README.md`.
- [ ] 7.5 RED: add `services/notes/tests/sync_write.rs::tree_change_before_write_conflicts`: change the working-tree file after the queue check and before the write; assert no write and one conflict. Confirm that it fails.
- [ ] 7.6 GREEN: implement the per-file lock, the tree hash check, the temporary file and the atomic rename. Verify 7.5.
- [ ] 7.7 RED: add `sync_write.rs::reader_never_sees_partial_file`: a reader thread hashes the file in a loop during 1 000 writes; assert that every hash is the old or the new one. Confirm that it fails against a direct write in the test's own fault mode.
- [ ] 7.8 GREEN: verify 7.7 with the atomic write from 7.6, and record the result in `ratatoskr-notes/DEVELOPMENT.md`.

## 8. Link rewrite (ratatoskr-notes)

- [ ] 8.1 Record the fixture corpus with `tools/record-link-fixtures.sh` on a Mac with the Obsidian app and CLI: every case that `notes-link-rewrite` lists, including `shortest-path-collision`, `code-block-link` and `alias-and-heading`, each with the Obsidian version, the vault settings and `SHA256SUMS`. No failing test first: generated fixtures. Verify that the script reproduces each fixture's checksum list.
- [ ] 8.2 RED: add `services/notes/tests/link_rewrite_golden.rs` with `every_fixture_matches`, `shortest_path_collision`, `code_block_link`, `alias_and_heading`, `corpus_covers_required_cases` and `fixtures_match_their_recording`. Confirm that every replay fails because no rewrite exists.
- [ ] 8.3 GREEN: implement link resolution and rewrite for wikilinks, embeds and Markdown links, outside code blocks. Verify that 8.2 passes for every fixture.
- [ ] 8.4 RED: add `services/notes/tests/link_rewrite_atomic.rs` with `stale_linked_file_blocks_rename` and `partial_application_fails_with_a_conflict`. Confirm that they fail.
- [ ] 8.5 GREEN: queue the rename and its rewrites as one write group at the head of every file queue it touches, and handle partial acknowledgement with `notes.write.partially_applied`. Verify 8.4, and document the fixture recording in `ratatoskr-notes/DEVELOPMENT.md`.

## 9. Notes integration check (ratatoskr-notes)

- [ ] 9.1 Run the command list of `ratatoskr-notes/DEVELOPMENT.md` on the branch. No failing test first: a check of groups 4–8. Verify that every command passes and record the output in the pull request.

## 10. Edge, operations and bus (ratatoskr-platform)

- [ ] 10.1 RED: add `crates/public-api/tests/notes_writes.rs` with `write_requires_idempotency_key`, `invalid_body_is_refused`, `write_command_carries_no_file_bytes` (a marker string in the uploaded note appears in neither the outbox row nor the published envelope) and `write_mode_route_is_control_class`. Confirm that they fail because the routes do not exist.
- [ ] 10.2 GREEN: add `POST /v1/notes/connections/{id}/writes` and `POST /v1/notes/conflicts/{id}/resolution` with the operation `notes.file.write` and `origin` `platform`, and proxy `PUT /v1/notes/connections/{id}/write-mode` with the operation `notes.connection.write_mode`, all in the class `control`. Verify 10.1.
- [ ] 10.3 RED: add `crates/public-api/tests/notes_routes.rs::session_upload_claim_names_the_session_kind`: a primary-session upload to `/v1/notes/connections/{id}/blobs` reaches a stub notes upstream with a minted claim naming the owner and the session kind and no device id. Confirm that it fails because Edge forwards the blob route only for a device.
- [ ] 10.4 GREEN: forward a primary-session upload on the blob route, in the class `transfer`, with a session-kind claim. Verify 10.3 and that `device_claim_names_the_device_kind` still passes.
- [ ] 10.5 RED: add `crates/operations/tests/report_authority.rs::notes_write_kinds_accept_only_notes_reports`: a report from `ratatoskr-extractor` for a `notes.file.write` or `notes.connection.write_mode` operation is rejected, and one from `ratatoskr-notes` is applied. Confirm that it fails because the kinds have no authority row.
- [ ] 10.6 GREEN: add the two authority rows with the lane `ratatoskr-notes` and pass the lane at both mint sites. Verify 10.5 and that `every_minted_operation_kind_has_an_authority_row` passes.
- [ ] 10.7 RED: add `crates/eventing/tests/stream_table.rs::notes_write_durables_are_provisioned`, asserting that `DOMAIN_CONSUMERS` declares 26 rows (25 after OBS-023, plus `ratatoskr_notes_write_requests` with `cmd.notes.file.write_requested.v1` and 30 s), and that Edge's own consumers create `platform_notes_conflict_projection` with `evt.notes.conflict.>` and 30 s. Confirm that it fails because the table has 25 rows and no conflict projection exists.
- [ ] 10.8 GREEN: add `ratatoskr_notes_write_requests` to `DOMAIN_CONSUMERS` in `crates/eventing/src/stream.rs` (25 → 26 rows), and create and consume `platform_notes_conflict_projection` in Edge, projecting conflicts onto the operation. Verify 10.7.
- [ ] 10.9 RED: add `crates/eventing/tests/nats_permissions.rs::notes_publishes_conflicts_and_no_command` against a real broker with the reviewed file. Confirm that it fails because the NOTES stanza does not allow `evt.notes.conflict.raised.v1`.
- [ ] 10.10 GREEN: add to the NOTES stanza of `deploy/nats/ratatoskr.conf` the permissions of `ratatoskr_notes_write_requests` and the two conflict subjects. Verify 10.9, then copy the stanza into `ratatoskr-notes/deploy/nats/identity.conf` on the notes branch, so that `every_service_fragment_equals_its_platform_stanza` stays green.

## 11. `plugin` channel (ratatoskr-obsidian-plugin)

- [ ] 11.1 RED: add `test/apply-operation.test.ts` with `base mismatch is reported, not applied`, `rename uses fileManager.renameFile` and `operations apply in queue order`, against a fake vault API. Confirm that they fail.
- [ ] 11.2 GREEN: implement the pull loop, the base check, the apply step and the result report. Verify 11.1, and document the write behaviour in the plugin `README.md`.

## 12. `cli` channel (ratatoskr-export-agent)

- [ ] 12.1 RED: add `Tests/AgentCoreTests/ObsidianCliApplyTests.swift` with `testRenameUsesObsidianRename`, `testDeleteNeverPermanent` and `testClosedObsidianLeavesQueue`, against a fake `obsidian` executable that records its arguments. Confirm that they fail.
- [ ] 12.2 GREEN: implement the queue reader and the CLI apply step. Verify 12.1, and document the requirement of Obsidian 1.12.7 or later in the agent `README.md`.

## 13. Editor and conflicts (ratatoskr-web)

- [ ] 13.1 RED: add `src/features/notes/conflict-view.test.tsx` (`offers accept_merge only with a proposal`) and `src/features/notes/editor.test.tsx` (`uploads before it writes and sends the loaded base hash`, `write-mode switch sends PUT write-mode`). Confirm that they fail because the views do not exist.
- [ ] 13.2 GREEN: implement the editor, the write-mode switch and the conflict view. Verify 13.1 and `npm run check`.

## 14. Integration (ratatoskr-workspace)

- [ ] 14.1 RED: add `harness/crates/workspace-core/tests/bus_acl.rs::notes_stanza_allows_its_write_durable_and_conflict_events`. In `harness/crates/workspace-core/tests/bus_durables.rs`, grow `DOMAIN` from 25 to 26 entries with `ratatoskr_notes_write_requests` (filter `cmd.notes.file.write_requested.v1`, owner `notes`) and `PLATFORM_ONLY` from 3 to 4 entries with `platform_notes_conflict_projection`. Run `bus_acl.rs` and `bus_durables.rs` against the current pins and confirm that `notes_stanza_allows_its_write_durable_and_conflict_events`, `the_service_table_length_equals_the_durables_the_harness_lists` (Platform declares 25 rows, the harness lists 26), `platform_names_every_durable_with_its_contract_filter` and `every_owner_hard_codes_its_durable_name_and_filter` fail, because the pinned Platform and notes hold neither the stanza lines nor the durables.
- [ ] 14.2 RED: add the integration profile scenario `notes-write-back`: write through a fake `sync` channel and a fake device; assert one revision and one `file.changed` per acknowledged write, none for a refused one, one conflict for a stale base, and a rewritten link after a rename. Run it against the current pins and confirm that it fails because the pinned notes has no write consumer.
- [ ] 14.3 Advance the pins to the merges of 1.1–1.6 with `./ws lock generate`. No failing test first: generated files. Verify with `./ws doctor`.
- [ ] 14.4 GREEN: run 14.1 and 14.2 against the advanced pins and verify that they pass, and that `cargo test -p workspace-core --test bus_durables --test bus_acl` is green.
- [ ] 14.5 Update `docs/NOTES_AND_SITES.md` from Proposed to Implemented for the write path, and add the two durables to `docs/DEPLOYMENT_TARGET.md` where it lists the bus. No test: documentation.

## Workflow follow-up

- Archive `add-notes-write-back` only after `xr-021-fleet-round-5` and then `add-notes-vault-connections` are archived, and every item of group 1 is closed.
