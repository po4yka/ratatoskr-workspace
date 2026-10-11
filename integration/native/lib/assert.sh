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
assert() {
  local name=$1 cond=$2 detail=${3:-} line
  if eval "$cond"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    line="ASSERT $name: PASS $detail"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    line="ASSERT $name: FAIL $detail"
  fi
  printf '%s\n' "$line"
  printf '%s\n' "$line" >>"${EV:?ev_init first}/asserts.txt"
}

# The deviation of a flow that is not a failure, for example a hop that was not exercised.
info() {
  printf 'INFO %s\n' "$*"
  printf 'INFO %s\n' "$*" >>"${EV:?ev_init first}/asserts.txt"
}

code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
q() { psql -X -At -q -d "$1" -c "$2"; }
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
  dir=$(repo_dir "$id")
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
