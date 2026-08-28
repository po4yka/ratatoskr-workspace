#!/usr/bin/env bash
set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
profile="$workspace_root/integration/compose/telegram-library.yaml"
runner="$workspace_root/integration/run-telegram-library.sh"
fake_bot="$workspace_root/integration/fixtures/telegram-library-fake-bot-api.py"
database_seed="$workspace_root/integration/fixtures/telegram-library-init.sql"
evidence_summary="$workspace_root/integration/evidence/TG-011.md"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing $1"
}

assert_contains() {
  rg --quiet --fixed-strings -- "$2" "$1" || fail "$3"
}

assert_matches() {
  rg --quiet --multiline -- "$2" "$1" || fail "$3"
}

assert_service_has() {
  local service=$1 value=$2
  sed -n "/^  ${service}:/,/^  [a-z][a-z-]*:/p" "$profile" \
    | rg --quiet --fixed-strings -- "$value" \
    || fail "profile service $service lacks $value"
}

# profile_declares_exact_services_ports_healthchecks_and_task_namespace
for file in "$profile" "$runner" "$fake_bot" "$database_seed"; do
  assert_file "$file"
done
assert_file "$evidence_summary"

for input in \
  RATATOSKR_TASK_NAMESPACE \
  RATATOSKR_KNOWLEDGE_CONTEXT RATATOSKR_KNOWLEDGE_REVISION \
  RATATOSKR_PLATFORM_CONTEXT RATATOSKR_PLATFORM_REVISION \
  RATATOSKR_TELEGRAM_CONTEXT RATATOSKR_TELEGRAM_REVISION \
  RATATOSKR_TG011_RUNTIME_DIR
do
  assert_contains "$profile" "${input}:?" "profile does not require $input"
done

for service in network postgres nats fake-bot knowledge platform telegram-webhook telegram-dispatcher; do
  assert_contains "$profile" "  ${service}:" "profile does not define $service"
done

if rg --quiet 'container_name:|127\.0\.0\.1:[0-9]+:' "$profile"; then
  fail "profile fixes a global container name or host port"
fi
for mapping in \
  '127.0.0.1::8080' '127.0.0.1::8091' '127.0.0.1::8182' \
  '127.0.0.1::9464' '127.0.0.1::9467' '127.0.0.1::9468' '127.0.0.1::18080'
do
  assert_contains "$profile" "$mapping" "profile lacks ephemeral mapping $mapping"
done

assert_contains "$profile" 'pgvector/pgvector:pg17' "profile does not use PostgreSQL 17 with pgvector"
assert_contains "$profile" 'RATATOSKR__ADMIN__LISTEN_ADDRESS: 127.0.0.1:8091' \
  "Knowledge does not use its allocated loopback listener"
assert_contains "$profile" 'RATATOSKR__GATEWAY__ROUTES__KNOWLEDGE__PREFIX: /v1/k' \
  "Platform lacks the canonical Knowledge prefix"
assert_contains "$profile" 'RATATOSKR__GATEWAY__ROUTES__KNOWLEDGE__LISTENER: 127.0.0.1:8091' \
  "Platform lacks the canonical Knowledge listener"
assert_contains "$profile" 'RATATOSKR__GATEWAY__ROUTES__KNOWLEDGE__CLASS: stream' \
  "Platform lacks the Knowledge route class"
for service in postgres nats fake-bot knowledge platform telegram-webhook telegram-dispatcher; do
  assert_service_has "$service" 'healthcheck:'
done

# These are literal source snippets, not expressions evaluated by this test.
# shellcheck disable=SC2016
assert_contains "$runner" 'project="ratatoskr-${namespace}"' "runner does not namespace the project"
# shellcheck disable=SC2016
assert_contains "$runner" '[[ "$namespace" != *tg011* ]]' "runner does not require the tg011 marker"
assert_contains "$runner" 'down --volumes --remove-orphans' "runner lacks exact Compose teardown"
assert_contains "$runner" 'workspace_revision' "runner does not record the workspace source revision"

# runner_asserts_search_unread_read_scope_and_capability_recovery
for assertion in \
  seed_two_tenant_library_fixture \
  search_returns_owner_results_only \
  unread_returns_two_owner_items \
  captured_read_token_changes_authoritative_state \
  replayed_read_token_is_refused \
  foreign_read_token_is_refused \
  final_unread_omits_marked_item \
  favorite_state_is_preserved \
  knowledge_failure_removes_capabilities \
  knowledge_recovery_restores_capabilities
do
  assert_contains "$runner" "$assertion" "runner lacks assertion $assertion"
done

for evidence_field in \
  'Knowledge revision' 'Platform revision' 'Telegram revision' 'Workspace revision' \
  'Compose SHA-256' 'Knowledge image ID' 'Platform image ID' 'Telegram image ID' \
  'Search owner results' 'Initial unread results' 'Final unread results' \
  'Read token replay' 'Foreign token denial' 'Favorite preserved' \
  'Capability disappearance' 'Capability recovery' 'Hosted CI' 'Live Telegram'
do
  assert_contains "$evidence_summary" "$evidence_field" "evidence omits $evidence_field"
done
assert_contains "$evidence_summary" 'synthetic' "evidence omits its synthetic boundary"

if rg --quiet --hidden -g '!telegram_library_profile_test.sh' \
  '(BEGIN [A-Z ]*PRIVATE KEY|\bSU[A-Z2-7]{20,}|[0-9]{8,10}:[A-Za-z0-9_-]{30,})' \
  "$profile" "$runner" "$fake_bot" "$database_seed" "$evidence_summary"; then
  fail "profile fixtures contain credential material"
fi

sentinel="ratatoskr-unrelated-sentinel-$$"
trap 'docker rm --force "$sentinel" >/dev/null 2>&1 || true' EXIT
docker run --detach --name "$sentinel" --entrypoint sh \
  nats@sha256:d4ac35882ac65aff236cd65b9d3fa4d24332c681e1a85f94eedccd3cdd65b1da \
  -c 'sleep 60' >/dev/null
RATATOSKR_TASK_NAMESPACE=tg011-static \
  RATATOSKR_KNOWLEDGE_CONTEXT=/tmp/knowledge RATATOSKR_KNOWLEDGE_REVISION=knowledge \
  RATATOSKR_PLATFORM_CONTEXT=/tmp/platform RATATOSKR_PLATFORM_REVISION=platform \
  RATATOSKR_TELEGRAM_CONTEXT=/tmp/telegram RATATOSKR_TELEGRAM_REVISION=telegram \
  RATATOSKR_TG011_RUNTIME_DIR=/tmp/tg011-runtime \
  "$runner" --teardown-plan >/tmp/tg011-teardown-plan.txt
docker inspect "$sentinel" >/dev/null || fail "dry-run teardown affected an unrelated container"
assert_contains /tmp/tg011-teardown-plan.txt '--project-name ratatoskr-tg011-static' \
  "teardown plan omits exact project"
assert_contains /tmp/tg011-teardown-plan.txt "$profile" "teardown plan omits exact profile"

printf 'Telegram library profile contract: PASS\n'
