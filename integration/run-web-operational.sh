#!/usr/bin/env bash
set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
profile="$workspace_root/integration/compose/web-operational.yaml"
namespace=${RATATOSKR_TASK_NAMESPACE:?set RATATOSKR_TASK_NAMESPACE}

if [[ ! "$namespace" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]]; then
  printf 'RATATOSKR_TASK_NAMESPACE must match [a-z0-9][a-z0-9-]{0,30}\n' >&2
  exit 2
fi

project="ratatoskr-${namespace}"
evidence_dir=${RATATOSKR_EVIDENCE_DIR:-"$workspace_root/evidence/$namespace"}
mkdir -p "$evidence_dir"
: >"$evidence_dir/timeline.txt"
owner_credential=web012-owner-credential
member_credential=web012-member-credential

require_revision() {
  local label=$1
  local context=$2
  local revision=$3
  local actual
  actual=$(git -C "$context" rev-parse HEAD)
  if [[ "$actual" != "$revision" ]]; then
    printf '%s context is at %s, expected %s\n' "$label" "$actual" "$revision" >&2
    exit 2
  fi
  git -C "$context" merge-base --is-ancestor "$revision" refs/remotes/origin/main || {
    printf '%s revision is not contained by origin/main\n' "$label" >&2
    exit 2
  }
}

require_revision Contracts "${RATATOSKR_CONTRACTS_CONTEXT:?set RATATOSKR_CONTRACTS_CONTEXT}" \
  "${RATATOSKR_CONTRACTS_REVISION:?set RATATOSKR_CONTRACTS_REVISION}"
require_revision Platform "${RATATOSKR_PLATFORM_CONTEXT:?set RATATOSKR_PLATFORM_CONTEXT}" \
  "${RATATOSKR_PLATFORM_REVISION:?set RATATOSKR_PLATFORM_REVISION}"
require_revision Web "${RATATOSKR_WEB_CONTEXT:?set RATATOSKR_WEB_CONTEXT}" \
  "${RATATOSKR_WEB_REVISION:?set RATATOSKR_WEB_REVISION}"

compose() {
  docker compose --project-name "$project" --file "$profile" "$@"
}

cleanup() {
  local status=$?
  set +e
  compose ps --all >"$evidence_dir/final-compose-ps.txt" 2>&1
  compose logs --no-color >"$evidence_dir/compose.log" 2>&1
  docker compose --project-name "$project" --file "$profile" down --volumes --remove-orphans \
    >"$evidence_dir/teardown.log" 2>&1
  docker ps --format '{{.ID}} {{.Names}} {{.Ports}}' >"$evidence_dir/docker-after.txt"
  exit "$status"
}
trap cleanup EXIT INT TERM

compose config --quiet

if [[ ${1:-} == --validate ]]; then
  printf 'web operational profile validation: PASS\n'
  exit 0
fi

wait_for_http() {
  local url=$1
  local expected=$2
  local output=$3
  local _ code
  for _ in $(seq 1 120); do
    code=$(curl --silent --show-error --output "$output" --write-out '%{http_code}' "$url" || true)
    if [[ "$code" == "$expected" ]]; then
      return 0
    fi
    sleep 1
  done
  printf 'Timed out waiting for %s to return %s\n' "$url" "$expected" >&2
  return 1
}

wait_for_status_state() {
  local expected=$1
  local output=$2
  local _
  for _ in $(seq 1 60); do
    if curl --silent --show-error --fail "$platform_url/v1/status" >"$output" \
      && jq --exit-status --arg expected "$expected" '.state == $expected' "$output" >/dev/null
    then
      return 0
    fi
    sleep 1
  done
  printf 'Timed out waiting for public status state %s\n' "$expected" >&2
  return 1
}

request() {
  local name=$1
  local expected=$2
  local credential=$3
  local path=$4
  local output="$evidence_dir/$name.json"
  local code
  if [[ -n "$credential" ]]; then
    code=$(curl --silent --show-error --output "$output" --write-out '%{http_code}' \
      --header "Authorization: Bearer $credential" "$platform_url$path")
  else
    code=$(curl --silent --show-error --output "$output" --write-out '%{http_code}' \
      "$platform_url$path")
  fi
  if [[ "$code" != "$expected" ]]; then
    printf '%s returned HTTP %s, expected %s\n' "$path" "$code" "$expected" >&2
    return 1
  fi
}

run_browser_smoke() {
  local phase=$1
  local temporary_dir status
  temporary_dir=$(mktemp -d "$RATATOSKR_WEB_CONTEXT/.web012-compose-smoke.XXXXXX")
  cp "$workspace_root/integration/tests/web_operational_smoke.mjs" "$temporary_dir/smoke.mjs"
  set +e
  (
    cd "$RATATOSKR_WEB_CONTEXT"
    COMPOSE_WEB_URL="$web_url" node "$temporary_dir/smoke.mjs" "$phase"
  ) >"$evidence_dir/browser-$phase.txt" 2>&1
  status=$?
  set -e
  rm "$temporary_dir/smoke.mjs"
  rmdir "$temporary_dir"
  return "$status"
}

docker ps --format '{{.ID}} {{.Names}} {{.Ports}}' >"$evidence_dir/docker-before.txt"
docker compose ls --format json >"$evidence_dir/compose-before.json"

compose up --detach --build
platform_port=$(compose port platform 8080 | tail -1 | awk -F: '{print $NF}')
admin_port=$(compose port platform 9464 | tail -1 | awk -F: '{print $NF}')
web_port=$(compose port web 80 | tail -1 | awk -F: '{print $NF}')
platform_url="http://127.0.0.1:$platform_port"
admin_url="http://127.0.0.1:$admin_port"
web_url="http://127.0.0.1:$web_port"

wait_for_http "$admin_url/health/ready" 200 "$evidence_dir/health-ready.json"
wait_for_http "$web_url/status" 200 "$evidence_dir/web-status.html"
wait_for_status_state operational "$evidence_dir/status-healthy.json"

request status-anonymous 200 '' /v1/status
request status-invalid-credential 200 invalid-fixture /v1/status
request member-operations 403 "$member_credential" /v1/admin/operations
request owner-capabilities 200 "$owner_credential" /v1/capabilities
request owner-operations 200 "$owner_credential" /v1/admin/operations
request owner-schedules 200 "$owner_credential" /v1/admin/schedules
request owner-audit 200 "$owner_credential" /v1/admin/audit-events

jq --exit-status '.code == "platform.auth.forbidden" and (.items | not)' \
  "$evidence_dir/member-operations.json" >/dev/null
jq --exit-status '
  [.capabilities[]] as $capabilities
  | (["platform.audit.inspect", "platform.operations.inspect", "platform.schedules.inspect"]
     - $capabilities | length) == 0
' "$evidence_dir/owner-capabilities.json" >/dev/null
jq --exit-status '
  (.items | length) == 3
  and any(.items[]; .status == "failed")
  and any(.items[]; .status == "partially_succeeded")
  and all(.items[]; has("message") | not)
' "$evidence_dir/owner-operations.json" >/dev/null
jq --exit-status '(.items | length) == 2 and any(.items[]; .enabled == false and .last_outcome == "failed")' \
  "$evidence_dir/owner-schedules.json" >/dev/null
jq --exit-status '(.items | length) == 2 and any(.items[]; .actor_user_id == null and .outcome == "failed")' \
  "$evidence_dir/owner-audit.json" >/dev/null
run_browser_smoke healthy

printf '%s degraded phase: stopping namespaced NATS\n' "$(date -u +%FT%TZ)" \
  >>"$evidence_dir/timeline.txt"
compose stop nats
wait_for_status_state degraded "$evidence_dir/status-degraded.json"
jq --exit-status '
  .state == "degraded"
  and any(.components[]; .id == "command_delivery" and .state == "unavailable" and .stale)
' "$evidence_dir/status-degraded.json" >/dev/null
run_browser_smoke degraded

printf '%s recovery phase: starting namespaced NATS\n' "$(date -u +%FT%TZ)" \
  >>"$evidence_dir/timeline.txt"
compose start nats
wait_for_status_state operational "$evidence_dir/status-recovered.json"

compose ps --all >"$evidence_dir/healthy-compose-ps.txt"
printf 'healthy API, owner/member, browser, degraded, recovery: PASS\n' | tee "$evidence_dir/result.txt"
