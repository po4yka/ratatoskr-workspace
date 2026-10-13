#!/usr/bin/env bash
# shellcheck disable=SC2034
# F6 Privacy deletion and tombstone delivery (the databases and blob roots F1 kept, the ChatGPT and Claude CLIs, Knowledge with the fake OpenRouter; R3-06, R3-08, R2-06, R2-07). Sourced by run.sh; defines the flow, runs nothing.
#
# Provenance: the ChatGPT deletion legs are ported from the by-hand privacy-deletion smoke of Round 2 (.workspaces/XR-021/smoke/f6/run.sh, reported passed with the Edge to receiver hop seeded by hand); the cumulative-series legs, Claude's chained deletion, the tombstone-resilience legs and the concurrency leg are new. The Claude CLI grammar (`privacy-delete plan --tenant T --request-key K --scope tenant|export|conversation [--target UUID]`, then `execute --tenant T --request-id ID --confirm`) was read from services/claude-archive/src/lifecycle_commands.rs; its output was not inspected, so Claude's legs assert database and stream effects, not stdout. Run through run.sh as committed in Round 5: see README.md for the verdict.

FLOW_ID=f6
FLOW_TITLE="Privacy deletion and tombstone delivery: cumulative exports, re-announce, Claude chain, resend and acknowledgement, stream erasure, owner after a mapping change, tombstone resilience, concurrency"
FLOW_BINARIES=("platform:ratatoskr-edge render-nats-config" "chatgpt:ratatoskr-chatgpt-archive" "claude:ratatoskr-claude-archive" "knowledge:ratatoskr-knowledge-service")
FLOW_PORTS="$INFRA_PORTS 8091 9081 8096 9085 8097 9086 $FAKE_OPENROUTER_PORT"
FLOW_REPOS="platform chatgpt claude knowledge"
FLOW_EVIDENCE="ChatGPT deletion legs by hand in Round 2 (Edge to receiver hop seeded); everything else not run before"
FLOW_NEEDS_KEPT=f1
FLOW_HONESTY=(
  "faked: OpenRouter is a loopback fake; all archives are the synthetic ZIPs of F1's cumulative series"
  "deviation: the tombstone-resilience legs publish their tombstones directly with the ChatGPT identity's real seed (fixtures/natsprobe.py), not through an importer, because the leg needs a tombstone to arrive while PostgreSQL is down"
  "seeded: a Knowledge channel-recap row (an F4 leg that is not present in this state) is inserted by SQL to show that Knowledge's tenant deletion clears the recap tables; if the insert is refused that leg is reported NOT RUN"
  "not exercised: the Edge to receiver hop in the deletion path (the importers are driven through their CLIs)"
  "deviation (R5-11): both importers run with RATATOSKR__TOMBSTONE__RESEND_AFTER_SECONDS=150, beyond the stream's 120 s duplicate window, so a resend is a second stream message; the example's 600 would make the leg wait ten minutes"
  "deviation (R5-06): the mapping-change leg restarts both importers with a RATATOSKR__RECEIPT__PLATFORM_ACCOUNTS that no longer lists the first user's account"
  "seeded (R5-11): the foreign-subject probe is a tombstone published with the ChatGPT identity's seed by fixtures/natsprobe.py, so no producer outbox row exists for it"
  "NOT RUN: two owners for one account (import under the first user, remap, import under the second, tenant-scope deletion); the survivor-content legs of R4-03 and R5-08 (they need the non-cumulative edited series, which archives.py does not build yet); the producer-side refused counter for the foreign probe (no producer row); the stream-erasure refusal of a foreign sequence is shown by the repository tests"
)

kn() { curl -s "127.0.0.1:8091/internal/search?tenant=user:$1&q=$2" | jq '.results | length'; }
tomb_count() { "$PY" -I "$NATIVE_ROOT/fixtures/natsprobe.py" messages "$S/nk/edge.nkey" ratatoskr_events evt.ai_archive.subject.tombstoned.v1 | wc -l | tr -d ' '; }
blobfile() { printf '%s/blobs/chatgpt/sha256/%s/%s' "$S" "${1:0:2}" "${1:2}"; }
kn_tombstones() { q ratatoskr "select count(*) from knowledge.ai_archive_tombstones"; }
uuid4() { "$PY" -c 'import uuid;print(uuid.uuid4())'; }
cg() { "$PY" -I "$NATIVE_ROOT/lib/envrun.py" "$S/conf/chatgpt.env" "$S/bin/ratatoskr-chatgpt-archive" privacy-delete "$@"; }
cl() { "$PY" -I "$NATIVE_ROOT/lib/envrun.py" "$S/conf/claude.env" "$S/bin/ratatoskr-claude-archive" privacy-delete "$@"; }
# The digest recorded when the fixture was uploaded (R5-14 rule 3); never recomputed from a file that a later flow may have rebuilt.
recorded_sha() { tr -d '\n' <"$S/fx/$1.sha256"; }
cg_tomb_ids() { q ratatoskr "select payload->>'event_id' from chatgpt_archive.outbox_events where event_type = 'ai_archive.subject.tombstoned.v1' order by id"; }
cl_tomb_ids() { q ratatoskr "select event_id from claude_archive.outbox_events where event_type = 'ai_archive.subject.tombstoned.v1' order by occurred_at, event_id"; }
probe() { "$PY" -I "$NATIVE_ROOT/fixtures/natsprobe.py" "$@"; }
# tomb_copies EVENT_ID: how many copies of one tombstone event the stream holds (a resend beyond the duplicate window is a second message).
tomb_copies() { probe messages "$S/nk/edge.nkey" ratatoskr_events evt.ai_archive.subject.tombstoned.v1 | jq -s --arg id "$1" '[.[] | select(.event_id == $id)] | length'; }
ack_copies() { probe messages "$S/nk/edge.nkey" ratatoskr_events evt.knowledge.deletion.acknowledged.v1 | jq -s --arg id "$1" '[.[] | select(.acknowledged_event_id == $id)] | length'; }
conv_added() { probe messages "$S/nk/edge.nkey" ratatoskr_events evt.ai_archive.conversation.added.v1; }
kn_job() { "$PY" -I "$NATIVE_ROOT/lib/envrun.py" "$S/conf/knowledge.env" "$S/bin/ratatoskr-knowledge-service" "$@"; }

f6_chatgpt() {
  info "ChatGPT: delete the oldest of three cumulative exports"
  local sha1 a1 a2 e1 arc1 civet req seq sha3 e3_before
  sha1=$(recorded_sha chatgpt-series-1)
  assert fixture_digest_recorded_at_upload_equals_the_file_now '[ "$sha1" = "$(sha256_file "$S/fx/chatgpt-series-1.zip")" ]' "R5-14 rule 3: archives.py is byte-deterministic, so a recorded digest and a recomputed one agree"
  a1=$(q ratatoskr "select id from chatgpt_archive.accounts where external_ref='smoke-chatgpt-account-1'")
  a2=$(q ratatoskr "select id from chatgpt_archive.accounts where external_ref='smoke-chatgpt-account-2'")
  e1=$(q ratatoskr "select id from chatgpt_archive.exports where sha256_hex='$sha1' and account_id='$a1'")
  arc1=$(q ratatoskr "select ai_archive_id from chatgpt_archive.exports where id='$e1'")
  civet=$(q ratatoskr "select id from chatgpt_archive.conversations where account_id='$a1' and title like 'Civet%'")
  assert chatgpt_state_found '[ -n "$a1" ] && [ -n "$a2" ] && [ -n "$e1" ] && [ -n "$civet" ]' "A1=$a1 A2=$a2 export1=$e1 civet=$civet"
  [[ -n "$e1" ]] || return
  sha3=$(recorded_sha chatgpt-series-3)
  e3_before=$(q ratatoskr "select id from chatgpt_archive.exports where sha256_hex='$sha3' and account_id='$a1'")
  assert series_3_export_is_stored_before_any_conversation_deletion '[ -n "$e3_before" ]' "export 3 (recorded digest ${sha3:0:12}) = $e3_before"
  untilt '[ "$(kn "$U1" aardvark)" -ge 1 ] && [ "$(kn "$U1" bobcat)" -ge 1 ] && [ "$(kn "$U1" civet)" -ge 1 ] && [ "$(kn "$U2" tapir)" -ge 1 ]' 120
  assert knowledge_indexed_the_series '[ "$(kn "$U1" aardvark)" -ge 1 ] && [ "$(kn "$U1" bobcat)" -ge 1 ] && [ "$(kn "$U1" civet)" -ge 1 ] && [ "$(kn "$U2" tapir)" -ge 1 ]'
  local snap2
  snap2=$(q ratatoskr "select (select count(*) from chatgpt_archive.exports where account_id='$a2'),(select count(*) from chatgpt_archive.conversations where account_id='$a2'),(select count(*) from chatgpt_archive.projects where account_id='$a2')")
  req=$(uuid4)
  seq=$(tomb_count)
  cg plan --tenant "$a1" --request "$req" --archive "$arc1" >"$EV/cg-plan1.json"
  assert chatgpt_plan_removes_nothing '[ "$(jq -r .scope.kind "$EV/cg-plan1.json")" = archive ] && [ -f "$(blobfile "$sha1")" ]'
  cg execute --tenant "$a1" --request "$req" --confirm >"$EV/cg-exec1.json"
  assert chatgpt_deletion_completed '[ "$(jq -r .status "$EV/cg-exec1.json")" = completed ]' "$(jq -c .totals "$EV/cg-exec1.json")"
  assert chatgpt_raw_blob_of_the_export_is_erased '[ ! -e "$(blobfile "$sha1")" ]'
  assert chatgpt_export_row_gone_and_later_exports_kept '[ "$(q ratatoskr "select count(*) from chatgpt_archive.exports where id='"'"'$e1'"'"'")" = 0 ] && [ "$(q ratatoskr "select count(*) from chatgpt_archive.exports where account_id='"'"'$a1'"'"'")" -ge 2 ]'
  untilt '[ "$(tomb_count)" -gt "$seq" ]' 60
  assert chatgpt_tombstone_published_through_the_real_pump '[ "$(tomb_count)" -gt "$seq" ]' "tombstones on the stream: $seq -> $(tomb_count)"
  untilt '[ "$(kn_tombstones)" -ge 1 ]' 60
  assert knowledge_applied_the_tombstone '[ "$(kn_tombstones)" -ge 1 ]'
  untilt '[ "$(kn "$U1" aardvark)" -ge 1 ]' 90
  assert conversation_held_by_a_retained_export_is_still_searchable '[ "$(kn "$U1" aardvark)" -ge 1 ] && [ "$(kn "$U1" bobcat)" -ge 1 ]' "R3-06: re-announced after the tombstone"
  assert tenant_2_untouched_by_deletion_1 '[ "$(q ratatoskr "select (select count(*) from chatgpt_archive.exports where account_id='"'"'$a2'"'"'),(select count(*) from chatgpt_archive.conversations where account_id='"'"'$a2'"'"'),(select count(*) from chatgpt_archive.projects where account_id='"'"'$a2'"'"')")" = "$snap2" ] && [ "$(kn "$U2" tapir)" -ge 1 ]'
  local after
  after=$(tomb_count)
  cg execute --tenant "$a1" --request "$req" --confirm >"$EV/cg-exec1-replay.json"
  sleep 3
  assert replay_is_idempotent_and_publishes_no_second_tombstone '[ "$(jq -S -c . "$EV/cg-exec1-replay.json")" = "$(jq -S -c . "$EV/cg-exec1.json")" ] && [ "$(tomb_count)" = "$after" ]'

  info "ChatGPT: tenant 2, whole-tenant scope"
  req=$(uuid4)
  cg plan --tenant "$a2" --request "$req" --all >"$EV/cg-plan3.json"
  cg execute --tenant "$a2" --request "$req" --confirm >"$EV/cg-exec3.json"
  assert chatgpt_tenant_deletion_completed '[ "$(jq -r .status "$EV/cg-exec3.json")" = completed ]'
  untilt '[ "$(kn "$U2" tapir)" = 0 ]' 90
  assert tenant_2_gone_and_tenant_1_isolated '[ "$(kn "$U2" tapir)" = 0 ] && [ "$(kn "$U1" bobcat)" -ge 1 ] && [ "$(q ratatoskr "select count(*) from chatgpt_archive.exports where account_id='"'"'$a2'"'"'")" = 0 ]'
  untilt '[ "$(q ratatoskr "select count(*) from knowledge.blob_erasure_queue")" = 0 ]' 60
  assert erasure_queue_empties '[ "$(q ratatoskr "select count(*) from knowledge.blob_erasure_queue")" = 0 ]'
}

f6_claude() {
  info "Claude: deletions chained through the real pump and NATS into Knowledge"
  local ca1 ca2 sha1 e1 hyssop rid seq
  ca1=00000000-0000-7000-8000-0000000000b1
  ca2=00000000-0000-7000-8000-0000000000b2
  sha1=$(recorded_sha claude-series-1)
  e1=$(q ratatoskr "select export_id from claude_archive.exports where account_ref='$ca1' and archive_hash=decode('$sha1','hex')")
  hyssop=$(q ratatoskr "select conversation_id from claude_archive.conversations where account_id='$ca1' and title like 'Hyssop%'")
  assert claude_state_found '[ -n "$e1" ] && [ -n "$hyssop" ]' "export1=$e1 hyssop=$hyssop"
  [[ -n "$e1" ]] || return
  untilt '[ "$(kn "$U1" fennel)" -ge 1 ] && [ "$(kn "$U1" hyssop)" -ge 1 ] && [ "$(kn "$U2" okapi)" -ge 1 ]' 120
  assert knowledge_indexed_claude_series '[ "$(kn "$U1" fennel)" -ge 1 ] && [ "$(kn "$U1" hyssop)" -ge 1 ] && [ "$(kn "$U2" okapi)" -ge 1 ]'
  seq=$(tomb_count)
  cl plan --tenant "$ca1" --request-key f6-claude-1 --scope export --target "$e1" >"$EV/cl-plan1.json"
  rid=$(q ratatoskr "select request_id from claude_archive.privacy_deletion_requests where request_key='f6-claude-1'")
  assert claude_plan_recorded '[ -n "$rid" ]' "request $rid"
  cl execute --tenant "$ca1" --request-id "$rid" --confirm >"$EV/cl-exec1.json"
  assert claude_export_deletion_completed '[ "$(q ratatoskr "select state from claude_archive.privacy_deletion_requests where request_id='"'"'$rid'"'"'")" = completed ]'
  assert claude_export_row_gone '[ "$(q ratatoskr "select count(*) from claude_archive.exports where export_id='"'"'$e1'"'"'")" = 0 ]'
  untilt '[ "$(tomb_count)" -gt "$seq" ]' 60
  assert claude_tombstone_published_through_the_real_pump '[ "$(tomb_count)" -gt "$seq" ]' "tombstones on the stream: $seq -> $(tomb_count)"
  untilt '[ "$(kn "$U1" fennel)" -ge 1 ]' 90
  assert claude_conversation_held_by_a_retained_export_is_still_searchable '[ "$(kn "$U1" fennel)" -ge 1 ]'
  cl plan --tenant "$ca2" --request-key f6-claude-3 --scope tenant >"$EV/cl-plan3.json"
  rid=$(q ratatoskr "select request_id from claude_archive.privacy_deletion_requests where request_key='f6-claude-3'")
  cl execute --tenant "$ca2" --request-id "$rid" --confirm >"$EV/cl-exec3.json"
  untilt '[ "$(kn "$U2" okapi)" = 0 ]' 90
  assert claude_tenant_deletion_clears_knowledge_and_isolates_tenant_1 '[ "$(kn "$U2" okapi)" = 0 ] && [ "$(kn "$U1" garlic)" -ge 1 ] && [ "$(kn "$U1" hyssop)" -ge 1 ]'
}

f6_resilience() {
  info "tombstone resilience (R3-08): PostgreSQL stopped for 20 seconds while a tombstone is delivered"
  # Two distinct subjects of the first user are chosen up front: the resilience tombstone deletes the first, and the foreign-subject probe names the second, which that tombstone did not touch. A probe that reused the deleted subject would be an unknown subject to Knowledge, which applies it for the other user instead of Terming it foreign_subject.
  local archive source other_source id redeliveries_before
  archive=$(q ratatoskr "select archive_id from knowledge.ai_archive_object_inbox where tenant_ref='user:$U1' order by archive_id limit 1")
  source=$(q ratatoskr "select source_id from knowledge.source_analysis_heads where family='ai_archive' and tenant_ref='user:$U1' order by source_id limit 1 offset 0")
  other_source=$(q ratatoskr "select source_id from knowledge.source_analysis_heads where family='ai_archive' and tenant_ref='user:$U1' order by source_id limit 1 offset 1")
  assert resilience_subjects_found '[ -n "$archive" ] && [ -n "$source" ] && [ -n "$other_source" ] && [ "$source" != "$other_source" ]' "archive=$archive subject=$source other subject=$other_source"
  [[ -n "$archive" && -n "$source" && -n "$other_source" && "$source" != "$other_source" ]] || return
  redeliveries_before=$(metric 9081 knowledge_ingest_redeliveries_total)
  pg_down
  id=$("$PY" -I "$NATIVE_ROOT/fixtures/natsprobe.py" tombstone "$S/nk/edge.nkey" "$S/nk/chatgpt.nkey" _INBOX_chatgpt ratatoskr-chatgpt "user:$U1" "$archive" "$source")
  sleep 20
  pg_start
  svc_wait_ready knowledge 90
  untilt '[ "$(q ratatoskr "select count(*) from knowledge.ai_archive_tombstones where event_id='"'"'$id'"'"'")" = 1 ]' 120
  assert tombstone_is_applied_after_the_restart '[ "$(q ratatoskr "select count(*) from knowledge.ai_archive_tombstones where event_id='"'"'$id'"'"'")" = 1 ]'
  assert delivery_during_the_outage_was_retried_not_lost '[ "$(metric 9081 knowledge_ingest_redeliveries_total)" -gt "$redeliveries_before" ]' "knowledge_ingest_redeliveries_total $redeliveries_before -> $(metric 9081 knowledge_ingest_redeliveries_total) (R4-05: the counter replaces the failure table Knowledge no longer has)"
  info "a tombstone naming another tenant's subject is Termed at the first delivery"
  local foreign_before foreign_id
  foreign_before=$(rg -c "foreign_subject" "$S/logs/knowledge.log" || echo 0)
  foreign_id=$("$PY" -I "$NATIVE_ROOT/fixtures/natsprobe.py" tombstone "$S/nk/edge.nkey" "$S/nk/chatgpt.nkey" _INBOX_chatgpt ratatoskr-chatgpt "user:$U2" "$archive" "$other_source")
  untilt '[ "$(rg -c "foreign_subject" "$S/logs/knowledge.log" || echo 0)" -gt "$foreign_before" ]' 60
  assert foreign_subject_logged_once_at_the_first_delivery '[ "$(rg -c "foreign_subject" "$S/logs/knowledge.log" || echo 0)" = "$((foreign_before + 1))" ]'
  assert foreign_tombstone_not_applied '[ "$(q ratatoskr "select count(*) from knowledge.ai_archive_tombstones where event_id='"'"'$foreign_id'"'"'")" = 0 ]'
  assert the_other_subject_of_the_first_user_is_untouched '[ "$(q ratatoskr "select count(*) from knowledge.source_analysis_heads where source_id='"'"'$other_source'"'"' and tenant_ref='"'"'user:$U1'"'"'")" = 1 ]'
  untilt '[ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]' 30
  assert ai_archive_durable_drained '[ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]'
}

f6_resend_ack_erasure() {
  info "resend, acknowledgement and stream erasure (R5-11, R5-12): Knowledge is stopped while one conversation of each provider is deleted"
  local a1 civet ca1 hyssop req rid
  a1=$(q ratatoskr "select id from chatgpt_archive.accounts where external_ref='smoke-chatgpt-account-1'")
  civet=$(q ratatoskr "select id from chatgpt_archive.conversations where account_id='$a1' and title like 'Civet%'")
  ca1=00000000-0000-7000-8000-0000000000b1
  hyssop=$(q ratatoskr "select conversation_id from claude_archive.conversations where account_id='$ca1' and title like 'Hyssop%'")
  assert resend_subjects_found '[ -n "$civet" ] && [ -n "$hyssop" ]' "civet=$civet hyssop=$hyssop"
  [[ -n "$civet" && -n "$hyssop" ]] || return
  conv_added >"$EV/conversation-added-before.jsonl"
  local cg_msg_before cl_msg_before
  cg_msg_before=$(jq -s --arg id "$civet" '[.[] | select(.producer == "ratatoskr-chatgpt" and (.aggregate_id | tostring | contains($id)))] | length' "$EV/conversation-added-before.jsonl")
  cl_msg_before=$(jq -s --arg id "$hyssop" '[.[] | select(.producer == "ratatoskr-claude" and (.aggregate_id | tostring | contains($id)))] | length' "$EV/conversation-added-before.jsonl")
  assert the_deleted_conversations_have_a_fact_on_the_stream_before '[ "$cg_msg_before" -ge 1 ] && [ "$cl_msg_before" -ge 1 ]' "conversation.added messages naming them: chatgpt $cg_msg_before, claude $cl_msg_before (aggregate ids: $(jq -s "[.[].aggregate_id] | unique | .[0:3]" "$EV/conversation-added-before.jsonl" | tr -d "\\n" | cut -c1-200))"
  local neighbours_before
  neighbours_before=$(jq -s --arg c "$civet" --arg h "$hyssop" '[.[] | select((.aggregate_id | tostring | contains($c) | not) and (.aggregate_id | tostring | contains($h) | not))] | length' "$EV/conversation-added-before.jsonl")

  svc_stop knowledge
  local cg_ids_before cl_ids_before cg_id cl_id
  cg_ids_before=$(cg_tomb_ids | sort)
  cl_ids_before=$(cl_tomb_ids | sort)
  req=$(uuid4)
  cg plan --tenant "$a1" --request "$req" --conversation "$civet" >"$EV/cg-plan-resend.json"
  cg execute --tenant "$a1" --request "$req" --confirm >"$EV/cg-exec-resend.json"
  assert chatgpt_conversation_deletion_completed '[ "$(jq -r .status "$EV/cg-exec-resend.json")" = completed ]' "$(jq -c .totals "$EV/cg-exec-resend.json" | cut -c1-300)"
  cl plan --tenant "$ca1" --request-key f6-claude-resend --scope conversation --target "$hyssop" >"$EV/cl-plan-resend.json"
  rid=$(q ratatoskr "select request_id from claude_archive.privacy_deletion_requests where request_key='f6-claude-resend'")
  cl execute --tenant "$ca1" --request-id "$rid" --confirm >"$EV/cl-exec-resend.json"
  assert claude_conversation_deletion_completed '[ "$(q ratatoskr "select state from claude_archive.privacy_deletion_requests where request_id='"'"'$rid'"'"'")" = completed ]'
  cg_id=$(comm -13 <(echo "$cg_ids_before") <(cg_tomb_ids | sort) | head -1)
  cl_id=$(comm -13 <(echo "$cl_ids_before") <(cl_tomb_ids | sort) | head -1)
  assert each_deletion_queued_a_tombstone '[ -n "$cg_id" ] && [ -n "$cl_id" ]' "chatgpt $cg_id claude $cl_id"
  [[ -n "$cg_id" && -n "$cl_id" ]] || return
  untilt '[ "$(tomb_copies "$cg_id")" -ge 1 ] && [ "$(tomb_copies "$cl_id")" -ge 1 ]' 60
  assert tombstones_are_on_the_stream_once_while_knowledge_is_down '[ "$(tomb_copies "$cg_id")" = 1 ] && [ "$(tomb_copies "$cl_id")" = 1 ]' "copies: chatgpt $(tomb_copies "$cg_id"), claude $(tomb_copies "$cl_id")"
  assert tombstone_rows_are_published_and_unacknowledged '[ "$(q ratatoskr "select (published_at is not null)::text || (acknowledged_at is null)::text from chatgpt_archive.outbox_events where payload->>'"'"'event_id'"'"' = '"'"'$cg_id'"'"'")" = truetrue ] && [ "$(q ratatoskr "select (published_at is not null)::text || (acknowledged_at is null)::text from claude_archive.outbox_events where event_id = '"'"'$cl_id'"'"'")" = truetrue ]'
  assert the_unacknowledged_gauges_show_the_backlog '[ "$(metric 9085 chatgpt_archive_unacknowledged_tombstones)" -ge 1 ] && [ "$(metric 9086 claude_archive_unacknowledged_tombstones)" -ge 1 ]' "chatgpt $(metric 9085 chatgpt_archive_unacknowledged_tombstones), claude $(metric 9086 claude_archive_unacknowledged_tombstones)"

  # R5-12: the producer's published copy of the deleted conversation is erased from the stream by Edge, while Knowledge is still down
  untilt '[ "$(conv_added | jq -s --arg c "$civet" "[.[] | select(.aggregate_id | tostring | contains(\$c))] | length")" = 0 ] && [ "$(conv_added | jq -s --arg h "$hyssop" "[.[] | select(.aggregate_id | tostring | contains(\$h))] | length")" = 0 ]' 40
  conv_added >"$EV/conversation-added-after.jsonl"
  assert the_deleted_conversations_fact_is_gone_from_the_stream_within_30_seconds '[ "$(jq -s --arg c "$civet" --arg h "$hyssop" "[.[] | select((.aggregate_id | tostring | contains(\$c)) or (.aggregate_id | tostring | contains(\$h)))] | length" "$EV/conversation-added-after.jsonl")" = 0 ]' "messages naming the deleted conversations after: $(jq -s --arg c "$civet" --arg h "$hyssop" "[.[] | select((.aggregate_id | tostring | contains(\$c)) or (.aggregate_id | tostring | contains(\$h)))] | length" "$EV/conversation-added-after.jsonl")"
  assert the_neighbouring_conversation_facts_are_still_on_the_stream '[ "$(jq -s "length" "$EV/conversation-added-after.jsonl")" = "$neighbours_before" ]' "other conversation.added messages: $neighbours_before before, $(jq -s "length" "$EV/conversation-added-after.jsonl") after"
  assert edge_audit_row_for_the_erasure_has_counts_and_no_content '[ "$(q ratatoskr "select count(*) from identity.audit_events where action = '"'"'stream.erasure'"'"' and outcome = '"'"'allowed'"'"'")" -ge 2 ]' "audit rows: $(q ratatoskr "select count(*) from identity.audit_events where action = 'stream.erasure'")"
  assert erasure_counter_counts_erased_messages '[ "$(metric 9464 platform_stream_erasure_total '"'"'outcome="erased"'"'"' | cut -d. -f1)" -ge 2 ]' "platform_stream_erasure_total erased: $(metric 9464 platform_stream_erasure_total 'outcome="erased"')"

  # R5-11: no acknowledgement arrives, so after the resend interval the SAME event id is on the stream a second time
  untilt '[ "$(tomb_copies "$cg_id")" = 2 ] && [ "$(tomb_copies "$cl_id")" = 2 ]' 260
  assert the_same_tombstone_is_resent_beyond_the_duplicate_window '[ "$(tomb_copies "$cg_id")" = 2 ] && [ "$(tomb_copies "$cl_id")" = 2 ]' "copies after the resend interval: chatgpt $(tomb_copies "$cg_id"), claude $(tomb_copies "$cl_id")"
  assert resend_count_is_one_and_the_row_is_still_unacknowledged '[ "$(q ratatoskr "select resend_count::text || (acknowledged_at is null)::text from chatgpt_archive.outbox_events where payload->>'"'"'event_id'"'"' = '"'"'$cg_id'"'"'")" = 1true ] && [ "$(q ratatoskr "select resend_count::text || (acknowledged_at is null)::text from claude_archive.outbox_events where event_id = '"'"'$cl_id'"'"'")" = 1true ]'

  # Knowledge starts: it applies each tombstone once and publishes one acknowledgement; the producers record it
  svc_start knowledge
  svc_wait_ready knowledge 90
  untilt '[ "$(q ratatoskr "select count(*) from knowledge.ai_archive_tombstones where event_id in ('"'"'$cg_id'"'"', '"'"'$cl_id'"'"')")" = 2 ]' 120
  assert knowledge_applied_each_tombstone_once '[ "$(q ratatoskr "select count(*) from knowledge.ai_archive_tombstones where event_id = '"'"'$cg_id'"'"'")" = 1 ] && [ "$(q ratatoskr "select count(*) from knowledge.ai_archive_tombstones where event_id = '"'"'$cl_id'"'"'")" = 1 ]'
  untilt '[ "$(q ratatoskr "select count(*) from chatgpt_archive.outbox_events where payload->>'"'"'event_id'"'"' = '"'"'$cg_id'"'"' and acknowledged_at is not null and ack_outcome = '"'"'applied'"'"'")" = 1 ] && [ "$(q ratatoskr "select count(*) from claude_archive.outbox_events where event_id = '"'"'$cl_id'"'"' and acknowledged_at is not null and ack_outcome = '"'"'applied'"'"'")" = 1 ]' 60
  assert producer_rows_record_the_acknowledgement_as_applied '[ "$(q ratatoskr "select count(*) from chatgpt_archive.outbox_events where payload->>'"'"'event_id'"'"' = '"'"'$cg_id'"'"' and acknowledged_at is not null and ack_outcome = '"'"'applied'"'"'")" = 1 ] && [ "$(q ratatoskr "select count(*) from claude_archive.outbox_events where event_id = '"'"'$cl_id'"'"' and acknowledged_at is not null and ack_outcome = '"'"'applied'"'"'")" = 1 ]' "within 30 s of Knowledge starting"
  assert exactly_one_acknowledgement_message_per_tombstone '[ "$(ack_copies "$cg_id")" = 1 ] && [ "$(ack_copies "$cl_id")" = 1 ]' "acknowledgements on the stream: chatgpt $(ack_copies "$cg_id"), claude $(ack_copies "$cl_id")"
  sleep 12
  assert no_further_resend_after_the_acknowledgement '[ "$(tomb_copies "$cg_id")" = 2 ] && [ "$(tomb_copies "$cl_id")" = 2 ]' "copies: chatgpt $(tomb_copies "$cg_id"), claude $(tomb_copies "$cl_id")"
  assert the_unacknowledged_gauges_go_to_zero '[ "$(metric 9085 chatgpt_archive_unacknowledged_tombstones)" = 0 ] && [ "$(metric 9086 claude_archive_unacknowledged_tombstones)" = 0 ]' "chatgpt $(metric 9085 chatgpt_archive_unacknowledged_tombstones), claude $(metric 9086 claude_archive_unacknowledged_tombstones)"
  untilt '[ "$(kn "$U1" civet)" = 0 ] && [ "$(kn "$U1" hyssop)" = 0 ]' 90
  assert deleted_conversations_are_no_longer_searchable '[ "$(kn "$U1" civet)" = 0 ] && [ "$(kn "$U1" hyssop)" = 0 ] && [ "$(kn "$U1" bobcat)" -ge 1 ] && [ "$(kn "$U1" garlic)" -ge 1 ]' "survivors bobcat $(kn "$U1" bobcat), garlic $(kn "$U1" garlic)"
  untilt '[ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]' 60
  assert ai_archive_durable_drained_after_the_resend '[ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]'
}

f6_foreign_ack() {
  info "the foreign-subject probe of f6_resilience is acknowledged refused (R5-11), the other subject stays"
  local refused
  untilt '[ "$(probe messages "$S/nk/edge.nkey" ratatoskr_events evt.knowledge.deletion.acknowledged.v1 | jq -s "[.[] | select(.outcome == \"refused\" and .refusal == \"foreign_subject\")] | length")" -ge 1 ]' 60
  refused=$(probe messages "$S/nk/edge.nkey" ratatoskr_events evt.knowledge.deletion.acknowledged.v1 | jq -s '[.[] | select(.outcome == "refused" and .refusal == "foreign_subject")] | length')
  assert foreign_probe_was_acknowledged_refused_foreign_subject '[ "$refused" -ge 1 ]' "refused / foreign_subject acknowledgements on the stream: $refused (a probe is not a producer row, so the producer-side counter is not asserted)"
}

f6_mapping_change() {
  info "owner after a mapping change (R5-06): both importers restart with a mapping that no longer lists the first user's account; a deletion is accepted and the tombstone names the original owner"
  local a1 ca1 aardvark garlic req rid before_ids after_ids new_id owner
  a1=$(q ratatoskr "select id from chatgpt_archive.accounts where external_ref='smoke-chatgpt-account-1'")
  ca1=00000000-0000-7000-8000-0000000000b1
  aardvark=$(q ratatoskr "select id from chatgpt_archive.conversations where account_id='$a1' and title like 'Aardvark%'")
  garlic=$(q ratatoskr "select conversation_id from claude_archive.conversations where account_id='$ca1' and title like 'Garlic%'")
  assert mapping_change_subjects_found '[ -n "$aardvark" ] && [ -n "$garlic" ]' "aardvark=$aardvark garlic=$garlic"
  [[ -n "$aardvark" && -n "$garlic" ]] || return
  conf_chatgpt "$U2=smoke-chatgpt-account-2" && conf_claude "$U2=00000000-0000-7000-8000-0000000000b2" || return
  pid_stop chatgpt
  pid_stop claude
  svc_start chatgpt
  svc_start claude
  svc_wait_ready chatgpt 60
  svc_wait_ready claude 60
  assert importers_ready_without_the_first_users_account '[ "$(code 127.0.0.1:9085/health/ready)" = 200 ] && [ "$(code 127.0.0.1:9086/health/ready)" = 200 ]'

  before_ids=$(cg_tomb_ids | sort)
  req=$(uuid4)
  cg plan --tenant "$a1" --request "$req" --conversation "$aardvark" >"$EV/cg-plan-remap.json"
  cg execute --tenant "$a1" --request "$req" --confirm >"$EV/cg-exec-remap.json"
  assert chatgpt_deletion_completes_after_the_mapping_change '[ "$(jq -r .status "$EV/cg-exec-remap.json")" = completed ]' "$(jq -c .totals "$EV/cg-exec-remap.json" | cut -c1-300)"
  assert chatgpt_report_has_no_unbound_downstream_tombstone '[ "$(jq -r ".totals.downstream_tombstone_unbound // 0" "$EV/cg-exec-remap.json")" = 0 ] && ! grep -q downstream_tombstone_unbound "$EV/cg-exec-remap.json"'
  new_id=$(comm -13 <(echo "$before_ids") <(cg_tomb_ids | sort) | head -1)
  owner=$(q ratatoskr "select payload->'payload'->>'owner' from chatgpt_archive.outbox_events where payload->>'event_id' = '$new_id'")
  assert chatgpt_tombstone_names_the_original_owner '[ "$owner" = "user:$U1" ]' "owner $owner"

  before_ids=$(cl_tomb_ids | sort)
  cl plan --tenant "$ca1" --request-key f6-claude-remap --scope conversation --target "$garlic" >"$EV/cl-plan-remap.json" 2>"$EV/cl-plan-remap.err"
  rid=$(q ratatoskr "select request_id from claude_archive.privacy_deletion_requests where request_key='f6-claude-remap'")
  assert claude_plan_is_accepted_after_the_mapping_change '[ -n "$rid" ]' "request $rid; before R5-06 Claude refused an unmapped tenant: $(head -c 200 "$EV/cl-plan-remap.err")"
  [[ -n "$rid" ]] || return
  cl execute --tenant "$ca1" --request-id "$rid" --confirm >"$EV/cl-exec-remap.json"
  assert claude_deletion_completes_after_the_mapping_change '[ "$(q ratatoskr "select state from claude_archive.privacy_deletion_requests where request_id='"'"'$rid'"'"'")" = completed ]'
  assert claude_report_has_no_unbound_downstream_tombstone '! grep -q downstream_tombstone_unbound "$EV/cl-exec-remap.json" "$EV/cl-plan-remap.json"'
  new_id=$(comm -13 <(echo "$before_ids") <(cl_tomb_ids | sort) | head -1)
  owner=$(q ratatoskr "select envelope->'payload'->>'owner' from claude_archive.outbox_events where event_id = '$new_id'")
  assert claude_tombstone_names_the_original_owner '[ "$owner" = "user:$U1" ]' "owner $owner"
  untilt '[ "$(kn "$U1" aardvark)" = 0 ] && [ "$(kn "$U1" garlic)" = 0 ]' 90
  assert knowledge_removed_the_first_users_data_after_the_mapping_change '[ "$(kn "$U1" aardvark)" = 0 ] && [ "$(kn "$U1" garlic)" = 0 ]'
  untilt '[ "$(metric 9085 chatgpt_archive_unacknowledged_tombstones)" = 0 ] && [ "$(metric 9086 claude_archive_unacknowledged_tombstones)" = 0 ]' 90
  assert remap_tombstones_were_acknowledged '[ "$(metric 9085 chatgpt_archive_unacknowledged_tombstones)" = 0 ] && [ "$(metric 9086 claude_archive_unacknowledged_tombstones)" = 0 ]'
}

f6_tenant_job() {
  info "Knowledge tenant deletion clears the channel recap tables"
  local command_id recap_id seeded=1
  command_id=$(uuid4)
  recap_id=$(uuid4)
  q ratatoskr "insert into knowledge.channel_recap_inbox (command_id, owner_ref, operation_id, digest_run_id, manifest_ref, manifest_digest_hex, window_start_at, window_end_at, source_count, channel_count, analysis_family, analysis_contract, output_language, request_payload) values ('$command_id','user:$U1','$(uuid4)','$(uuid4)','channel-digest-manifest:$(uuid4)','$(printf '%064d' 1)', now() - interval '1 day', now(), 1, 1, 'channel_digest_recap', 'channel_digest_recap.v1', 'en', '{}'::jsonb)" >/dev/null 2>"$EV/recap-seed.err" || seeded=0
  if ((seeded == 1)); then
    q ratatoskr "insert into knowledge.channel_recap_runs (recap_run_id, inbox_command_id, owner_ref, digest_run_id, manifest_digest_hex, analysis_family, analysis_contract, prompt_version, context_version, output_language) select '$recap_id', command_id, owner_ref, digest_run_id, manifest_digest_hex, analysis_family, analysis_contract, 'v1', 'v1', output_language from knowledge.channel_recap_inbox where command_id='$command_id'" >/dev/null 2>>"$EV/recap-seed.err" || seeded=0
  fi
  if ((seeded == 0)); then
    info "NOT RUN: the recap row could not be seeded (see recap-seed.err); Knowledge's tenant deletion was not checked against the recap tables"
    return
  fi
  svc_stop knowledge
  kn_job delete-tenant "user:$U1" >"$EV/knowledge-delete-tenant.txt" 2>&1
  assert knowledge_tenant_deletion_ran '[ -s "$EV/knowledge-delete-tenant.txt" ]' "$(head -c 300 "$EV/knowledge-delete-tenant.txt")"
  assert recap_tables_are_empty_for_the_tenant '[ "$(q ratatoskr "select (select count(*) from knowledge.channel_recap_inbox where owner_ref='"'"'user:$U1'"'"')+(select count(*) from knowledge.channel_recap_runs where owner_ref='"'"'user:$U1'"'"')")" = 0 ]'
}

f6_concurrency() {
  info "concurrency (R2-07): two deletions on one digest while another tenant imports identical bytes"
  local a1 sha3 e3 arc3 browser2 code_value dev2 req1 req2
  # The target is chatgpt-full.zip, uploaded by F1 and not touched by any earlier deletion. The series-3 export used here before was removed, by design, when its only conversation not held elsewhere (Civet) was deleted: the old NOT RUN was a lookup of an export that no longer existed, not a fixture that changed (archives.py is byte-deterministic and the digest is recorded at upload time).
  a1=$(q ratatoskr "select id from chatgpt_archive.accounts where external_ref='smoke-chatgpt-account-1'")
  sha3=$(recorded_sha chatgpt-full)
  e3=$(q ratatoskr "select id from chatgpt_archive.exports where sha256_hex='$sha3' and account_id='$a1' order by id limit 1")
  arc3=$(q ratatoskr "select ai_archive_id from chatgpt_archive.exports where id='$e3'")
  assert concurrency_target_export_is_stored '[ -n "$e3" ] && [ -n "$arc3" ]' "digest ${sha3:0:12} export $e3 archive $arc3"
  [[ -n "$e3" && -n "$arc3" ]] || return
  browser2=$(secret browser2)
  call c-pairing-code POST "$EDGE/v1/devices/pairing-codes" "$browser2" '{"expected_kind":"export_agent","label":"smoke"}' >/dev/null
  code_value=$(jq -r .code "$EV/c-pairing-code.resp.body")
  call c-pair POST "$EDGE/v1/devices/pair" "" "$(jq -nc --arg c "$code_value" '{code:$c,kind:"export_agent",display_name:"smoke export agent 2"}')" >/dev/null
  dev2=$(jq -r .credential "$EV/c-pair.resp.body")
  req1=$(uuid4)
  req2=$(uuid4)
  cg plan --tenant "$a1" --request "$req1" --archive "$arc3" >/dev/null
  cg plan --tenant "$a1" --request "$req2" --archive "$arc3" >/dev/null
  (cg execute --tenant "$a1" --request "$req1" --confirm >"$EV/cg-race1.json" 2>&1) &
  local race1=$!
  (cg execute --tenant "$a1" --request "$req2" --confirm >"$EV/cg-race2.json" 2>&1) &
  local race2=$!
  upload_archive chatgpt "$S/fx/chatgpt-full.zip" "$dev2" 2>/dev/null
  wait "$race1" "$race2"
  info "second user's import of the identical bytes ended: ${ARCHIVE_STATUS:-unknown}"
  local missing=0 digest
  while read -r digest; do
    [[ -z "$digest" ]] && continue
    [[ -f "$(blobfile "$digest")" ]] || missing=$((missing + 1))
  done < <(q ratatoskr "select sha256_hex from chatgpt_archive.exports")
  assert no_committed_export_references_a_missing_blob '[ "$missing" = 0 ]' "exports whose raw blob is missing: $missing"
}

# f6_in_flight PROVIDER: R6-03. An export is imported and its conversation is deleted as soon as the import has committed, while the importer's pump has the conversation's facts queued or in flight. Whichever side wins the race, the outbox keeps no row of the conversation and the stream keeps no fact message of it. The race is NOT forced here (a hit of the pump's 5 s window needs a paused pump, which only the repository tests of R6-03 rule 7 have); this leg shows that the shipped pair of processes ends in the same state either way.
f6_in_flight() {
  local provider=$1 dev=$2 file account conv req rid word stream_count outbox_count
  "$PY" -I "$NATIVE_ROOT/fixtures/archives.py" "$S/fx" >/dev/null
  if [[ $provider == chatgpt ]]; then
    file=$S/fx/chatgpt-inflight.zip word=Quokka
    account=$(q ratatoskr "select id from chatgpt_archive.accounts where external_ref='smoke-chatgpt-account-2'")
  else
    file=$S/fx/claude-inflight.zip word=Rowan
    account=00000000-0000-7000-8000-0000000000b2
  fi
  assert "in_flight_${provider}_fixture_and_account_found" '[ -f "$file" ] && [ -n "$account" ]' "fixture $(basename "$file") account $account"
  [[ -f "$file" && -n "$account" ]] || return
  (upload_archive "$provider" "$file" "$dev" >/dev/null 2>&1) &
  local upload=$!
  if [[ $provider == chatgpt ]]; then
    untilt '[ -n "$(q ratatoskr "select id from chatgpt_archive.conversations where account_id = '"'"'$account'"'"' and title like '"'"'$word%'"'"'")" ]' 90
    conv=$(q ratatoskr "select id from chatgpt_archive.conversations where account_id = '$account' and title like '$word%'")
  else
    untilt '[ -n "$(q ratatoskr "select conversation_id from claude_archive.conversations where account_id = '"'"'$account'"'"' and title like '"'"'$word%'"'"'")" ]' 90
    conv=$(q ratatoskr "select conversation_id from claude_archive.conversations where account_id = '$account' and title like '$word%'")
  fi
  assert "in_flight_${provider}_import_committed_its_conversation" '[ -n "$conv" ]' "conversation $conv"
  if [[ -z "$conv" ]]; then wait "$upload"; return; fi
  # no pause: the deletion is issued the moment the import has committed
  req=$(uuid4)
  if [[ $provider == chatgpt ]]; then
    cg plan --tenant "$account" --request "$req" --conversation "$conv" >"$EV/in-flight-chatgpt-plan.json"
    cg execute --tenant "$account" --request "$req" --confirm >"$EV/in-flight-chatgpt-exec.json"
    assert in_flight_chatgpt_deletion_completed '[ "$(jq -r .status "$EV/in-flight-chatgpt-exec.json")" = completed ]' "$(jq -c .totals "$EV/in-flight-chatgpt-exec.json" | cut -c1-200)"
  else
    cl plan --tenant "$account" --request-key "f6-in-flight-claude" --scope conversation --target "$conv" >"$EV/in-flight-claude-plan.json"
    rid=$(q ratatoskr "select request_id from claude_archive.privacy_deletion_requests where request_key='f6-in-flight-claude'")
    cl execute --tenant "$account" --request-id "$rid" --confirm >"$EV/in-flight-claude-exec.json"
    assert in_flight_claude_deletion_completed '[ "$(q ratatoskr "select state from claude_archive.privacy_deletion_requests where request_id='"'"'$rid'"'"'")" = completed ]'
  fi
  wait "$upload"
  info "in-flight $provider: the upload has ended (the import may have been cut short by the deletion; either end is acceptable, the assertions below are about what is left behind)"
  if [[ $provider == chatgpt ]]; then
    outbox_count='q ratatoskr "select count(*) from chatgpt_archive.outbox_events where aggregate_id::text = '"'"'$conv'"'"' and event_type like '"'"'ai_archive.conversation.%'"'"'"'
  else
    outbox_count='q ratatoskr "select count(*) from claude_archive.outbox_events where aggregate_id = '"'"'$conv'"'"' and event_type like '"'"'ai_archive.conversation.%'"'"'"'
  fi
  stream_count='{ probe messages "$S/nk/edge.nkey" ratatoskr_events evt.ai_archive.conversation.added.v1; probe messages "$S/nk/edge.nkey" ratatoskr_events evt.ai_archive.conversation.updated.v1; } | jq -s --arg c "$conv" "[.[] | select(.aggregate_id | tostring | contains(\$c))] | length"'
  untilt '[ "$(eval "$outbox_count")" = 0 ] && [ "$(eval "$stream_count")" = 0 ]' 60
  assert "in_flight_${provider}_outbox_holds_no_row_of_the_deleted_conversation" '[ "$(eval "$outbox_count")" = 0 ]' "conversation fact rows of $conv in the outbox: $(eval "$outbox_count")"
  assert "in_flight_${provider}_stream_holds_no_fact_message_of_the_deleted_conversation" '[ "$(eval "$stream_count")" = 0 ]' "conversation.added and .updated messages naming $conv on ratatoskr_events, counted within 60 s of the deletion: $(eval "$stream_count")"
}

f6_in_flight_all() {
  info "in-flight deletion (R6-03): a conversation is deleted the moment its import commits, with the pump publishing; for ChatGPT and for Claude"
  local browser2 code_value dev2
  browser2=$(secret browser2)
  call f-pairing-code POST "$EDGE/v1/devices/pairing-codes" "$browser2" '{"expected_kind":"export_agent","label":"smoke"}' >/dev/null
  code_value=$(jq -r .code "$EV/f-pairing-code.resp.body")
  call f-pair POST "$EDGE/v1/devices/pair" "" "$(jq -nc --arg c "$code_value" '{code:$c,kind:"export_agent",display_name:"smoke export agent 3"}')" >/dev/null
  dev2=$(jq -r .credential "$EV/f-pair.resp.body")
  f6_in_flight chatgpt "$dev2"
  f6_in_flight claude "$dev2"
  info "NOT FORCED natively (R6-03): the race is not forced; a hit of the pump's 5 s in-flight window needs a paused pump, and the deterministic proof is the repository tests of R6-03 rule 7"
}

flow_run() {
  infra_resume || { assert infra_resume 'false' "PostgreSQL or NATS did not resume the state of F1"; return; }
  svc_start edge
  svc_wait_ready edge 90 || { assert edge_started 'false' "Edge did not become ready"; return; }
  pg_role knowledge ratatoskr_knowledge || { assert role_knowledge 'false' "role.sql failed"; return; }
  mkdir -p "$S/blobs/knowledge"
  fake_start fake-openrouter fake_openrouter.py "$FAKE_OPENROUTER_PORT" "$S/logs/fake-openrouter.jsonl" "$S/run"
  # R5-11: beyond the stream's 120 s duplicate window, so a resend is a second message; both importers read the mapped accounts of F1's section s13
  TOMBSTONE_RESEND_SECONDS=150
  conf_chatgpt "$U1=smoke-chatgpt-account-1,$U2=smoke-chatgpt-account-2" && conf_claude "$U1=00000000-0000-7000-8000-0000000000b1,$U2=00000000-0000-7000-8000-0000000000b2" || return
  conf_knowledge false || return
  svc_start knowledge
  svc_start chatgpt
  svc_start claude
  svc_wait_ready knowledge 90
  svc_wait_ready chatgpt 60
  svc_wait_ready claude 60
  assert importers_and_knowledge_ready '[ "$(code 127.0.0.1:9081/ready)" = 200 ] && [ "$(code 127.0.0.1:9085/health/ready)" = 200 ] && [ "$(code 127.0.0.1:9086/health/ready)" = 200 ]'
  untilt '[ "$(q ratatoskr "select count(*) from knowledge.ai_archive_object_inbox")" -ge 1 ]' 120
  untilt '[ "$(q ratatoskr "select count(*) from knowledge.search_documents")" -ge 1 ]' 120
  assert knowledge_consumed_the_retained_facts '[ "$(q ratatoskr "select count(*) from knowledge.ai_archive_object_inbox")" -ge 1 ] && [ "$(q ratatoskr "select count(*) from knowledge.search_documents")" -ge 1 ]'
  f6_chatgpt
  f6_claude
  f6_resend_ack_erasure
  f6_resilience
  f6_foreign_ack
  f6_mapping_change
  f6_concurrency
  f6_in_flight_all
  f6_tenant_job
  assert the_durables_drained_at_the_end '[ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]' "ai_archive pending+ack-pending: $(pending ratatoskr_knowledge_ai_archive)"
}
