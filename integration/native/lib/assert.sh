#!/usr/bin/env bash
# shellcheck disable=SC2034
# Assertions and HTTP helpers of the native smoke. Source after lib/common.sh. An assertion prints "ASSERT <name>: PASS|FAIL <detail>" and is recorded in $EV/asserts.txt; a failed assertion never aborts the flow, it is recorded and the flow goes on to cleanup.

PASS_COUNT=0
FAIL_COUNT=0

ev_init() {
  EV=$EVIDENCE_ROOT/$1
  mkdir -p "$EV"
  : >"$EV/asserts.txt"
  export EV
}

# assert NAME 'shell condition' [detail]
# The condition is evaluated in the caller's scope, so every local of this function carries the `_assert_` prefix: a caller variable named `name`, `cond`, `detail` or `line` stays visible to its own condition.
# A query helper (q) that failed while the condition ran makes the assertion FAIL whatever the condition said: a command substitution that fails does not fail `[ "$(q ...)" = 0 ]`, and two empty strings compare equal.
assert() {
  local _assert_name=$1 _assert_cond=$2 _assert_detail=${3:-} _assert_line _assert_verdict=PASS _assert_q
  rm -f "${EV:?ev_init first}/.q-failed"
  eval "$_assert_cond" || _assert_verdict=FAIL
  if [[ -s "$EV/.q-failed" ]]; then
    _assert_q=$(head -c 300 "$EV/.q-failed" | tr '\n' ' ')
    _assert_verdict=FAIL
    _assert_detail="$_assert_detail [a query failed: $_assert_q]"
  fi
  if [[ "$_assert_verdict" == PASS ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  _assert_line="ASSERT $_assert_name: $_assert_verdict $_assert_detail"
  printf '%s\n' "$_assert_line"
  printf '%s\n' "$_assert_line" >>"$EV/asserts.txt"
}

# The deviation of a flow that is not a failure, for example a hop that was not exercised.
info() {
  printf 'INFO %s\n' "$*"
  printf 'INFO %s\n' "$*" >>"${EV:?ev_init first}/asserts.txt"
}

# metric PORT NAME [LABEL]: the value of one series on an operator port (127.0.0.1:PORT/metrics), for example `metric 9081 knowledge_ingest_redeliveries_total` or `metric 9464 platform_bus_consumer_pending 'durable="ratatoskr_knowledge_ai_archive"'` (the label text must occur in the series' label set). A series the endpoint does not state is an error recorded for the running assertion, not an empty string.
metric() {
  local _metric_value
  _metric_value=$(curl -fsS "127.0.0.1:$1/metrics" 2>/dev/null | awk -v name="$2" -v labels="${3:-}" '
    labels == "" && $1 == name { print $2; exit }
    labels != "" && index($0, name "{") == 1 && index($0, labels) > 0 { print $NF; exit }')
  if [[ -z "$_metric_value" ]]; then
    printf 'metric %s%s{%s} is not stated on 127.0.0.1:%s/metrics\n' "$2" "" "${3:-}" "$1" >>"${EV:?ev_init first}/.q-failed"
    return 1
  fi
  printf '%s' "$_metric_value"
}

# logcount FILE PATTERN: how many lines of a log match (0 when none or the file is missing; grep -c, not rg -c, which prints nothing for zero).
logcount() { grep -c -- "$2" "$1" 2>/dev/null || true; }

code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
# q DATABASE SQL: prints the rows, and on a psql error prints the error to stderr, records it for the assertion that ran the query (see assert) and returns psql's non-zero status. It never prints "nothing" for an error.
q() {
  local _q_err="${EV:?ev_init first}/.q-stderr" _q_rc
  psql -X -At -q -v ON_ERROR_STOP=1 -d "$1" -c "$2" 2>"$_q_err"
  _q_rc=$?
  if ((_q_rc != 0)); then
    printf 'q failed (rc=%s) on %s: %s\n' "$_q_rc" "$1" "$(tr '\n' ' ' <"$_q_err")" >>"$EV/.q-failed"
    cat "$_q_err" >&2
  fi
  return "$_q_rc"
}
untilt() { local i; for ((i = 0; i < $2; i++)); do eval "$1" && return 0; sleep 1; done; return 1; }
waitready() {
  local url=$1 max=${2:-60} i
  for ((i = 0; i < max; i++)); do
    [[ "$(code "$url")" == 200 ]] && return 0
    sleep 1
  done
  return 1
}

# call NAME METHOD URL TOKEN [json-body] [idempotency-key]: saves a request (credential redacted) and the response under $EV and prints the HTTP status.
call() {
  local name=$1 method=$2 url=$3 token=$4 body=${5:-} key=${6:-}
  local args=(-s -D "$EV/$name.resp.headers" -o "$EV/$name.resp.body" -w '%{http_code}' -X "$method")
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  [[ -n "$key" ]] && args+=(-H "Idempotency-Key: $key")
  [[ -n "$body" ]] && args+=(-H 'Content-Type: application/json' -d "$body")
  local status
  status=$(curl "${args[@]}" "$url")
  printf '%s %s\nAuthorization: Bearer [redacted]\nIdempotency-Key: %s\n\n%s\n' "$method" "$url" "$key" "$body" \
    | sed -E 's#"(code|credential|assertion|device_secret)":"[^"]*"#"\1":"[redacted]"#g' >"$EV/$name.req"
  printf '%s' "$status"
}

# pollop ID TOKEN MAX_SECONDS TAG: polls GET /v1/operations/{id} and prints the terminal status, or timeout:<last>.
pollop() {
  local id=$1 token=$2 max=$3 tag=$4 waited=0 status=
  while ((waited < max)); do
    curl -s -H "Authorization: Bearer $token" "$EDGE/v1/operations/$id" >"$EV/op-$tag.json"
    status=$(jq -r .status "$EV/op-$tag.json" 2>/dev/null)
    case $status in succeeded|failed|partially_succeeded|cancelled) printf '%s' "$status"; return ;; esac
    sleep 2
    waited=$((waited + 2))
  done
  printf 'timeout:%s' "$status"
}

jsz() { curl -s "$NATS_MON/jsz?streams=true&consumers=true&config=true"; }

# "filter ack_wait_seconds max_deliver" of a durable, from the monitoring endpoint.
dur() {
  jsz | jq -r --arg n "$1" '[.account_details[].stream_detail[].consumer_detail[]? | select(.name==$n) | [.config.filter_subject, (.config.ack_wait/1e9|floor|tostring), (.config.max_deliver|tostring)] | join(" ")] | first // empty'
}
pending() {
  jsz | jq -r --arg n "$1" '[.account_details[].stream_detail[].consumer_detail[]? | select(.name==$n) | (.num_ack_pending+.num_pending)] | first // "none"'
}

# Number of ACL violations in the NATS log outside the deliberate probe window of flow F0.
nats_violation_count() {
  local log=$S/logs/nats.log begin=0 end=0
  [[ -f "$log" ]] || { printf '0'; return; }
  [[ -f "$S/run/probe.begin" ]] && begin=$(cat "$S/run/probe.begin")
  [[ -f "$S/run/probe.end" ]] && end=$(cat "$S/run/probe.end")
  awk -v b="$begin" -v e="$end" '
    /Publish Violation|Subscription Violation|Authorization Violation/ { if (!(b > 0 && NR > b && NR <= e)) n++ }
    END { print n + 0 }
  ' "$log"
}

# A submodule that a flow built from must still be clean when the flow ends.
assert_repo_clean() {
  local id=$1 dir dirty
  dir=$(baseline_dir "$id")
  dirty=$(git -C "$dir" status --porcelain --untracked-files=all | wc -l | tr -d ' ')
  assert "repo_clean_$id" '[ "$dirty" = 0 ]' "dirty files: $dirty"
}

# result_write NAME-OF-FLOW: writes result.txt; the verdict is FAIL when any assertion failed.
result_write() {
  local verdict=PASS
  ((FAIL_COUNT == 0)) || verdict=FAIL
  {
    printf '%s\n' "$verdict"
    printf 'assertions: pass=%s fail=%s\n' "$PASS_COUNT" "$FAIL_COUNT"
    printf 'hops stubbed, seeded or not exercised:\n'
    printf '  %s\n' "${FLOW_HONESTY[@]}"
    if [[ -f "$S/conf/deviations.txt" ]]; then
      printf 'configuration deviations from the shipped examples:\n'
      sed 's/^/  /' "$S/conf/deviations.txt"
    fi
  } >"$EV/result.txt"
  printf 'RESULT %s: %s (pass=%s fail=%s)\n' "$1" "$verdict" "$PASS_COUNT" "$FAIL_COUNT"
}

# Counts and records the ASSERT lines a helper program (a Python driver) printed: ingest_assert_lines FILE.
ingest_assert_lines() {
  local passed failed
  passed=$(grep -c '^ASSERT .*: PASS' "$1")
  failed=$(grep -c '^ASSERT .*: FAIL' "$1")
  PASS_COUNT=$((PASS_COUNT + passed))
  FAIL_COUNT=$((FAIL_COUNT + failed))
  grep -E '^(ASSERT|INFO) ' "$1" >>"$EV/asserts.txt"
}
