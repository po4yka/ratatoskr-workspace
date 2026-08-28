#!/usr/bin/env bash
set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
profile="$workspace_root/integration/compose/telegram-notification.yaml"
runner="$workspace_root/integration/run-telegram-notification.sh"
fake_bot="$workspace_root/integration/fixtures/telegram-fake-bot-api.py"
database_seed="$workspace_root/integration/fixtures/telegram-notification-init.sql"

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

for file in "$profile" "$runner" "$fake_bot" "$database_seed"; do
  assert_file "$file"
done

for input in \
  RATATOSKR_TASK_NAMESPACE \
  RATATOSKR_CONTRACTS_CONTEXT RATATOSKR_CONTRACTS_REVISION \
  RATATOSKR_PLATFORM_CONTEXT RATATOSKR_PLATFORM_REVISION \
  RATATOSKR_TELEGRAM_CONTEXT RATATOSKR_TELEGRAM_REVISION \
  RATATOSKR_TG010_RUNTIME_DIR
do
  assert_contains "$profile" "${input}:?" "profile does not require $input"
done

for service in network postgres nats fake-bot platform telegram-webhook telegram-dispatcher tools; do
  assert_contains "$profile" "  ${service}:" "profile does not define $service"
done

if rg --quiet 'container_name:|127\.0\.0\.1:[0-9]+:' "$profile"; then
  fail "profile fixes a global container name or host port"
fi
for mapping in '127.0.0.1::8182' '127.0.0.1::9467' '127.0.0.1::9468'; do
  assert_contains "$profile" "$mapping" "profile lacks ephemeral mapping $mapping"
done

assert_contains "$profile" 'postgres:17' "profile does not pin PostgreSQL major 17"
assert_contains "$profile" 'ratatoskr_events' "profile lacks canonical event stream"
assert_contains "$profile" 'ratatoskr_telegram_notifications' "profile lacks canonical durable"
assert_contains "$profile" 'evt.platform.notification.raised.v1' "profile lacks canonical subject"
# These are literal source snippets, not expressions evaluated by this test.
# shellcheck disable=SC2016
assert_contains "$runner" 'project="ratatoskr-${namespace}"' "runner does not namespace the project"
# shellcheck disable=SC2016
assert_contains "$runner" '[[ "$namespace" != *tg010* ]]' "runner does not require the tg010 marker"
assert_contains "$runner" 'down --volumes --remove-orphans' "runner lacks exact Compose teardown"
assert_contains "$runner" 'article_flow_reaches_final_projection' "runner lacks article assertion"
assert_contains "$runner" 'enabled_notification_is_sent_once' "runner lacks enabled assertion"
assert_contains "$runner" 'disabled_notification_is_suppressed' "runner lacks suppression assertion"
assert_contains "$runner" 'duplicate_notification_is_not_sent_twice' "runner lacks duplicate assertion"
assert_contains "$runner" 'dispatcher_refuses_missing_or_mismatched_platform_durable' \
  "runner lacks durable failure assertion"
assert_contains "$runner" 'workspace_revision' "runner does not record the workspace source revision"

if rg --quiet --hidden -g '!telegram_notification_profile_test.sh' \
  '(BEGIN [A-Z ]*PRIVATE KEY|\bSU[A-Z2-7]{20,}|[0-9]{8,10}:[A-Za-z0-9_-]{30,})' \
  "$profile" "$runner" "$fake_bot" "$database_seed"; then
  fail "profile fixtures contain credential material"
fi

sentinel="ratatoskr-unrelated-sentinel-$$"
trap 'docker rm --force "$sentinel" >/dev/null 2>&1 || true' EXIT
docker run --detach --name "$sentinel" --entrypoint sh \
  nats@sha256:d4ac35882ac65aff236cd65b9d3fa4d24332c681e1a85f94eedccd3cdd65b1da \
  -c 'sleep 60' >/dev/null
RATATOSKR_TASK_NAMESPACE=tg010-static \
  RATATOSKR_CONTRACTS_CONTEXT=/tmp/contracts RATATOSKR_CONTRACTS_REVISION=contracts \
  RATATOSKR_PLATFORM_CONTEXT=/tmp/platform RATATOSKR_PLATFORM_REVISION=platform \
  RATATOSKR_TELEGRAM_CONTEXT=/tmp/telegram RATATOSKR_TELEGRAM_REVISION=telegram \
  RATATOSKR_TG010_RUNTIME_DIR=/tmp/tg010-runtime \
  "$runner" --teardown-plan >/tmp/tg010-teardown-plan.txt
docker inspect "$sentinel" >/dev/null || fail "dry-run teardown affected an unrelated container"
assert_contains /tmp/tg010-teardown-plan.txt '--project-name ratatoskr-tg010-static' \
  "teardown plan omits exact project"
assert_contains /tmp/tg010-teardown-plan.txt "$profile" "teardown plan omits exact profile"

printf 'Telegram notification profile contract: PASS\n'
