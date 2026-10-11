#!/usr/bin/env bash
# shellcheck disable=SC2034
# F3 Telegram to Platform (the webhook and the dispatcher as shipped, a fake Bot API, plus F2's services; R3-12). Sourced by run.sh; defines the flow, runs nothing.
#
# Provenance: the assertion-key steps and the PDF capture follow the by-hand Telegram PDF smoke of Round 3 (.workspaces/XR-021/smoke/tgpdf), which used a scripted assertion issuer; this flow runs the real webhook and dispatcher binaries, which no earlier smoke did (the Telegram webhook and dispatcher were never run before). Run through run.sh as committed: NO.

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
bot_seq() { jq -s 'map(.seq) | max // 0' "$S/logs/fake-bot.jsonl" 2>/dev/null || echo 0; }

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
  local seq status
  seq=$(bot_seq)
  status=$(post_update 1001 '{"document":{"file_id":"doc1.pdf","file_unique_id":"u1","file_name":"notes.pdf","mime_type":"application/pdf","file_size":1400}}')
  assert pdf_update_accepted_by_the_webhook '[ "$status" = 200 ]' "http=$status"
  untilt '[ "$(q ratatoskr "select count(*) from operations.operations where status in ('"'"'succeeded'"'"','"'"'partially_succeeded'"'"','"'"'failed'"'"')")" -ge 1 ]' 120
  local final
  final=$(q ratatoskr "select status from operations.operations order by accepted_at desc limit 1")
  assert pdf_capture_operation_succeeded '[ "$final" = succeeded ]' "$final"
  assert blob_is_in_the_shared_telegram_root '[ "$(find "$S/blobs/telegram" -type f | wc -l | tr -d " ")" -ge 1 ]'
  assert session_exchange_returned_201 '[ "$(jq -rs "[.[] | select(.path==\"/v1/sessions/telegram\" and .status==201)] | length" "$S/logs/tap.jsonl")" -ge 1 ]' "a real exchange through the tap"
  assert identity_row_written_by_the_first_exchange '[ "$(q ratatoskr "select count(*) from telegram.identities where internal_user_id is not null")" -ge 1 ]'
  untilt '[ "$(bot_replies_after "$seq" | wc -l | tr -d " ")" -ge 2 ]' 60
  assert acknowledgement_then_completion_replies '[ "$(bot_replies_after "$seq" | wc -l | tr -d " ")" -ge 2 ]' "replies in order: $(bot_replies_after "$seq" | cut -c1-80 | tr "\n" "|")"
  bot_replies_after "$seq" >"$EV/replies-pdf.txt"

  info "an attachment that is not a PDF"
  seq=$(bot_seq)
  status=$(post_update 1002 '{"photo":[{"file_id":"p1","file_unique_id":"p1u","width":10,"height":10,"file_size":100}]}')
  untilt '[ "$(bot_replies_after "$seq" | wc -l | tr -d " ")" -ge 1 ]' 60
  local unsupported_body='<b>Unsupported attachment</b>
Send a PDF document with a text layer; images, video, voice, and audio are not supported yet.'
  assert photo_update_gets_exactly_the_static_unsupported_body '[ "$(bot_replies_after "$seq" | head -c 4000)" = "$unsupported_body" ]' "$(bot_replies_after "$seq" | head -2 | cut -c1-120 | tr "\n" "|")"

  info "a forwarded PDF carries no attachment fact in origin"
  status=$(post_update 1003 '{"forward_date":1787900000,"forward_origin":{"type":"user","date":1787900000,"sender_user":{"id":42,"is_bot":false,"first_name":"Someone"}},"document":{"file_id":"doc1.pdf","file_unique_id":"u1","file_name":"forwarded-secret-name.pdf","mime_type":"application/pdf","file_size":1400}}')
  untilt '[ "$(jq -rs "[.[] | select(.path==\"/v1/captures/blobs\")] | length" "$S/logs/tap.jsonl")" -ge 2 ]' 90
  jq -s '[.[] | select(.path=="/v1/captures/blobs")] | last' "$S/logs/tap.jsonl" >"$EV/forwarded-capture-request.json"
  assert forwarded_request_origin_has_no_attachment_fact '[ "$(jq -r ".request.origin | keys | map(test(\"attach|file\")) | any" "$EV/forwarded-capture-request.json")" = false ] && [ "$(grep -c "forwarded-secret-name" "$EV/forwarded-capture-request.json")" = 0 ]' "origin keys: $(jq -c ".request.origin | keys" "$EV/forwarded-capture-request.json")"

  info "Edge stopped before a PDF is sent"
  svc_stop edge
  seq=$(bot_seq)
  status=$(post_update 1004 '{"document":{"file_id":"doc1.pdf","file_unique_id":"u1","file_name":"notes.pdf","mime_type":"application/pdf","file_size":1400}}')
  untilt '[ "$(bot_replies_after "$seq" | wc -l | tr -d " ")" -ge 1 ]' 180
  local unavailable_body='<b>Ratatoskr is temporarily unavailable</b>
Your item was not saved. Please send it again in a few minutes.'
  assert edge_down_gets_exactly_the_static_unavailable_body '[ "$(bot_replies_after "$seq" | head -c 4000)" = "$unavailable_body" ]' "$(bot_replies_after "$seq" | head -2 | cut -c1-120 | tr "\n" "|")"
  svc_start edge
  svc_wait_ready edge 90

  info "step 3: notifications"
  sleep 10
  assert dispatcher_stays_ready_and_idle '[ "$(code 127.0.0.1:9468/health/ready)" = 200 ]'
  python3 -I "$NATIVE_ROOT/fixtures/natsprobe.py" stream "$S/nk/edge.nkey" ratatoskr_events 'evt.platform.notification.>' >"$EV/notification-subjects.json" 2>&1
  assert nothing_published_a_notification '[ "$(jq -r ".subjects // {} | length" "$EV/notification-subjects.json" 2>/dev/null || echo 0)" = 0 ]' "no notification can be produced in this fleet: excluded, recorded in the changeset"
}
