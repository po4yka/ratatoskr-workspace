#!/usr/bin/env bash
# shellcheck disable=SC2034
# F2 Knowledge ingestion through a PDF blob capture, read through Edge (Edge, extractor, Knowledge; R3-09, R3-14). Sourced by run.sh; defines the flow, runs nothing.
#
# Provenance: ported from the by-hand Knowledge smoke of Round 3 (.workspaces/XR-021/smoke/kp/run.sh, reported passed: the PDF capture and the ChatGPT archive were both searchable through Edge), plus the negatives, the outage leg and the size legs of the plan, which the by-hand run did not have. Run through run.sh as committed in Round 5: see README.md for the verdict.

FLOW_ID=f2
FLOW_TITLE="Knowledge ingestion: PDF blob capture and AI-archive fact, searched through Edge"
FLOW_BINARIES=("platform:ratatoskr-edge render-nats-config" "extractor:ratatoskr-extractor" "knowledge:ratatoskr-knowledge-service" "chatgpt:ratatoskr-chatgpt-archive" "claude:ratatoskr-claude-archive")
FLOW_PORTS="$INFRA_PORTS 8091 9081 9088 8096 9085 8097 9086 $FAKE_OPENROUTER_PORT"
FLOW_REPOS="platform extractor knowledge chatgpt claude"
FLOW_EVIDENCE="by-hand run in Round 3 (kp): ran, passed, with hop A and hop B searchable through Edge; the negatives, outage and size legs are new"
FLOW_HONESTY=(
  "seeded: two users and a Mini App session (fixtures/platform-seed.sql); real in F3"
  "faked: OpenRouter is a loopback fake (the documented BASE_URL seam), so summaries and keywords are not a live provider result; PDFs and the ChatGPT archive are synthetic"
  "deviation: the Knowledge recap is disabled for this flow (RATATOSKR__CHANNEL_RECAP__ENABLED=false); ingest runs in the shipped openrouter mode against the fake"
  "not exercised: the Telegram webhook that normally writes the blob (the blob is placed in the Telegram blob root layout by hand; F3 uses the real webhook)"
  "faked (R5-03): the credential-outage leg makes the OpenRouter fake answer 401 for 60 s, then 402 and 404 for 30 s each, through the control file RUN/fake-status, and a 400 for 25 s; the Knowledge outage leg revokes and restores the login of Knowledge's database role (ALTER ROLE ... NOLOGIN, pg_terminate_backend), a seeded fault, not a PostgreSQL failure"
  "NOT RUN: the same PDF fetched from a URL as well as received as a blob (R5-02): the extractor's URL lane refuses loopback and private addresses by design and the harness has no public page; the two-blob capture of the same digest (the first and the corrected capture) is the evidence of one document identity"
  "NOT RUN: the credential outage with a social-style fact in flight (no social service runs in F2); the PDF capture and the ChatGPT and Claude archives are in flight"
)

# Places a file in the Telegram blob root layout and prints "DIGEST LENGTH".
put_telegram_blob() {
  local file=$1 digest
  digest=$(sha256_file "$file")
  mkdir -p "$S/blobs/telegram/sha256/${digest:0:2}"
  cp "$file" "$S/blobs/telegram/sha256/${digest:0:2}/${digest:2}"
  printf '%s %s' "$digest" "$(wc -c <"$file" | tr -d ' ')"
}

# capture_blob NAME KEY OWNER DIGEST LENGTH MEDIA_TYPE: POST /v1/captures/blobs as the seeded Mini App session. Sets CAPTURE_STATUS (the HTTP status) and CAPTURE_OP (the operation id) in the caller's shell, so it is never run inside $( ).
capture_blob() {
  local name=$1 key=$2 owner=$3 digest=$4 length=$5 media=$6 body status
  body=$(jq -nc --arg o "$owner" --arg h "$digest" --argjson n "$length" --arg m "$media" '{blob:{owner_service:$o,digest:{algorithm:"sha256",hex:$h},media_type:$m,length_bytes:$n},origin:{chat_kind:"private",forwarded:false}}')
  status=$(call "$name" POST "$EDGE/v1/captures/blobs" "$MINI" "$body" "$key")
  CAPTURE_STATUS=$status
  CAPTURE_OP=$(jq -r '.operation_id // empty' "$EV/$name.resp.body")
}

op_codes() { jq -r '[.errors[]?.code, .warnings[]?.code] | map(select(. != null)) | join(",")' "$EV/op-$1.json" 2>/dev/null; }
search_count() { curl -s -H "Authorization: Bearer $MINI" "$EDGE/v1/library/search?q=$1" | jq '[.. | objects | select(has("title"))] | length'; }
knowledge_count() { curl -s "127.0.0.1:8091/internal/search?tenant=user:$1&q=$2" | jq '.results | length'; }

flow_run() {
  infra_fresh || { assert infra_up 'false' "PostgreSQL or NATS did not start"; return; }
  edge_up || { assert edge_started 'false' "Edge did not become ready"; return; }
  assert_s04_durables
  seed_principals
  local row repo role
  for row in "knowledge|ratatoskr_knowledge" "extractor|ratatoskr_extractor" "chatgpt|ratatoskr_chatgpt" "claude|ratatoskr_claude"; do
    IFS='|' read -r repo role <<<"$row"
    pg_role "$repo" "$role" || { assert "role_$role" 'false' "role.sql failed"; return; }
  done
  fake_start fake-openrouter fake_openrouter.py "$FAKE_OPENROUTER_PORT" "$S/logs/fake-openrouter.jsonl" "$S/run"
  mkdir -p "$S/blobs/knowledge" "$S/blobs/extractor" "$S/blobs/telegram" "$S/blobs/chatgpt" "$S/staging/chatgpt" "$S/blobs/claude"
  conf_knowledge false && conf_extractor && conf_chatgpt && conf_claude || return
  svc_start knowledge
  svc_start extractor
  svc_start chatgpt
  svc_start claude
  svc_wait_ready knowledge 90
  svc_wait_ready extractor 60
  svc_wait_ready chatgpt 60
  svc_wait_ready claude 60
  MINI=$(secret miniapp)
  local browser1
  browser1=$(secret browser1)

  info "step 1: surface"
  # Edge refreshes the capabilities every 15 s (R5-14 rule 4), so right after the services start they read stale; wait for Knowledge to be seen.
  untilt '[ "$(curl -s -H "Authorization: Bearer $MINI" "$EDGE/v1/capabilities" | jq "[.services[]? | select(.service==\"knowledge\" and (.stale | not))] | length")" = 1 ]' 90
  curl -s -H "Authorization: Bearer $MINI" "$EDGE/v1/capabilities" >"$EV/edge-capabilities.json"
  assert edge_reports_the_library_available '[ "$(jq "[.services[]? | select(.service==\"knowledge\" and (.stale | not))] | length" "$EV/edge-capabilities.json")" = 1 ]' "$(jq -c . "$EV/edge-capabilities.json" | cut -c1-300)"
  assert knowledge_search_not_on_operator_port '[ "$(code 127.0.0.1:9081/internal/search)" = 404 ]'
  assert knowledge_ready_not_on_api_port '[ "$(code 127.0.0.1:8091/ready)" = 404 ]'
  assert services_connect_as_their_own_roles '[ "$(q postgres "select count(distinct usename) from pg_stat_activity where usename in ('"'"'ratatoskr_edge'"'"','"'"'ratatoskr_knowledge'"'"','"'"'ratatoskr_extractor'"'"','"'"'ratatoskr_chatgpt'"'"')")" = 4 ]'

  info "step 2: the PDF capture, read through Edge"
  local pdf_dir=$R/extractor/crates/pdf/tests/fixtures digest length pdf_digest pdf_length status
  read -r pdf_digest pdf_length <<<"$(put_telegram_blob "$pdf_dir/text-two-pages.pdf")"
  capture_blob capture-doc smoke-doc-1 ratatoskr-telegram "$pdf_digest" "$pdf_length" application/pdf
  status=$CAPTURE_STATUS
  assert capture_accepted '[ "$status" = 202 ]' "http=$status op=$CAPTURE_OP"
  local first_op=$CAPTURE_OP
  assert capture_succeeded '[ "$(pollop "$first_op" "$MINI" 120 doc)" = succeeded ]'
  assert operation_tenant_is_the_seeded_user '[ "$(jq -r .tenant_id "$EV/op-doc.json")" = "user:$U1" ]'
  untilt '[ "$(q ratatoskr "select count(*) from knowledge.search_documents")" -ge 1 ]' 90
  assert document_searchable_through_edge '[ "$(search_count deterministic)" -ge 1 ]' "$(curl -s -H "Authorization: Bearer $MINI" "$EDGE/v1/library/search?q=deterministic" | jq -c . | cut -c1-300)"
  assert document_searchable_through_knowledge_api '[ "$(knowledge_count "$U1" deterministic)" -ge 1 ]'
  assert search_is_tenant_scoped '[ "$(knowledge_count "$U2" deterministic)" = 0 ]'
  assert edge_search_requires_a_credential '[ "$(code "$EDGE/v1/library/search?q=deterministic")" = 401 ]'
  untilt '[ "$(pending ratatoskr_knowledge_documents)" = 0 ]' 30
  assert documents_durable_drained '[ "$(pending ratatoskr_knowledge_documents)" = 0 ]'
  assert no_redelivery_without_a_fault '[ "$(metric 9081 knowledge_ingest_redeliveries_total)" = 0 ]' "Knowledge counts a delivery it retries in knowledge_ingest_redeliveries_total (R4-05), which stays zero while nothing is faulted"

  info "step 2 negatives"
  read -r digest length <<<"$(put_telegram_blob "$pdf_dir/no-text-layer.pdf")"
  capture_blob capture-notext smoke-notext-1 ratatoskr-telegram "$digest" "$length" application/pdf
  status=$CAPTURE_STATUS
  pollop "$CAPTURE_OP" "$MINI" 90 notext >/dev/null
  assert no_text_layer_fails_with_its_public_code '[ "$(jq -r .status "$EV/op-notext.json")" = failed ] && [[ "$(op_codes notext)" == *content.extraction.no_text_layer* ]]' "$(op_codes notext)"
  capture_blob capture-foreign smoke-foreign-1 ratatoskr-someone-else "$pdf_digest" "$pdf_length" application/pdf
  status=$CAPTURE_STATUS
  assert foreign_owner_service_is_403 '[ "$status" = 403 ]' "http=$status"
  capture_blob capture-replay smoke-doc-1 ratatoskr-telegram "$pdf_digest" "$pdf_length" application/pdf
  status=$CAPTURE_STATUS
  assert replay_of_the_idempotency_key_returns_the_same_operation '[ "$CAPTURE_OP" = "$first_op" ]' "http=$status op=$CAPTURE_OP expected=$first_op"
  capture_blob capture-wronglen smoke-wronglen-1 ratatoskr-telegram "$pdf_digest" "$((pdf_length + 7))" application/pdf
  status=$CAPTURE_STATUS
  pollop "$CAPTURE_OP" "$MINI" 60 wronglen >/dev/null
  assert wrong_length_fails '[ "$(jq -r .status "$EV/op-wronglen.json")" = failed ]' "$(op_codes wronglen)"
  assert wrong_length_is_logged_as_a_failed_blob_verification '[ "$(logcount "$S/logs/extractor.log" "peer blob verification failed")" -ge 1 ]' "the extractor logs peer blob verification failed for a declared length that does not match the blob"
  capture_blob capture-corrected smoke-corrected-1 ratatoskr-telegram "$pdf_digest" "$pdf_length" application/pdf
  status=$CAPTURE_STATUS
  assert corrected_capture_of_the_same_digest_succeeds '[ "$(pollop "$CAPTURE_OP" "$MINI" 90 corrected)" = succeeded ]'
  untilt '[ "$(q ratatoskr "select count(*) from knowledge.search_documents where tenant_ref = '"'"'user:$U1'"'"'")" -ge 1 ]' 60
  untilt '[ "$("$PY" -I "$NATIVE_ROOT/fixtures/natsprobe.py" messages "$S/nk/edge.nkey" ratatoskr_events evt.content.document.extracted.v1 | wc -l | tr -d " ")" -ge 2 ]' 30
  "$PY" -I "$NATIVE_ROOT/fixtures/natsprobe.py" messages "$S/nk/edge.nkey" ratatoskr_events evt.content.document.extracted.v1 >"$EV/document-extracted-events.jsonl"
  assert one_document_identity_for_two_captures_of_one_digest '[ "$(jq -s "length" "$EV/document-extracted-events.jsonl")" -ge 2 ] && [ "$(jq -s "map(.document_id) | unique | length" "$EV/document-extracted-events.jsonl")" = 1 ] && [ "$(q ratatoskr "select count(*) from knowledge.search_documents where search_vector @@ plainto_tsquery('"'"'english'"'"', '"'"'deterministic'"'"')")" = 1 ]' "R5-02: extracted events $(jq -s "length" "$EV/document-extracted-events.jsonl"), distinct document ids $(jq -s "map(.document_id) | unique | length" "$EV/document-extracted-events.jsonl"), search_documents rows for the text $(q ratatoskr "select count(*) from knowledge.search_documents where search_vector @@ plainto_tsquery('english', 'deterministic')")"
  capture_blob capture-png smoke-png-1 ratatoskr-telegram "$pdf_digest" "$pdf_length" image/png
  status=$CAPTURE_STATUS
  pollop "$CAPTURE_OP" "$MINI" 60 png >/dev/null
  assert image_media_type_fails_unsupported '[ "$(jq -r .status "$EV/op-png.json")" = failed ] && [[ "$(op_codes png)" == *content.extraction.unsupported_media* ]]' "$(op_codes png)"

  info "step 3: NATS outage for 30 seconds during an extraction"
  "$PY" -I "$NATIVE_ROOT/fixtures/pdfs.py" "$S/fx" || return
  read -r digest length <<<"$(put_telegram_blob "$S/fx/big-under.pdf")"
  local probes_bad=0
  capture_blob capture-outage smoke-outage-1 ratatoskr-telegram "$digest" "$length" application/pdf
  status=$CAPTURE_STATUS
  local outage_op=$CAPTURE_OP outage_i
  sleep 1
  nats_down
  for ((outage_i = 0; outage_i < 15; outage_i++)); do
    [[ "$(code 127.0.0.1:9081/ready)" == 200 ]] || probes_bad=$((probes_bad + 1))
    sleep 2
  done
  nats_restart
  # Knowledge's readiness follows the broker (services/knowledge/tests/ingest_outage.rs: broker_outage_flips_readiness_false_and_recovers); the first harness wrote the opposite and was wrong.
  assert knowledge_readiness_follows_the_broker_down '[ "$probes_bad" -ge 1 ]' "non-200 readiness probes while the broker was down: $probes_bad of 15"
  assert knowledge_is_ready_again_after_the_broker_returns 'waitready 127.0.0.1:9081/ready 90' "readiness recovered"
  assert outage_operation_terminates '[[ "$(pollop "$outage_op" "$MINI" 240 outage)" =~ ^(succeeded|partially_succeeded|failed)$ ]]' "$(jq -r .status "$EV/op-outage.json")"
  untilt '[ "$(q ratatoskr "select count(*) from extractor.outbox_events where published_at is null")" = 0 ]' 90
  assert extractor_outbox_published_none_dead_lettered '[ "$(q ratatoskr "select count(*) from extractor.outbox_events where published_at is null or dead_lettered_at is not null")" = 0 ]'

  info "step 4: documents around MAX_EVENT_BYTES"
  assert document_just_below_the_limit_is_searchable '[ "$(search_count underfixture)" -ge 1 ] || [ "$(knowledge_count "$U1" underfixture)" -ge 1 ]' "operation $(jq -r .status "$EV/op-outage.json")"
  read -r digest length <<<"$(put_telegram_blob "$S/fx/big-over.pdf")"
  capture_blob capture-over smoke-over-1 ratatoskr-telegram "$digest" "$length" application/pdf
  status=$CAPTURE_STATUS
  pollop "$CAPTURE_OP" "$MINI" 240 over >/dev/null
  assert document_above_the_limit_is_partially_succeeded '[ "$(jq -r .status "$EV/op-over.json")" = partially_succeeded ] && [[ "$(op_codes over)" == *content.document.not_ingested* ]]' "$(jq -r .status "$EV/op-over.json") $(op_codes over)"

  info "step 5: hop B, a ChatGPT archive through the real importer, indexed as text"
  "$PY" -I "$NATIVE_ROOT/fixtures/archives.py" "$S/fx" >/dev/null
  local code_value pair_body dev dev_id
  status=$(call pairing-code POST "$EDGE/v1/devices/pairing-codes" "$browser1" '{"expected_kind":"export_agent","label":"smoke"}')
  code_value=$(jq -r .code "$EV/pairing-code.resp.body")
  status=$(call pair POST "$EDGE/v1/devices/pair" "" "$(jq -nc --arg c "$code_value" '{code:$c,kind:"export_agent",display_name:"smoke export agent"}')")
  dev=$(jq -r .credential "$EV/pair.resp.body")
  assert device_paired '[ "$status" = 201 ] && [ -n "$dev" ] && [ "$dev" != null ]' "http=$status"
  upload_archive chatgpt "$S/fx/chatgpt-conversations-only.zip" "$dev"
  assert archive_import_terminal '[[ "$ARCHIVE_STATUS" =~ ^(succeeded|partially_succeeded)$ ]]' "$ARCHIVE_STATUS"
  untilt '[ "$(q ratatoskr "select count(*) from knowledge.search_documents")" -ge 3 ]' 90
  assert conversation_found_by_a_word_from_its_messages '[ "$(search_count marmot)" -ge 1 ] && [ "$(knowledge_count "$U1" marmot)" -ge 1 ]' "$(curl -s "127.0.0.1:8091/internal/search?tenant=user:$U1&q=marmot" | jq -c "[.results[]|{title,snippet}]" | cut -c1-300)"
  local scaffold
  for scaffold in message_id family conversation_id; do
    assert "scaffold_token_not_searchable_$scaffold" '[ "$(search_count "$scaffold")" = 0 ] && [ "$(knowledge_count "$U1" "$scaffold")" = 0 ]' "R3-09: ids and prompt scaffold are not indexed"
  done
  untilt '[ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]' 30
  assert ai_archive_durable_drained '[ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]'
  assert redelivery_counter_is_stated_and_the_durables_drained '[ "$(metric 9081 knowledge_ingest_redeliveries_total)" -ge 0 ] && [ "$(pending ratatoskr_knowledge_documents)" = 0 ] && [ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]' "redeliveries after the NATS outage leg: $(metric 9081 knowledge_ingest_redeliveries_total)"

  info "step 6 (R4): a Claude archive reaches Knowledge, and the AI-archive durable drains"
  upload_archive claude "$S/fx/claude-complete.zip" "$dev"
  assert claude_archive_import_terminal '[[ "$ARCHIVE_STATUS" =~ ^(succeeded|partially_succeeded)$ ]]' "$ARCHIVE_STATUS"
  untilt '[ "$(knowledge_count "$U1" basil)" -ge 1 ]' 120
  assert claude_conversation_found_by_a_word_from_its_messages '[ "$(search_count basil)" -ge 1 ] && [ "$(knowledge_count "$U1" basil)" -ge 1 ]' "$(curl -s "127.0.0.1:8091/internal/search?tenant=user:$U1&q=basil" | jq -c "[.results[]|{title,snippet}]" | cut -c1-300)"
  untilt '[ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]' 60
  assert claude_fact_drained_the_ai_archive_durable '[ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]'

  local unanalysable_at_start
  unanalysable_at_start=$(logcount "$S/logs/knowledge.log" unanalysable)
  info "step 7 (R5-03): large conversation facts of about 2 MiB and 7.85 MB reach Knowledge through the deployed ACL, on the 120 s durable"
  "$PY" -I "$NATIVE_ROOT/fixtures/big_archives.py" "$S/fx" >/dev/null
  local big provider word upload_result
  for big in "chatgpt|chatgpt-large-2mib|pangolin" "chatgpt|chatgpt-large-7p9mb|wombat" "claude|claude-large-2mib|ocelot" "claude|claude-large-7p9mb|lemming"; do
    IFS='|' read -r provider big word <<<"$big"
    upload_result=$(env RATATOSKR_SMOKE_DIR="$S" NATIVE_ROOT="$NATIVE_ROOT" EV="$EV" "$PY" -I "$NATIVE_ROOT/fixtures/upload_cli.py" "$provider" "$S/fx/$big.zip" "$dev" 16777216 | tail -1)
    assert "large_fact_${big}_import_succeeded" '[ "$(jq -r .status <<<"$upload_result")" = succeeded ]' "$upload_result"
    untilt '[ "$(knowledge_count "$U1" "$word")" -ge 1 ]' 180
    assert "large_fact_${big}_is_searchable" '[ "$(knowledge_count "$U1" "$word")" -ge 1 ] && [ "$(search_count "$word")" -ge 1 ]' "word $word: $(knowledge_count "$U1" "$word") hits"
  done
  assert large_facts_were_not_dropped_as_too_large '[ "$(grep -rl facts_too_large "$EV/ops" 2>/dev/null | wc -l | tr -d " ")" = 0 ] && [ "$(q ratatoskr "select count(*) from chatgpt_archive.outbox_events where undeliverable_at is not null")" = 0 ]' "no ai_archive.import.facts_too_large and no undeliverable outbox row"
  assert large_facts_were_not_termed_unanalysable '[ "$(logcount "$S/logs/knowledge.log" unanalysable)" = "$unanalysable_at_start" ]' "R5-03: the 2 MiB conversation was Termed unanalysable before the snapshot ceiling was raised"
  untilt '[ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]' 120
  assert ai_archive_durable_drained_after_the_large_facts '[ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]'

  info "step 8 (R5-03): the provider credential fails for a while (401 for 60 s, 402 and 404 for 30 s each), then recovers; a PDF and an archive are in flight"
  local redeliveries_before runs_before
  redeliveries_before=$(metric 9081 knowledge_ingest_redeliveries_total)
  printf '401 60\n402 30\n404 30\n' >"$S/run/fake-status"
  read -r digest length <<<"$(put_telegram_blob "$S/fx/text-small.pdf")"
  capture_blob capture-credential smoke-credential-1 ratatoskr-telegram "$digest" "$length" application/pdf
  status=$CAPTURE_STATUS
  local credential_op=$CAPTURE_OP
  upload_archive chatgpt "$S/fx/chatgpt-full.zip" "$dev"
  assert credential_outage_archive_import_terminal '[[ "$ARCHIVE_STATUS" =~ ^(succeeded|partially_succeeded)$ ]]' "$ARCHIVE_STATUS"
  assert credential_outage_capture_succeeded '[ "$(pollop "$credential_op" "$MINI" 120 credential)" = succeeded ]'
  # the schedule ends 120 s after the control file was written; Knowledge retries on its own backoff, so allow time after that
  untilt '[ "$(knowledge_count "$U1" chartreuse)" -ge 1 ] && [ "$(knowledge_count "$U1" quokka)" -ge 1 ]' 300
  assert credential_outage_document_and_archive_are_searchable_after_recovery '[ "$(knowledge_count "$U1" chartreuse)" -ge 1 ] && [ "$(knowledge_count "$U1" quokka)" -ge 1 ]' "chartreuse=$(knowledge_count "$U1" chartreuse) quokka=$(knowledge_count "$U1" quokka)"
  assert credential_outage_was_retried_not_termed '[ "$(metric 9081 knowledge_ingest_redeliveries_total)" -gt "$redeliveries_before" ] && [ "$(logcount "$S/logs/knowledge.log" unanalysable)" = "$unanalysable_at_start" ]' "redeliveries $redeliveries_before -> $(metric 9081 knowledge_ingest_redeliveries_total); R5-03: an operator-fixable provider failure is retried, never Termed"
  rm -f "$S/run/fake-status"
  untilt '[ "$(pending ratatoskr_knowledge_documents)" = 0 ] && [ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]' 120
  assert durables_drained_after_the_credential_outage '[ "$(pending ratatoskr_knowledge_documents)" = 0 ] && [ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]'

  info "step 8b (R4-05): Knowledge cannot reach its database for 90 seconds while a PDF capture and an archive import are in flight; more than five deliveries pass"
  local outage_redeliveries_before
  outage_redeliveries_before=$(metric 9081 knowledge_ingest_redeliveries_total)
  read -r digest length <<<"$(put_telegram_blob "$S/fx/text-outage.pdf")"
  q postgres "alter role ratatoskr_knowledge nologin" >/dev/null
  q postgres "select count(pg_terminate_backend(pid)) from pg_stat_activity where usename = 'ratatoskr_knowledge'" >/dev/null
  capture_blob capture-db-outage smoke-db-outage-1 ratatoskr-telegram "$digest" "$length" application/pdf
  status=$CAPTURE_STATUS
  local db_outage_op=$CAPTURE_OP
  upload_archive claude "$S/fx/claude-nofiles.zip" "$dev"
  sleep 90
  q postgres "alter role ratatoskr_knowledge login" >/dev/null
  assert db_outage_capture_succeeded '[ "$(pollop "$db_outage_op" "$MINI" 180 dboutage)" = succeeded ]'
  untilt '[ "$(knowledge_count "$U1" persimmon)" -ge 1 ] && [ "$(knowledge_count "$U1" thyme)" -ge 1 ]' 300
  assert db_outage_document_and_conversation_are_searchable_after_the_restore '[ "$(knowledge_count "$U1" persimmon)" -ge 1 ] && [ "$(knowledge_count "$U1" thyme)" -ge 1 ]' "persimmon=$(knowledge_count "$U1" persimmon) thyme=$(knowledge_count "$U1" thyme)"
  assert db_outage_deliveries_were_retried_more_than_five_times '[ "$(metric 9081 knowledge_ingest_redeliveries_total)" -ge "$((outage_redeliveries_before + 5))" ]' "redeliveries $outage_redeliveries_before -> $(metric 9081 knowledge_ingest_redeliveries_total) (delays 2, 4, 8, 16, 32 s)"
  untilt '[ "$(pending ratatoskr_knowledge_documents)" = 0 ] && [ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]' 120
  assert durables_drained_after_the_database_outage '[ "$(pending ratatoskr_knowledge_documents)" = 0 ] && [ "$(pending ratatoskr_knowledge_ai_archive)" = 0 ]'
  assert the_outage_did_not_term_anything '[ "$(logcount "$S/logs/knowledge.log" unanalysable)" = "$unanalysable_at_start" ]'

  info "step 9: a permanent provider refusal (400) is Termed at its first delivery, and a message that is not an envelope does not block the durable"
  local termed_before fake_calls_before
  termed_before=$(metric 9081 knowledge_ingest_redeliveries_total)
  fake_calls_before=$(wc -l <"$S/logs/fake-openrouter.jsonl" | tr -d " ")
  printf '400 25\n' >"$S/run/fake-status"
  read -r digest length <<<"$(put_telegram_blob "$S/fx/text-bad-request.pdf")"
  capture_blob capture-bad-request smoke-bad-request-1 ratatoskr-telegram "$digest" "$length" application/pdf
  status=$CAPTURE_STATUS
  pollop "$CAPTURE_OP" "$MINI" 120 badrequest >/dev/null
  sleep 30
  assert the_fake_was_asked_and_refused_with_400 '[ "$(wc -l <"$S/logs/fake-openrouter.jsonl" | tr -d " ")" -gt "$fake_calls_before" ]' "provider requests $fake_calls_before -> $(wc -l <"$S/logs/fake-openrouter.jsonl" | tr -d " ")"
  assert a_400_is_termed_at_its_first_delivery '[ "$(metric 9081 knowledge_ingest_redeliveries_total)" = "$termed_before" ] && [ "$(logcount "$S/logs/knowledge.log" unanalysable)" = "$((unanalysable_at_start + 1))" ]' "redeliveries stayed at $termed_before (a retried delivery would raise the counter) and exactly one delivery was rejected as unanalysable"
  rm -f "$S/run/fake-status"
  "$PY" -I "$NATIVE_ROOT/fixtures/natsprobe.py" publish "$S/nk/extractor.nkey" _INBOX_extractor evt.content.document.extracted.v1 '{"this":"is not an envelope"}'
  sleep 10
  assert a_non_envelope_message_does_not_block_the_documents_durable '[ "$(pending ratatoskr_knowledge_documents)" = 0 ]' "pending + ack-pending: $(pending ratatoskr_knowledge_documents)"
  assert the_non_envelope_message_was_termed_not_retried '[ "$(metric 9081 knowledge_ingest_redeliveries_total)" = "$termed_before" ]' "redeliveries stayed at $termed_before"
}
