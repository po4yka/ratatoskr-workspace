#!/usr/bin/env bash
# shellcheck disable=SC2034
# F3 Telegram to Platform (the webhook and the dispatcher as shipped, a fake Bot API, plus F2's services; R3-12). Sourced by run.sh; defines the flow, runs nothing.
#
# Provenance: the assertion-key steps and the PDF capture follow the by-hand Telegram PDF smoke of Round 3 (.workspaces/XR-021/smoke/tgpdf), which used a scripted assertion issuer; this flow runs the real webhook and dispatcher binaries, which no earlier smoke did (the Telegram webhook and dispatcher were never run before). Run through run.sh as committed in Round 5: see README.md for the verdict.

FLOW_ID=f3
FLOW_TITLE="Telegram to Platform: assertion key, webhook update, session exchange, replies, dispatcher idle"
FLOW_BINARIES=("platform:ratatoskr-edge render-nats-config" "extractor:ratatoskr-extractor" "knowledge:ratatoskr-knowledge-service" "telegram:ratatoskr-telegram-webhook ratatoskr-telegram-dispatcher")
FLOW_PORTS="$INFRA_PORTS 8091 9081 9088 8182 9467 9468 $FAKE_OPENROUTER_PORT $FAKE_BOT_PORT $FAKE_TAP_PORT"
FLOW_REPOS="platform extractor knowledge telegram"
FLOW_EVIDENCE="not run before this harness (the webhook and the dispatcher were never run); the assertion-key command was exercised by hand in the Telegram PDF smoke"
FLOW_HONESTY=(
  "faked: the Telegram Bot API is a loopback fake (fixtures/fake_bot_api.py), so no message reached Telegram; OpenRouter is a loopback fake; the PDF is the extractor's own synthetic fixture"
  "deviation: RATATOSKR__PLATFORM__BASE_URL of the webhook and the dispatcher points at a recording tap (fixtures/tap_proxy.py) that forwards unchanged to Edge, so the request the webhook sends can be read"
  "not exercised: notifications. Nothing in the fleet publishes evt.platform.notification.raised.v1 (excluded: a product decision), so the dispatcher can only be shown ready and idle"
  "not exercised: Telegram MTProto, a real bot token, TLS through cloudflared"
  "faked (R5-10): the held-stream leg stops the extractor with the harness's pid file and starts it again; the tap passes the dispatcher's text/event-stream request through frame by frame (the first tap buffered a response until it ended, which would have held a progress stream back)"
  "seeded (R4-08): the session-loss leg revokes the sender's Platform sessions by SQL (revoked_at), because a session row cannot be deleted while the audit trail references it"
  "NOT RUN: a bare URL then the same URL forwarded (the extractor's URL lane refuses loopback addresses by design); a 409 from Platform (cannot be provoked once the key describes the body)"
)

KAT_SEED=9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60
KAT_PUBLIC='11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo='
OWNER_ID=900700601

# post_update ID JSON_MESSAGE_FIELDS: delivers a webhook update from the owner with the secret-token header.
post_update() {
  local update_id=$1 fields=$2 body
  body=$(jq -nc --argjson id "$update_id" --argjson owner "$OWNER_ID" --argjson fields "$fields" '{update_id:$id,message:({message_id:$id,from:{id:$owner,is_bot:false,first_name:"Synthetic"},date:1787904000,chat:{id:$owner,type:"private",first_name:"Synthetic"}} + $fields)}')
  curl -s -o "$EV/update-$update_id.out" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H "X-Telegram-Bot-Api-Secret-Token: $(cat "$S/keys/webhook-secret")" --data "$body" http://127.0.0.1:8182/webhook
}

bot_replies_after() { jq -rs --argjson seq "$1" '[.[] | select(.seq > $seq and (.method | ascii_downcase | IN("sendmessage","editmessagetext")))] | map(.request.text // "") | .[]' "$S/logs/fake-bot.jsonl"; }
# The highest sequence number a recording holds, or 0 when it does not exist yet (jq -s on a missing file prints 0 AND fails, so the file is tested first).
bot_seq() { if [[ -f "$S/logs/fake-bot.jsonl" ]]; then jq -s 'map(.seq) | max // 0' "$S/logs/fake-bot.jsonl"; else echo 0; fi; }

# bot_calls_after SEQ METHOD: how many Bot API calls of that method (any case) the fake recorded after SEQ. Calls are counted by method, never by lines of text: one message with two lines is one call.
bot_calls_after() { jq -rs --argjson seq "$1" --arg method "$2" '[.[] | select(.seq > $seq and ((.method | ascii_downcase) == $method))] | length' "$S/logs/fake-bot.jsonl"; }
# reply_sequence_after SEQ: one "method:first 80 characters of the text" line per reply call after SEQ, in call order.
reply_sequence_after() { jq -rs --argjson seq "$1" '[.[] | select(.seq > $seq and ((.method | ascii_downcase) | IN("sendmessage","editmessagetext")))] | map((.method | ascii_downcase) + ":" + ((.request.text // "") | gsub("\n"; " ") | .[0:80])) | .[]' "$S/logs/fake-bot.jsonl"; }
tap_seq() { if [[ -f "$S/logs/tap.jsonl" ]]; then jq -s 'map(.seq) | max // 0' "$S/logs/tap.jsonl"; else echo 0; fi; }
# capture_statuses TAP_SEQ: the status of every /v1/captures* call the tap recorded after TAP_SEQ, in order, space separated. A retry, a conflict or a refusal shows here; the reply the sender saw does not.
capture_statuses() { jq -rs --argjson seq "${1:-0}" '[.[] | select(.seq > $seq and (.path | startswith("/v1/captures"))) | .status | tostring] | join(" ")' "$S/logs/tap.jsonl"; }
terminal_operations() { q ratatoskr "select count(*) from operations.operations where status in ('succeeded','partially_succeeded','failed')"; }

flow_run() {
  infra_fresh || { assert infra_up 'false' "PostgreSQL or NATS did not start"; return; }
  info "step 1: the assertion key comes from the webhook's own command"
  local webhook=$S/bin/ratatoskr-telegram-webhook public derived
  public=$("$webhook" assertion-key generate "$S/keys/telegram-signing-key" 2>"$EV/assertion-key-generate.err")
  derived=$("$webhook" assertion-key public "$S/keys/telegram-signing-key" 2>/dev/null)
  assert assertion_key_generate_prints_the_public_key '[ -n "$public" ] && [ ${#public} = 44 ]' "length ${#public}"
  assert assertion_key_public_agrees_with_generate '[ "$public" = "$derived" ]'
  assert seed_file_mode_is_0600 '[ "$(stat -f %Lp "$S/keys/telegram-signing-key" 2>/dev/null || stat -c %a "$S/keys/telegram-signing-key")" = 600 ]'
  printf '%s\n' "$KAT_SEED" >"$S/keys/kat-seed"
  assert assertion_key_known_answer_rfc8032 '[ "$("$webhook" assertion-key public "$S/keys/kat-seed")" = "$KAT_PUBLIC" ]' "RFC 8032 section 7.1 test 1"
  rm -f "$S/keys/kat-seed"
  assert assertion_key_refuses_to_overwrite '! "$webhook" assertion-key generate "$S/keys/telegram-signing-key" >/dev/null 2>&1'

  edge_up "$public" || { assert edge_started 'false' "Edge did not become ready"; return; }
  assert_s04_durables
  local row repo role
  for row in "telegram|ratatoskr_telegram" "extractor|ratatoskr_extractor" "knowledge|ratatoskr_knowledge"; do
    IFS='|' read -r repo role <<<"$row"
    pg_role "$repo" "$role" || { assert "role_$role" 'false' "role.sql failed"; return; }
  done
  mkdir -p "$S/blobs/knowledge" "$S/blobs/extractor" "$S/blobs/telegram" "$S/fx/botfiles"
  cp "$R/extractor/crates/pdf/tests/fixtures/text-two-pages.pdf" "$S/fx/botfiles/doc1.pdf"
  # A second, different PDF: the webhook's idempotency key describes the body, so an update that repeats doc1 is a replay of the first operation and starts no new one.
  "$PY" -I "$NATIVE_ROOT/fixtures/pdfs.py" "$S/fx/pdfs" >/dev/null && cp "$S/fx/pdfs/text-outage.pdf" "$S/fx/botfiles/doc2.pdf"
  fake_start fake-openrouter fake_openrouter.py "$FAKE_OPENROUTER_PORT" "$S/logs/fake-openrouter.jsonl" "$S/run"
  fake_start fake-bot fake_bot_api.py "$FAKE_BOT_PORT" "$S/logs/fake-bot.jsonl" "$S/fx/botfiles"
  fake_start tap tap_proxy.py "$FAKE_TAP_PORT" 8080 "$S/logs/tap.jsonl"
  conf_knowledge false && conf_extractor && conf_telegram || return
  svc_start knowledge
  svc_start extractor
  svc_start webhook
  svc_start dispatcher
  svc_wait_ready knowledge 90
  svc_wait_ready extractor 60
  svc_wait_ready webhook 60
  svc_wait_ready dispatcher 60
  assert webhook_ready '[ "$(code 127.0.0.1:9467/health/ready)" = 200 ]'
  assert dispatcher_ready '[ "$(code 127.0.0.1:9468/health/ready)" = 200 ]'
  assert edge_reports_the_telegram_mini_app_available '[ "$(code -X POST -H "Content-Type: application/json" --data "{\"assertion\":\"x\"}" "$EDGE/v1/sessions/telegram")" != 404 ]' "a malformed assertion must be refused, not unrouted"

  info "step 2: a PDF from the owner"
  local seq tap0 status
  seq=$(bot_seq)
  tap0=$(tap_seq)
  status=$(post_update 1001 '{"document":{"file_id":"doc1.pdf","file_unique_id":"u1","file_name":"notes.pdf","mime_type":"application/pdf","file_size":1400}}')
  assert pdf_update_accepted_by_the_webhook '[ "$status" = 200 ]' "http=$status"
  untilt '[ "$(terminal_operations)" -ge 1 ]' 120
  local final
  final=$(q ratatoskr "select status from operations.operations order by accepted_at desc limit 1")
  assert pdf_capture_operation_succeeded '[ "$final" = succeeded ]' "$final"
  assert plain_capture_status_is_202 '[ "$(capture_statuses "$tap0")" = 202 ]' "tap statuses of /v1/captures*: $(capture_statuses "$tap0") (tap0=$tap0; tap log: $(wc -l <"$S/logs/tap.jsonl" 2>&1 | tr -d " ") lines; bot log: $(wc -l <"$S/logs/fake-bot.jsonl" 2>&1 | tr -d " ") lines, seq0=$seq)"
  assert blob_is_in_the_shared_telegram_root '[ "$(find "$S/blobs/telegram" -type f | wc -l | tr -d " ")" -ge 1 ]'
  assert session_exchange_returned_201 '[ "$(jq -rs "[.[] | select(.path==\"/v1/sessions/telegram\" and .status==201)] | length" "$S/logs/tap.jsonl")" -ge 1 ]' "a real exchange through the tap"
  assert identity_row_written_by_the_first_exchange '[ "$(q ratatoskr "select count(*) from telegram.identities where internal_user_id is not null")" -ge 1 ]'
  untilt '[ "$(( $(bot_calls_after "$seq" sendmessage) + $(bot_calls_after "$seq" editmessagetext) ))" -ge 2 ]' 60
  reply_sequence_after "$seq" >"$EV/replies-pdf.txt"
  assert acknowledgement_is_the_first_reply_and_a_sendmessage '[ "$(head -1 "$EV/replies-pdf.txt" | cut -d: -f1)" = sendmessage ]' "first reply: $(head -1 "$EV/replies-pdf.txt")"
  assert completion_is_a_later_edit_or_send_with_another_body '[ "$(sed -n 2p "$EV/replies-pdf.txt" | cut -d: -f1)" != "" ] && [ "$(sed -n 2p "$EV/replies-pdf.txt" | cut -d: -f2-)" != "$(sed -n 1p "$EV/replies-pdf.txt" | cut -d: -f2-)" ]' "replies in order: $(tr "\n" "|" <"$EV/replies-pdf.txt")"
  assert no_reply_is_a_refusal '[ "$(grep -c "Could not save" "$EV/replies-pdf.txt")" = 0 ]'

  info "an attachment that is not a PDF"
  seq=$(bot_seq)
  status=$(post_update 1002 '{"photo":[{"file_id":"p1","file_unique_id":"p1u","width":10,"height":10,"file_size":100}]}')
  untilt '[ "$(bot_calls_after "$seq" sendmessage)" -ge 1 ]' 60
  local unsupported_body='<b>Unsupported attachment</b>
Send a PDF document with a text layer; images, video, voice, and audio are not supported yet.'
  assert photo_update_gets_exactly_the_static_unsupported_body '[ "$(bot_replies_after "$seq" | head -c 4000)" = "$unsupported_body" ]' "$(bot_replies_after "$seq" | head -2 | cut -c1-120 | tr "\n" "|")"
  assert photo_update_creates_no_capture_call '[ "$(capture_statuses "$tap0")" = 202 ]' "tap statuses of /v1/captures* since the first PDF: $(capture_statuses "$tap0")"

  info "the same PDF forwarded is a second accepted operation, not a refusal (R4-08 plain then forwarded; RED against telegram 81aa9e2 expected: Platform answers 409 for the reused key)"
  local tap1 ops_before
  seq=$(bot_seq)
  tap1=$(tap_seq)
  ops_before=$(terminal_operations)
  status=$(post_update 1003 '{"forward_date":1787900000,"forward_origin":{"type":"user","date":1787900000,"sender_user":{"id":42,"is_bot":false,"first_name":"Someone"}},"document":{"file_id":"doc1.pdf","file_unique_id":"u1","file_name":"forwarded-secret-name.pdf","mime_type":"application/pdf","file_size":1400}}')
  assert forwarded_update_accepted_by_the_webhook '[ "$status" = 200 ]' "http=$status"
  untilt '[ "$(terminal_operations)" -ge $((ops_before + 1))  ]' 120
  jq -s --argjson seq "$tap1" '[.[] | select(.seq > $seq and .path=="/v1/captures/blobs")] | last' "$S/logs/tap.jsonl" >"$EV/forwarded-capture-request.json"
  assert forwarded_capture_status_is_202 '[ "$(capture_statuses "$tap1")" = 202 ]' "tap statuses of /v1/captures* for the forwarded PDF: $(capture_statuses "$tap1")"
  assert forwarded_request_origin_has_no_attachment_fact '[ "$(jq -r ".request.origin | keys | map(test(\"attach|file\")) | any" "$EV/forwarded-capture-request.json")" = false ] && [ "$(grep -c "forwarded-secret-name" "$EV/forwarded-capture-request.json")" = 0 ]' "origin keys: $(jq -c ".request.origin | keys" "$EV/forwarded-capture-request.json")"
  untilt '[ "$(bot_calls_after "$seq" sendmessage)" -ge 1 ]' 60
  reply_sequence_after "$seq" >"$EV/replies-forwarded.txt"
  assert forwarded_pdf_is_acknowledged_not_refused '[ "$(head -1 "$EV/replies-forwarded.txt" | cut -d: -f1)" = sendmessage ] && [ "$(grep -c "Could not save" "$EV/replies-forwarded.txt")" = 0 ]' "$(tr "\n" "|" <"$EV/replies-forwarded.txt")"
  assert both_operations_succeeded '[ "$(q ratatoskr "select count(*) from operations.operations where status = '"'"'succeeded'"'"'")" -ge 2 ]'
  untilt '[ "$(q ratatoskr "select count(*) from knowledge.search_documents")" -ge 1 ]' 90
  assert knowledge_holds_one_document_for_the_digest '[ "$(q ratatoskr "select count(*) from knowledge.search_documents")" = 1 ]' "rows: $(q ratatoskr "select count(*) from knowledge.search_documents")"
  info "NOT RUN: a bare URL then the same URL forwarded needs a page the extractor may fetch; its URL lane refuses loopback and private addresses by design (crates/url-routing) and the harness has no public page, so the plain-then-forwarded PDF above is the evidence"

  info "the same update delivered twice converges on one operation"
  local tap2
  ops_before=$(q ratatoskr "select count(*) from operations.operations")
  tap2=$(tap_seq)
  status=$(post_update 1001 '{"document":{"file_id":"doc1.pdf","file_unique_id":"u1","file_name":"notes.pdf","mime_type":"application/pdf","file_size":1400}}')
  sleep 5
  assert redelivered_update_is_acknowledged_to_telegram '[ "$status" = 200 ]' "http=$status"
  assert redelivered_update_creates_no_operation_and_no_capture_call '[ "$(q ratatoskr "select count(*) from operations.operations")" = "$ops_before" ] && [ -z "$(capture_statuses "$tap2")" ]' "operations $ops_before, capture calls: $(capture_statuses "$tap2")"

  info "session loss: the Platform sessions of the sender are revoked while the webhook runs (R4-08; a row cannot be deleted, the audit trail references it)"
  local deleted tap3 exchange
  q ratatoskr "select kind || ' ' || count(*) from identity.sessions group by kind order by kind" >"$EV/sessions-before-loss.txt" 2>&1
  deleted=$(q ratatoskr "update identity.sessions set revoked_at = now() where kind = 'telegram_mini_app' and revoked_at is null and user_id = (select internal_user_id from telegram.identities where telegram_user_id = $OWNER_ID) returning 1" 2>"$EV/session-delete.err" | wc -l | tr -d " ")
  assert session_rows_revoked '[ "$deleted" -ge 1 ]' "deleted $deleted rows; sessions before: $(tr "\n" "," <"$EV/sessions-before-loss.txt"); $(head -c 200 "$EV/session-delete.err")"
  seq=$(bot_seq)
  tap3=$(tap_seq)
  status=$(post_update 1006 '{"document":{"file_id":"doc1.pdf","file_unique_id":"u1","file_name":"notes.pdf","mime_type":"application/pdf","file_size":1400}}')
  untilt '[ -n "$(jq -rs --argjson seq "$tap3" "[.[] | select(.seq > \$seq and .path==\"/v1/captures/blobs\" and .status==202)] | first // empty" "$S/logs/tap.jsonl")" ]' 90
  exchange=$(jq -rs --argjson seq "$tap3" '[.[] | select(.seq > $seq and (.path | startswith("/v1/")) and (.path | startswith("/v1/operations") | not)) | "\(.path):\(.status)"] | join(" ")' "$S/logs/tap.jsonl")
  assert capture_after_session_loss_is_one_401_then_exchange_then_202 'grep -Eq "/v1/captures/blobs:401 /v1/sessions/telegram:201 /v1/captures/blobs:202" <<<"$exchange"' "tap: $exchange"
  sleep 3
  reply_sequence_after "$seq" >"$EV/replies-session-loss.txt"
  assert sender_sees_no_refusal_after_session_loss '[ "$(grep -Ec "Could not save|temporarily unavailable" "$EV/replies-session-loss.txt")" = 0 ]' "$(tr "\n" "|" <"$EV/replies-session-loss.txt")"
  info "NOT RUN here: a 409 from Platform cannot be provoked once the key describes the body, so the retry-then-unavailable path of a conflict is covered by the Telegram repository tests"

  info "a progress stream held over 25 seconds is followed over one connection, not one per 10 seconds (R5-10)"
  local tap4 events_requests ops_now
  svc_stop extractor
  seq=$(bot_seq)
  tap4=$(tap_seq)
  ops_now=$(terminal_operations)
  status=$(post_update 1010 '{"document":{"file_id":"doc2.pdf","file_unique_id":"u2","file_name":"held.pdf","mime_type":"application/pdf","file_size":1200}}')
  assert held_update_accepted_by_the_webhook '[ "$status" = 200 ]' "http=$status"
  sleep 32
  events_requests=$(jq -rs --argjson seq "$tap4" '[.[] | select(.seq > $seq and .method == "GET" and (.path | test("^/v1/operations/[^/]+/events")))] | length' "$S/logs/tap.jsonl")
  svc_start extractor
  svc_wait_ready extractor 60
  untilt '[ "$(terminal_operations)" -gt "$ops_now" ]' 120
  reply_sequence_after "$seq" >"$EV/replies-held.txt"
  assert at_most_two_follow_requests_over_a_32_second_hold '[ "$events_requests" -le 2 ]' "GET /v1/operations/{id}/events requests during the hold: $events_requests (before the fix: about one per 10 s)"
  assert at_least_one_follow_request_was_made '[ "$events_requests" -ge 1 ]' "the dispatcher followed the operation: $events_requests requests"
  assert dispatcher_log_has_no_follow_frame_failed '[ "$(logcount "$S/logs/dispatcher.log" follow_frame_failed)" = 0 ]'
  untilt 'reply_sequence_after "$seq" | grep -q "^editmessagetext:.*Completed"' 120
  reply_sequence_after "$seq" >"$EV/replies-held.txt"
  assert held_operation_completion_edit_arrives_after_the_extractor_starts 'grep -q "^editmessagetext:.*Completed" "$EV/replies-held.txt"' "$(tr "\n" "|" <"$EV/replies-held.txt")"

  info "Edge stopped before a PDF is sent"
  svc_stop edge
  seq=$(bot_seq)
  status=$(post_update 1004 '{"document":{"file_id":"doc1.pdf","file_unique_id":"u1","file_name":"notes.pdf","mime_type":"application/pdf","file_size":1400}}')
  untilt '[ "$(bot_calls_after "$seq" sendmessage)" -ge 1 ]' 180
  local unavailable_body='<b>Ratatoskr is temporarily unavailable</b>
Your item was not saved. Please send it again in a few minutes.'
  assert edge_down_gets_exactly_the_static_unavailable_body '[ "$(bot_replies_after "$seq" | head -c 4000)" = "$unavailable_body" ]' "$(bot_replies_after "$seq" | head -2 | cut -c1-120 | tr "\n" "|")"
  svc_start edge
  svc_wait_ready edge 90

  info "step 3: notifications"
  sleep 10
  assert dispatcher_stays_ready_and_idle '[ "$(code 127.0.0.1:9468/health/ready)" = 200 ]'
  "$PY" -I "$NATIVE_ROOT/fixtures/natsprobe.py" stream "$S/nk/edge.nkey" ratatoskr_events 'evt.platform.notification.>' >"$EV/notification-subjects.json" 2>&1
  assert nothing_published_a_notification '[ "$(jq -r ".subjects // {} | length" "$EV/notification-subjects.json" 2>/dev/null || echo 0)" = 0 ]' "no notification can be produced in this fleet: excluded, recorded in the changeset"
}
