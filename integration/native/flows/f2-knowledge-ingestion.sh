#!/usr/bin/env bash
# shellcheck disable=SC2034
# F2 Knowledge ingestion through a PDF blob capture, read through Edge (Edge, extractor, Knowledge; R3-09, R3-14). Sourced by run.sh; defines the flow, runs nothing.
#
# Provenance: ported from the by-hand Knowledge smoke of Round 3 (.workspaces/XR-021/smoke/kp/run.sh, reported passed: the PDF capture and the ChatGPT archive were both searchable through Edge), plus the negatives, the outage leg and the size legs of the plan, which the by-hand run did not have. Run through run.sh as committed: NO.

FLOW_ID=f2
FLOW_TITLE="Knowledge ingestion: PDF blob capture and AI-archive fact, searched through Edge"
FLOW_BINARIES=("platform:ratatoskr-edge render-nats-config" "extractor:ratatoskr-extractor" "knowledge:ratatoskr-knowledge-service" "chatgpt:ratatoskr-chatgpt-archive")
FLOW_PORTS="$INFRA_PORTS 8091 9081 9088 8096 9085 $FAKE_OPENROUTER_PORT"
FLOW_REPOS="platform extractor knowledge chatgpt"
FLOW_EVIDENCE="by-hand run in Round 3 (kp): ran, passed, with hop A and hop B searchable through Edge; the negatives, outage and size legs are new"
FLOW_HONESTY=(
  "seeded: two users and a Mini App session (fixtures/platform-seed.sql); real in F3"
  "faked: OpenRouter is a loopback fake (the documented BASE_URL seam), so summaries and keywords are not a live provider result; PDFs and the ChatGPT archive are synthetic"
  "deviation: the Knowledge recap is disabled for this flow (RATATOSKR__CHANNEL_RECAP__ENABLED=false); ingest runs in the shipped openrouter mode against the fake"
  "not exercised: the Telegram webhook that normally writes the blob (the blob is placed in the Telegram blob root layout by hand; F3 uses the real webhook)"
)

# Places a file in the Telegram blob root layout and prints "DIGEST LENGTH".
put_telegram_blob() {
  local file=$1 digest
  digest=$(sha256_file "$file")
  mkdir -p "$S/blobs/telegram/sha256/${digest:0:2}"
  cp "$file" "$S/blobs/telegram/sha256/${digest:0:2}/${digest:2}"
  printf '%s %s' "$digest" "$(wc -c <"$file" | tr -d ' ')"
}

# capture NAME KEY OWNER DIGEST LENGTH MEDIA_TYPE: POST /v1/captures/blobs as the seeded Mini App session; prints the HTTP status. The operation id lands in $CAPTURE_OP.
capture_blob() {
  local name=$1 key=$2 owner=$3 digest=$4 length=$5 media=$6 body status
  body=$(jq -nc --arg o "$owner" --arg h "$digest" --argjson n "$length" --arg m "$media" '{blob:{owner_service:$o,digest:{algorithm:"sha256",hex:$h},media_type:$m,length_bytes:$n},origin:{chat_kind:"private",forwarded:false}}')
  status=$(call "$name" POST "$EDGE/v1/captures/blobs" "$MINI" "$body" "$key")
  CAPTURE_OP=$(jq -r '.operation_id // empty' "$EV/$name.resp.body")
  printf '%s' "$status"
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
  for row in "knowledge|ratatoskr_knowledge" "extractor|ratatoskr_extractor" "chatgpt|ratatoskr_chatgpt"; do
    IFS='|' read -r repo role <<<"$row"
    pg_role "$repo" "$role" || { assert "role_$role" 'false' "role.sql failed"; return; }
  done
  fake_start fake-openrouter fake_openrouter.py "$FAKE_OPENROUTER_PORT" "$S/logs/fake-openrouter.jsonl" "$S/run"
  mkdir -p "$S/blobs/knowledge" "$S/blobs/extractor" "$S/blobs/telegram" "$S/blobs/chatgpt" "$S/staging/chatgpt"
  conf_knowledge false && conf_extractor && conf_chatgpt || return
  svc_start knowledge
  svc_start extractor
  svc_start chatgpt
  svc_wait_ready knowledge 90
  svc_wait_ready extractor 60
  svc_wait_ready chatgpt 60
  MINI=$(secret miniapp)
  local browser1
  browser1=$(secret browser1)

  info "step 1: surface"
  sleep 3
  curl -s -H "Authorization: Bearer $MINI" "$EDGE/v1/capabilities" >"$EV/edge-capabilities.json"
  assert edge_reports_the_library_available '[ "$(jq "[.services[]? | select(.service==\"knowledge\" and (.stale | not))] | length" "$EV/edge-capabilities.json")" = 1 ]' "$(jq -c . "$EV/edge-capabilities.json" | cut -c1-300)"
  assert knowledge_search_not_on_operator_port '[ "$(code 127.0.0.1:9081/internal/search)" = 404 ]'
  assert knowledge_ready_not_on_api_port '[ "$(code 127.0.0.1:8091/ready)" = 404 ]'
  assert services_connect_as_their_own_roles '[ "$(q postgres "select count(distinct usename) from pg_stat_activity where usename in ('"'"'ratatoskr_edge'"'"','"'"'ratatoskr_knowledge'"'"','"'"'ratatoskr_extractor'"'"','"'"'ratatoskr_chatgpt'"'"')")" = 4 ]'

  info "step 2: the PDF capture, read through Edge"
  local pdf_dir=$R/extractor/crates/pdf/tests/fixtures digest length pdf_digest pdf_length status
  read -r pdf_digest pdf_length <<<"$(put_telegram_blob "$pdf_dir/text-two-pages.pdf")"
  status=$(capture_blob capture-doc smoke-doc-1 ratatoskr-telegram "$pdf_digest" "$pdf_length" application/pdf)
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
  assert no_ingest_failures '[ "$(q ratatoskr "select count(*) from knowledge.ingest_failures")" = 0 ]'

  info "step 2 negatives"
  read -r digest length <<<"$(put_telegram_blob "$pdf_dir/no-text-layer.pdf")"
  status=$(capture_blob capture-notext smoke-notext-1 ratatoskr-telegram "$digest" "$length" application/pdf)
  pollop "$CAPTURE_OP" "$MINI" 90 notext >/dev/null
  assert no_text_layer_fails_with_its_public_code '[ "$(jq -r .status "$EV/op-notext.json")" = failed ] && [[ "$(op_codes notext)" == *content.extraction.no_text_layer* ]]' "$(op_codes notext)"
  status=$(capture_blob capture-foreign smoke-foreign-1 ratatoskr-someone-else "$pdf_digest" "$pdf_length" application/pdf)
  assert foreign_owner_service_is_403 '[ "$status" = 403 ]' "http=$status"
  status=$(capture_blob capture-replay smoke-doc-1 ratatoskr-telegram "$pdf_digest" "$pdf_length" application/pdf)
  assert replay_of_the_idempotency_key_returns_the_same_operation '[ "$CAPTURE_OP" = "$first_op" ]' "http=$status op=$CAPTURE_OP expected=$first_op"
  status=$(capture_blob capture-wronglen smoke-wronglen-1 ratatoskr-telegram "$pdf_digest" "$((pdf_length + 7))" application/pdf)
  pollop "$CAPTURE_OP" "$MINI" 60 wronglen >/dev/null
  assert wrong_length_fails '[ "$(jq -r .status "$EV/op-wronglen.json")" = failed ]' "$(op_codes wronglen)"
  assert wrong_length_is_a_blob_mismatch_operator_class '[ "$(rg -c "blob_mismatch" "$S/logs/extractor.log" || true)" -ge 1 ]'
  status=$(capture_blob capture-corrected smoke-corrected-1 ratatoskr-telegram "$pdf_digest" "$pdf_length" application/pdf)
  assert corrected_capture_of_the_same_digest_succeeds '[ "$(pollop "$CAPTURE_OP" "$MINI" 90 corrected)" = succeeded ]'
  status=$(capture_blob capture-png smoke-png-1 ratatoskr-telegram "$pdf_digest" "$pdf_length" image/png)
  pollop "$CAPTURE_OP" "$MINI" 60 png >/dev/null
  assert image_media_type_fails_unsupported '[ "$(jq -r .status "$EV/op-png.json")" = failed ] && [[ "$(op_codes png)" == *content.extraction.unsupported_media* ]]' "$(op_codes png)"

  info "step 3: NATS outage for 30 seconds during an extraction"
  python3 -I "$NATIVE_ROOT/fixtures/pdfs.py" "$S/fx" || return
  read -r digest length <<<"$(put_telegram_blob "$S/fx/big-under.pdf")"
  local probes_bad=0
  status=$(capture_blob capture-outage smoke-outage-1 ratatoskr-telegram "$digest" "$length" application/pdf)
  local outage_op=$CAPTURE_OP outage_i
  sleep 1
  nats_down
  for ((outage_i = 0; outage_i < 15; outage_i++)); do
    [[ "$(code 127.0.0.1:9081/ready)" == 200 ]] || probes_bad=$((probes_bad + 1))
    sleep 2
  done
  nats_restart
  assert knowledge_ready_stayed_200_during_the_outage '[ "$probes_bad" = 0 ]' "non-200 probes: $probes_bad of 15"
  assert outage_operation_terminates '[[ "$(pollop "$outage_op" "$MINI" 240 outage)" =~ ^(succeeded|partially_succeeded|failed)$ ]]' "$(jq -r .status "$EV/op-outage.json")"
  untilt '[ "$(q ratatoskr "select count(*) from extractor.outbox_events where published_at is null")" = 0 ]' 90
  assert extractor_outbox_published_none_dead_lettered '[ "$(q ratatoskr "select count(*) from extractor.outbox_events where published_at is null or dead_lettered_at is not null")" = 0 ]'

  info "step 4: documents around MAX_EVENT_BYTES"
  assert document_just_below_the_limit_is_searchable '[ "$(search_count underfixture)" -ge 1 ] || [ "$(knowledge_count "$U1" underfixture)" -ge 1 ]' "operation $(jq -r .status "$EV/op-outage.json")"
  read -r digest length <<<"$(put_telegram_blob "$S/fx/big-over.pdf")"
  status=$(capture_blob capture-over smoke-over-1 ratatoskr-telegram "$digest" "$length" application/pdf)
  pollop "$CAPTURE_OP" "$MINI" 240 over >/dev/null
  assert document_above_the_limit_is_partially_succeeded '[ "$(jq -r .status "$EV/op-over.json")" = partially_succeeded ] && [[ "$(op_codes over)" == *content.document.not_ingested* ]]' "$(jq -r .status "$EV/op-over.json") $(op_codes over)"

  info "step 5: hop B, a ChatGPT archive through the real importer, indexed as text"
  python3 -I "$NATIVE_ROOT/fixtures/archives.py" "$S/fx" >/dev/null
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
  assert no_ingest_failures_final '[ "$(q ratatoskr "select count(*) from knowledge.ingest_failures")" = 0 ]'
}
