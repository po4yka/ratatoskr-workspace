#!/usr/bin/env bash
set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
profile="$workspace_root/integration/compose/web-operational.yaml"
runner="$workspace_root/integration/run-web-operational.sh"
seed="$workspace_root/integration/fixtures/web-operational.sql"
browser_smoke="$workspace_root/integration/tests/web_operational_smoke.mjs"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing $1"
}

assert_contains() {
  local file=$1
  local pattern=$2
  local description=$3
  rg --quiet --fixed-strings -- "$pattern" "$file" || fail "$description"
}

assert_file "$profile"
assert_file "$runner"
assert_file "$seed"

for input in \
  RATATOSKR_TASK_NAMESPACE \
  RATATOSKR_CONTRACTS_CONTEXT RATATOSKR_CONTRACTS_REVISION \
  RATATOSKR_PLATFORM_CONTEXT RATATOSKR_PLATFORM_REVISION \
  RATATOSKR_WEB_CONTEXT RATATOSKR_WEB_REVISION
do
  assert_contains "$profile" "${input}:?" "profile does not require $input"
done

for service in postgres nats platform seed web
do
  assert_contains "$profile" "  ${service}:" "profile does not define the $service service"
done

if rg --quiet 'container_name:' "$profile"; then
  fail "profile fixes a global container name"
fi

assert_contains "$profile" '127.0.0.1::8080' "Platform port is not dynamically assigned"
assert_contains "$profile" '127.0.0.1::80' "Web port is not dynamically assigned"
assert_contains "$runner" "docker compose --project-name \"\$project\"" \
  "runner does not scope Compose operations to the task project"
assert_contains "$runner" 'down --volumes --remove-orphans' \
  "runner does not tear down its project and volumes"

assert_contains "$seed" "'platform.owner'" "seed has no owner grant"
assert_contains "$seed" 'web012-owner-credential' \
  "seed does not document the fixed owner fixture credential"
assert_contains "$seed" 'web012-member-credential' \
  "seed does not document the fixed member fixture credential"
assert_contains "$runner" 'wait_for_http' "runner has no bounded HTTP startup wait"
assert_contains "$runner" '/v1/status' "runner does not inspect anonymous public status"
assert_contains "$runner" '/v1/admin/operations' "runner does not inspect owner operations"
assert_contains "$runner" '/v1/admin/schedules' "runner does not inspect owner schedules"
assert_contains "$runner" '/v1/admin/audit-events' "runner does not inspect owner audit"
assert_contains "$runner" 'stop nats' "runner does not isolate the NATS degradation phase"
assert_contains "$runner" 'start nats' "runner does not verify NATS recovery"
assert_contains "$runner" 'run_browser_smoke' "runner has no Playwright handoff"
assert_contains "$runner" ": >\"\$evidence_dir/timeline.txt\"" \
  "runner does not reset phase evidence before a repeated smoke"
assert_file "$browser_smoke"

printf 'web operational profile contract: PASS\n'
