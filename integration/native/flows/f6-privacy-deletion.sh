#!/usr/bin/env bash
# shellcheck disable=SC2034
# F6 Privacy deletion and tombstone delivery (the databases and blob roots F1 kept, the ChatGPT and Claude CLIs, Knowledge with the fake OpenRouter; R3-06, R3-08, R2-06, R2-07). Sourced by run.sh; defines the flow, runs nothing.
#
# Provenance: the ChatGPT deletion legs are ported from the by-hand privacy-deletion smoke of Round 2 (.workspaces/XR-021/smoke/f6/run.sh, reported passed with the Edge to receiver hop seeded by hand); the cumulative-series legs, Claude's chained deletion, the tombstone-resilience legs and the concurrency leg are new. The Claude CLI grammar (`privacy-delete plan --tenant T --request-key K --scope tenant|export|conversation [--target UUID]`, then `execute --tenant T --request-id ID --confirm`) was read from services/claude-archive/src/lifecycle_commands.rs; its output was not inspected, so Claude's legs assert database and stream effects, not stdout. Run through run.sh as committed: NO.

FLOW_ID=f6
FLOW_TITLE="Privacy deletion and tombstone delivery: cumulative exports, re-announce, Claude chain, tombstone resilience, concurrency"
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
)

kn() { curl -s "127.0.0.1:8091/internal/search?tenant=user:$1&q=$2" | jq '.results | length'; }
tomb_count() { python3 -I "$NATIVE_ROOT/fixtures/natsprobe.py" messages "$S/nk/edge.nkey" ratatoskr_events evt.ai_archive.subject.tombstoned.v1 | wc -l | tr -d ' '; }
blobfile() { printf '%s/blobs/chatgpt/sha256/%s/%s' "$S" "${1:0:2}" "${1:2}"; }
kn_tombstones() { q ratatoskr "select count(*) from knowledge.ai_archive_tombstones"; }
uuid4() { python3 -c 'import uuid;print(uuid.uuid4())'; }
cg() { python3 -I "$NATIVE_ROOT/lib/envrun.py" "$S/conf/chatgpt.env" "$S/bin/ratatoskr-chatgpt-archive" privacy-delete "$@"; }
cl() { python3 -I "$NATIVE_ROOT/lib/envrun.py" "$S/conf/claude.env" "$S/bin/ratatoskr-claude-archive" privacy-delete "$@"; }
kn_job() { python3 -I "$NATIVE_ROOT/lib/envrun.py" "$S/conf/knowledge.env" "$S/bin/ratatoskr-knowledge-service" "$@"; }

f6_chatgpt() {
  info "ChatGPT: delete the oldest of three cumulative exports"
  local sha1 a1 a2 e1 arc1 civet req seq
  sha1=$(sha256_file "$S/fx/chatgpt-series-1.zip")
  a1=$(q ratatoskr "select id from chatgpt_archive.accounts where external_ref='smoke-chatgpt-account-1'")
  a2=$(q ratatoskr "select id from chatgpt_archive.accounts where external_ref='smoke-chatgpt-account-2'")
  e1=$(q ratatoskr "select id from chatgpt_archive.exports where sha256_hex='$sha1' and account_id='$a1'")
  arc1=$(q ratatoskr "select ai_archive_id from chatgpt_archive.exports where id='$e1'")
  civet=$(q ratatoskr "select id from chatgpt_archive.conversations where account_id='$a1' and title like 'Civet%'")
  assert chatgpt_state_found '[ -n "$a1" ] && [ -n "$a2" ] && [ -n "$e1" ] && [ -n "$civet" ]' "A1=$a1 A2=$a2 export1=$e1 civet=$civet"
  [[ -n "$e1" ]] || return
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

  info "ChatGPT: conversation scope"
  req=$(uuid4)
  cg plan --tenant "$a1" --request "$req" --conversation "$civet" >"$EV/cg-plan2.json"
  cg execute --tenant "$a1" --request "$req" --confirm >"$EV/cg-exec2.json"
  assert chatgpt_conversation_deletion_completed '[ "$(jq -r .status "$EV/cg-exec2.json")" = completed ]'
  untilt '[ "$(kn "$U1" civet)" = 0 ]' 90
  assert deleted_conversation_is_no_longer_searchable '[ "$(kn "$U1" civet)" = 0 ] && [ "$(kn "$U1" bobcat)" -ge 1 ]'

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
  sha1=$(sha256_file "$S/fx/claude-series-1.zip")
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
  cl plan --tenant "$ca1" --request-key f6-claude-2 --scope conversation --target "$hyssop" >"$EV/cl-plan2.json"
  rid=$(q ratatoskr "select request_id from claude_archive.privacy_deletion_requests where request_key='f6-claude-2'")
  cl execute --tenant "$ca1" --request-id "$rid" --confirm >"$EV/cl-exec2.json"
  untilt '[ "$(kn "$U1" hyssop)" = 0 ]' 90
  assert claude_deleted_conversation_is_gone_from_knowledge '[ "$(kn "$U1" hyssop)" = 0 ] && [ "$(kn "$U1" garlic)" -ge 1 ]'
  cl plan --tenant "$ca2" --request-key f6-claude-3 --scope tenant >"$EV/cl-plan3.json"
  rid=$(q ratatoskr "select request_id from claude_archive.privacy_deletion_requests where request_key='f6-claude-3'")
  cl execute --tenant "$ca2" --request-id "$rid" --confirm >"$EV/cl-exec3.json"
  untilt '[ "$(kn "$U2" okapi)" = 0 ]' 90
  assert claude_tenant_deletion_clears_knowledge_and_isolates_tenant_1 '[ "$(kn "$U2" okapi)" = 0 ] && [ "$(kn "$U1" garlic)" -ge 1 ]'
}

f6_resilience() {
  info "tombstone resilience (R3-08): PostgreSQL stopped for 20 seconds while a tombstone is delivered"
  local archive source id before_failures
  archive=$(q ratatoskr "select archive_id from knowledge.ai_archive_object_inbox where tenant_ref='user:$U1' limit 1")
  source=$(q ratatoskr "select source_id from knowledge.source_analysis_heads where family='ai_archive' and tenant_ref='user:$U1' limit 1")
  assert resilience_subjects_found '[ -n "$archive" ] && [ -n "$source" ]' "archive=$archive subject=$source"
  [[ -n "$archive" && -n "$source" ]] || return
  before_failures=$(q ratatoskr "select count(*) from knowledge.ingest_failures")
  pg_down
  id=$(python3 -I "$NATIVE_ROOT/fixtures/natsprobe.py" tombstone "$S/nk/edge.nkey" "$S/nk/chatgpt.nkey" _INBOX_chatgpt ratatoskr-chatgpt "user:$U1" "$archive" "$source")
  sleep 20
  pg_start
  svc_wait_ready knowledge 90
  untilt '[ "$(q ratatoskr "select count(*) from knowledge.ai_archive_tombstones where event_id='"'"'$id'"'"'")" = 1 ]' 120
  assert tombstone_is_applied_after_the_restart '[ "$(q ratatoskr "select count(*) from knowledge.ai_archive_tombstones where event_id='"'"'$id'"'"'")" = 1 ]'
  assert no_ingest_failure_row_for_it '[ "$(q ratatoskr "select count(*) from knowledge.ingest_failures")" = "$before_failures" ]'
  info "a tombstone naming another tenant's subject is Termed at the first delivery"
  local foreign_before foreign_id
  foreign_before=$(rg -c "foreign_subject" "$S/logs/knowledge.log" || echo 0)
  foreign_id=$(python3 -I "$NATIVE_ROOT/fixtures/natsprobe.py" tombstone "$S/nk/edge.nkey" "$S/nk/chatgpt.nkey" _INBOX_chatgpt ratatoskr-chatgpt "user:$U2" "$archive" "$source")
  untilt '[ "$(rg -c "foreign_subject" "$S/logs/knowledge.log" || echo 0)" -gt "$foreign_before" ]' 60
  assert foreign_subject_logged_once_at_the_first_delivery '[ "$(rg -c "foreign_subject" "$S/logs/knowledge.log" || echo 0)" = "$((foreign_before + 1))" ]'
  assert foreign_tombstone_not_applied '[ "$(q ratatoskr "select count(*) from knowledge.ai_archive_tombstones where event_id='"'"'$foreign_id'"'"'")" = 0 ]'
  untilt '[ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]' 30
  assert ai_archive_durable_drained '[ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]'
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
  a1=$(q ratatoskr "select id from chatgpt_archive.accounts where external_ref='smoke-chatgpt-account-1'")
  sha3=$(sha256_file "$S/fx/chatgpt-series-3.zip")
  e3=$(q ratatoskr "select id from chatgpt_archive.exports where sha256_hex='$sha3' and account_id='$a1'")
  arc3=$(q ratatoskr "select ai_archive_id from chatgpt_archive.exports where id='$e3'" 2>/dev/null)
  if [[ -z "$e3" ]]; then
    info "NOT RUN: export 3 of the series is not present any more"
    return
  fi
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
  upload_archive chatgpt "$S/fx/chatgpt-series-3.zip" "$dev2" 2>/dev/null
  wait "$race1" "$race2"
  info "second user's import of the identical bytes ended: ${ARCHIVE_STATUS:-unknown}"
  local missing=0 digest
  while read -r digest; do
    [[ -z "$digest" ]] && continue
    [[ -f "$(blobfile "$digest")" ]] || missing=$((missing + 1))
  done < <(q ratatoskr "select sha256_hex from chatgpt_archive.exports")
  assert no_committed_export_references_a_missing_blob '[ "$missing" = 0 ]' "exports whose raw blob is missing: $missing"
}

flow_run() {
  infra_resume || { assert infra_resume 'false' "PostgreSQL or NATS did not resume the state of F1"; return; }
  svc_start edge
  svc_wait_ready edge 90 || { assert edge_started 'false' "Edge did not become ready"; return; }
  pg_role knowledge ratatoskr_knowledge || { assert role_knowledge 'false' "role.sql failed"; return; }
  mkdir -p "$S/blobs/knowledge"
  fake_start fake-openrouter fake_openrouter.py "$FAKE_OPENROUTER_PORT" "$S/logs/fake-openrouter.jsonl" "$S/run"
  conf_knowledge false || return
  svc_start knowledge
  svc_start chatgpt
  svc_start claude
  svc_wait_ready knowledge 90
  svc_wait_ready chatgpt 60
  svc_wait_ready claude 60
  assert importers_and_knowledge_ready '[ "$(code 127.0.0.1:9081/ready)" = 200 ] && [ "$(code 127.0.0.1:9085/health/ready)" = 200 ] && [ "$(code 127.0.0.1:9086/health/ready)" = 200 ]'
  untilt '[ "$(q ratatoskr "select count(*) from knowledge.ai_archive_object_inbox")" -ge 1 ]' 120
  assert knowledge_consumed_the_retained_facts '[ "$(q ratatoskr "select count(*) from knowledge.ai_archive_object_inbox")" -ge 1 ] && [ "$(q ratatoskr "select count(*) from knowledge.search_documents")" -ge 1 ]'
  f6_chatgpt
  f6_claude
  f6_resilience
  f6_concurrency
  f6_tenant_job
  assert no_ingest_failures_at_the_end '[ "$(q ratatoskr "select count(*) from knowledge.ingest_failures")" = 0 ]' "ingest_failures=$(q ratatoskr "select count(*) from knowledge.ingest_failures")"
}
