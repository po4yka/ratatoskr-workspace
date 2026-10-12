#!/usr/bin/env bash
# shellcheck disable=SC2034
# F5 Social captures (Edge, X, Instagram, Threads; R3-02, R3-15). Sourced by run.sh; defines the flow, runs nothing.
#
# Provenance: the X legs follow the by-hand X capture smoke (.workspaces/XR-021/smoke/xcapp: the capture shape of the browser extension, a fake HTTPS X API behind a throwaway CA), which ended at the TLS leg in Round 2 and was fixed by R3-15; the lane-authority legs (R3-02), Instagram and Threads were not run before. Run through run.sh as committed: NO.

FLOW_ID=f5
FLOW_TITLE="Social captures: X, Instagram, Threads lanes, cross-lane report authority, public-resolution outcomes"
FLOW_BINARIES=("platform:ratatoskr-edge render-nats-config" "knowledge:ratatoskr-knowledge-service" "x:ratatoskr-x" "instagram:ratatoskr-instagram-archive" "threads:ratatoskr-threads-archive")
FLOW_PORTS="$INFRA_PORTS 8091 9081 9087 9082 9083 9084 $FAKE_X_PORT $FAKE_OPENROUTER_PORT"
FLOW_REPOS="platform knowledge x instagram threads"
FLOW_EVIDENCE="X capture by hand in Round 2 (failed at the TLS leg, fixed by R3-15); lane authority, Instagram and Threads not run before"
FLOW_HONESTY=(
  "faked: the X API is a loopback HTTPS fake behind a throwaway CA (X's EXTRA_CA_FILE is the one documented TLS seam, R3-15); everything it returns is faked provider content"
  "seeded: a user and a browser_extension device with a device session (fixtures/platform-seed.sql); the pairing API is exercised in F1"
  "NOT RUN: the success legs of Instagram and Threads public resolution. Their endpoints are allow-listed to Meta hosts on purpose and need credentials; only lane acceptance and the queued state are asserted"
  "deviation: Knowledge runs with the recap disabled and OpenRouter faked, started late in the flow to index the captured X post"
  "the cross-lane reports are published with the X identity's real seed by fixtures/natsprobe.py; the Instagram and Threads services are stopped for those legs so no provider call is made"
)

capture_social() {
  local name=$1 provider=$2 url=$3 key=$4 body
  body=$(jq -nc --arg url "$url" --arg p "$provider" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{social:{acquisition:"browser_extension",captured_at:$at,provider:$p,saved_authority:"explicit_user_capture"},url:$url}')
  call "$name" POST "$EDGE/v1/captures" "$DEV" "$body" "$key"
}

capture_plain() {
  local name=$1 url=$2 key=$3
  call "$name" POST "$EDGE/v1/captures" "$DEV" "$(jq -nc --arg url "$url" '{url:$url}')" "$key"
}

# threads_canonical_rows OPERATION_ID PERMALINK_TAIL: Threads capture rows of one operation whose canonical URL ends with the tail and holds neither a query nor an escape.
threads_canonical_rows() { q ratatoskr "select count(*) from threads_archive.captures where operation_id = '$1' and canonical_url like '%$2' and canonical_url not like '%?%' and canonical_url not like '%!%%' escape '!'"; }
op_of() { jq -r .operation_id "$EV/$1.resp.body"; }
reporter_of() { q ratatoskr "select coalesce(reporter, '') from operations.operations where operation_id='$1'"; }
fact_count() { python3 -I "$NATIVE_ROOT/fixtures/natsprobe.py" messages "$S/nk/edge.nkey" ratatoskr_events "$1" | jq -s "[.[] | select($2)] | length"; }

# Polls an operation every half second and prints the distinct statuses it showed with their stage, until it is terminal or the time is up.
watch_statuses() {
  local op=$1 max=$2 i seen="" now
  for ((i = 0; i < max * 2; i++)); do
    now=$(curl -s -H "Authorization: Bearer $DEV" "$EDGE/v1/operations/$op" | jq -r '"\(.status)/\(.stage)"')
    [[ "$seen" == *"$now"* ]] || seen="$seen $now"
    case $now in succeeded/*|failed/*|partially_succeeded/*|cancelled/*) break ;; esac
    sleep 0.5
  done
  printf '%s' "$seen"
}

flow_run() {
  infra_fresh || { assert infra_up 'false' "PostgreSQL or NATS did not start"; return; }
  edge_up || { assert edge_started 'false' "Edge did not become ready"; return; }
  assert_s04_durables
  seed_principals
  DEV=$(secret device)
  local row repo role
  for row in "x|ratatoskr_x" "instagram|ratatoskr_instagram" "threads|ratatoskr_threads" "knowledge|ratatoskr_knowledge"; do
    IFS='|' read -r repo role <<<"$row"
    pg_role "$repo" "$role" || { assert "role_$role" 'false' "role.sql failed"; return; }
  done
  mkdir -p "$S/blobs/threads" "$S/blobs/knowledge"
  python3 -I "$NATIVE_ROOT/fixtures/make_pki.py" "$S/pki" || return
  : >"$S/run/deleted.list"
  fake_start fake-x fake_x_api.py "$FAKE_X_PORT" "$S/pki/leaf.pem" "$S/pki/leaf.key" "$S/logs/fake-x.jsonl" "$S/run/deleted.list"
  conf_x && conf_instagram && conf_threads || return
  svc_start x
  svc_start instagram
  svc_start threads
  svc_wait_ready x 60
  svc_wait_ready instagram 60
  svc_wait_ready threads 60
  assert services_ready '[ "$(code 127.0.0.1:9087/health/ready)" = 200 ] && [ "$(code 127.0.0.1:9082/health/ready)" = 200 ] && [ "$(code 127.0.0.1:9084/health/ready)" = 200 ]'

  info "acceptance of every lane through the real bus"
  local status xop xop2 iop top top2 ids
  status=$(capture_social x1 x "https://x.com/ada/status/1700000000000000001" smoke-x1)
  xop=$(op_of x1)
  assert x_com_accepted '[ "$status" = 202 ]' "http=$status"
  status=$(capture_social x2 x "https://twitter.com/ada/status/1700000000000000002" smoke-x2)
  xop2=$(op_of x2)
  assert twitter_com_accepted '[ "$status" = 202 ]' "http=$status"
  status=$(capture_social ig1 instagram "https://www.instagram.com/p/Cabc123xyz/" smoke-ig1)
  iop=$(op_of ig1)
  assert instagram_accepted '[ "$status" = 202 ]' "http=$status"
  local ig_seen
  ig_seen=$(watch_statuses "$iop" 12)
  assert instagram_reaches_queued_capture_queued '[[ "$ig_seen" == *queued/capture_queued* ]]' "statuses seen:$ig_seen"
  status=$(capture_social th1 threads "https://www.threads.net/@ada/post/Cdef456" smoke-th1)
  top=$(op_of th1)
  assert threads_net_accepted '[ "$status" = 202 ]' "http=$status"
  status=$(capture_social th2 threads "https://www.threads.com/@ada/post/Cghi789" smoke-th2)
  top2=$(op_of th2)
  assert threads_com_accepted '[ "$status" = 202 ]' "http=$status"
  local th_seen
  th_seen=$(watch_statuses "$top" 12)
  assert threads_reaches_queued_capture_queued '[[ "$th_seen" == *queued/capture_queued* ]]' "statuses seen:$th_seen"

  info "Threads: a permalink with an escaped query is accepted and recorded under its canonical permalink (R4-07; RED against threads e3656d0 expected: intake refuses the permalink, no row exists and the operation fails at intake)"
  local th3 th3op th4 th4op
  th3=$(capture_social th3 threads "https://www.threads.net/@author/post/AbCd1?xmt=a%3Db" smoke-th3)
  th3op=$(op_of th3)
  assert threads_percent_encoded_query_accepted '[ "$th3" = 202 ]' "http=$th3"
  untilt '[ "$(threads_canonical_rows "$th3op" "/@author/post/AbCd1")" = 1 ]' 60
  assert threads_records_a_capture_for_the_canonical_permalink '[ "$(threads_canonical_rows "$th3op" "/@author/post/AbCd1")" = 1 ]' "rows for operation $th3op: $(q ratatoskr "select canonical_url from threads_archive.captures where operation_id = '$th3op'")"
  assert threads_percent_encoded_query_operation_ends_terminal '[[ "$(pollop "$th3op" "$DEV" 120 th3)" =~ ^(failed|partially_succeeded|succeeded)$ ]]' "public resolution is allow-listed to Meta hosts, so a failed or inaccessible end is the expected one and the success leg is NOT RUN"
  th4=$(capture_social th4 threads "https://www.threads.net/@author/post/AbCd2?q=caf$(printf '\303\251')" smoke-th4)
  th4op=$(op_of th4)
  if [[ "$th4" == 202 ]]; then
    untilt '[ "$(threads_canonical_rows "$th4op" "/@author/post/AbCd2")" = 1 ]' 60
    assert threads_non_ascii_query_byte_records_the_canonical_permalink '[ "$(threads_canonical_rows "$th4op" "/@author/post/AbCd2")" = 1 ]'
  else
    info "a non-ASCII query byte was refused by Edge before the Threads lane (http=$th4): the Threads grammar leg for that byte is NOT RUN"
  fi

  info "the lane each operation was dispatched to is recorded (R3-02)"
  assert x_operations_carry_the_x_lane '[ "$(reporter_of "$xop")" = ratatoskr-x ] && [ "$(reporter_of "$xop2")" = ratatoskr-x ]'
  assert instagram_operation_carries_the_instagram_lane '[ "$(reporter_of "$iop")" = ratatoskr-instagram ]'
  assert threads_operations_carry_the_threads_lane '[ "$(reporter_of "$top")" = ratatoskr-threads ] && [ "$(reporter_of "$top2")" = ratatoskr-threads ]'

  info "X: the fake answers, the post is captured and published"
  assert x_com_operation_succeeded '[ "$(pollop "$xop" "$DEV" 90 x1)" = succeeded ]'
  assert twitter_com_operation_succeeded '[ "$(pollop "$xop2" "$DEV" 90 x2)" = succeeded ]'
  local tenant_filter=".tenant_id == \"user:$U1\" and .producer == \"ratatoskr-x\""
  assert captured_facts_carry_the_owner_and_the_x_producer '[ "$(fact_count evt.social.source.captured.v1 "$tenant_filter")" -ge 2 ]' "facts on evt.social.source.captured.v1: $(fact_count evt.social.source.captured.v1 true)"
  assert fake_x_api_saw_authenticated_requests '[ "$(jq -s "[.[] | select(.kind==\"request\" and .auth_bearer==true)] | length" "$S/logs/fake-x.jsonl")" -ge 2 ]'

  info "X: a deleted post and a transport failure"
  printf '1700000000000000404\n' >>"$S/run/deleted.list"
  status=$(capture_social x404 x "https://x.com/ada/status/1700000000000000404" smoke-x404)
  local deleted_op
  deleted_op=$(op_of x404)
  assert deleted_post_terminates_failed '[ "$(pollop "$deleted_op" "$DEV" 90 x404)" = failed ] && grep -q "social.source.deleted" "$EV/op-x404.json"' "$(jq -c "[.status,.errors]" "$EV/op-x404.json" | cut -c1-200)"
  assert removed_fact_published '[ "$(fact_count evt.social.source.removed.v1 "$tenant_filter")" -ge 1 ]'
  svc_stop x
  render_conf x x.conf.example x \
    "--set RATATOSKR__DATABASE__URL=$(db_url ratatoskr_x)" \
    "--set RATATOSKR__BUS__NKEY_SEED_PATH=$(nkey x)" \
    "--set RATATOSKR__PUBLIC_CAPTURE__BEARER_TOKEN_PATH=$S/keys/x-public-capture.token" \
    "--set RATATOSKR__PUBLIC_CAPTURE__API_BASE_URL=https://127.0.0.1:$FAKE_X_PORT"
  svc_start x
  svc_wait_ready x 60
  status=$(capture_social xtls x "https://x.com/ada/status/1700000000000000505" smoke-xtls)
  local tls_op
  tls_op=$(op_of xtls)
  assert transport_failure_terminates_failed_unavailable '[ "$(pollop "$tls_op" "$DEV" 150 xtls)" = failed ] && grep -q "social.source.unavailable" "$EV/op-xtls.json"' "$(jq -c "[.status,.errors]" "$EV/op-xtls.json" | cut -c1-200)"
  assert unavailable_is_reported_once_and_not_pending '[ "$(q ratatoskr "select count(*) from x_archive.explicit_captures where operation_id='"'"'$tls_op'"'"' and status='"'"'unavailable'"'"' and reported_at is not null and next_attempt_at <= now()")" = 1 ]'

  info "Knowledge indexes the captured post when it runs with ingest enabled"
  fake_start fake-openrouter fake_openrouter.py "$FAKE_OPENROUTER_PORT" "$S/logs/fake-openrouter.jsonl" "$S/run"
  conf_knowledge false || return
  svc_start knowledge
  svc_wait_ready knowledge 90
  untilt '[ "$(q ratatoskr "select count(*) from knowledge.search_documents")" -ge 1 ]' 90
  assert captured_post_is_indexed '[ "$(q ratatoskr "select count(*) from knowledge.search_documents")" -ge 1 ]' "search documents: $(q ratatoskr "select count(*) from knowledge.search_documents")"

  info "cross-lane report authority (R3-02): the Instagram and Threads services are stopped so no provider call is made"
  svc_stop instagram
  svc_stop threads
  status=$(capture_social ig2 instagram "https://www.instagram.com/p/Cdef789abc/" smoke-ig2)
  local victim
  victim=$(op_of ig2)
  sleep 3
  local before event_id outcome
  before=$(q ratatoskr "select status || '/' || coalesce(stage, '') from operations.operations where operation_id='$victim'")
  event_id=$(python3 -I "$NATIVE_ROOT/fixtures/natsprobe.py" report "$S/nk/x.nkey" _INBOX_x "user:$U1" "$victim" ratatoskr-x)
  untilt '[ -n "$(q ratatoskr "select outcome from operations.inbox where message_id='"'"'$event_id'"'"'")" ]' 30
  outcome=$(q ratatoskr "select outcome from operations.inbox where message_id='$event_id'")
  assert forged_report_for_another_lane_is_rejected '[ "$outcome" = rejected ]' "inbox outcome: $outcome"
  assert forged_report_leaves_the_operation_unchanged '[ "$(q ratatoskr "select status || '"'"'/'"'"' || coalesce(stage, '"'"''"'"') from operations.operations where operation_id='"'"'$victim'"'"'")" = "$before" ]' "before=$before"
  event_id=$(python3 -I "$NATIVE_ROOT/fixtures/natsprobe.py" report "$S/nk/x.nkey" _INBOX_x "user:$U2" "$victim" ratatoskr-x)
  untilt '[ -n "$(q ratatoskr "select outcome from operations.inbox where message_id='"'"'$event_id'"'"'")" ]' 30
  assert report_for_another_tenant_is_rejected '[ "$(q ratatoskr "select outcome from operations.inbox where message_id='"'"'$event_id'"'"'")" = rejected ]'
  event_id=$(python3 -I "$NATIVE_ROOT/fixtures/natsprobe.py" report "$S/nk/instagram.nkey" _INBOX_instagram "user:$U1" "$victim" ratatoskr-instagram)
  untilt '[ -n "$(q ratatoskr "select outcome from operations.inbox where message_id='"'"'$event_id'"'"'")" ]' 30
  assert report_from_the_right_producer_and_tenant_is_applied '[ "$(q ratatoskr "select outcome from operations.inbox where message_id='"'"'$event_id'"'"'")" = applied ]' "operation now $(q ratatoskr "select status from operations.operations where operation_id='$victim'")"

  info "grammar boundaries"
  status=$(capture_social mismatch x "https://www.threads.com/@ada/post/Cmismatch1" smoke-mismatch)
  assert provider_x_on_a_threads_url_is_400 '[ "$status" = 400 ]' "http=$status"
  status=$(capture_plain plain20 "https://x.com/ada/status/17000000000000000001" smoke-plain20)
  local plain_op
  plain_op=$(op_of plain20)
  assert twenty_digit_status_id_is_accepted_in_the_generic_lane '[ "$status" = 202 ]' "http=$status"
  assert twenty_digit_status_id_is_not_an_x_lane '[ "$(reporter_of "$plain_op")" = ratatoskr-extractor ]' "reporter=$(reporter_of "$plain_op")"
}
