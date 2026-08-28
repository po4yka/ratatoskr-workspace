#!/usr/bin/env bash
set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
target="$workspace_root/docs/DEPLOYMENT_TARGET.md"
telegram=${RATATOSKR_TELEGRAM_CONTEXT:?set RATATOSKR_TELEGRAM_CONTEXT}
revision=${RATATOSKR_TELEGRAM_REVISION:?set RATATOSKR_TELEGRAM_REVISION}
webhook="$telegram/deploy/systemd/ratatoskr-telegram-webhook.service"
dispatcher="$telegram/deploy/systemd/ratatoskr-telegram-dispatcher.service"
webhook_config="$telegram/deploy/systemd/webhook.conf.example"
dispatcher_config="$telegram/deploy/systemd/dispatcher.conf.example"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  rg --quiet --fixed-strings -- "$2" "$1" || fail "$3"
}

[[ $(git -C "$telegram" rev-parse HEAD) == "$revision" ]] || fail "Telegram context revision differs"
git -C "$telegram" diff --quiet || fail "Telegram context has unstaged changes"
git -C "$telegram" diff --cached --quiet || fail "Telegram context has staged changes"

for artifact in "$webhook" "$dispatcher"; do
  [[ -f "$artifact" ]] || fail "missing Telegram systemd artifact $artifact"
  assert_contains "$artifact" 'Type=exec' "unit is not Type=exec"
  assert_contains "$artifact" 'TimeoutStopSec=130s' "unit stop timeout differs"
  assert_contains "$artifact" 'MemoryMax=' "unit has no memory ceiling"
  assert_contains "$artifact" 'CPUQuota=' "unit has no CPU ceiling"
  assert_contains "$artifact" 'NoNewPrivileges=yes' "unit lacks process hardening"
  assert_contains "$artifact" '/mnt/nvme/ratatoskr/logs/' "unit does not use NVMe logging"
done

assert_contains "$webhook_config" 'RATATOSKR__WEBHOOK__BIND=127.0.0.1:8182' \
  "webhook public listener differs from 8182"
assert_contains "$webhook_config" 'RATATOSKR__ADMIN__BIND=0.0.0.0:9467' \
  "webhook operator listener differs from 9467"
assert_contains "$dispatcher_config" 'RATATOSKR__ADMIN__BIND=0.0.0.0:9468' \
  "dispatcher operator listener differs from 9468"
if rg --quiet 'RATATOSKR__WEBHOOK__BIND' "$dispatcher_config"; then
  fail "dispatcher claims a public listener"
fi
assert_contains "$dispatcher" 'Requires=ratatoskr-telegram-webhook.service' \
  "dispatcher does not order after the schema-owning webhook"

# The table snippets intentionally contain literal backticks rather than substitutions.
# shellcheck disable=SC2016
for allocation in \
  '| 8182 | `ratatoskr-telegram-webhook` public listener | `cloudflared` tunnel |' \
  '| 9467 | `ratatoskr-telegram-webhook` operator listener | host and monitoring bridge only |' \
  '| 9468 | `ratatoskr-telegram-dispatcher` operator listener | host and monitoring bridge only |'
do
  assert_contains "$target" "$allocation" "workspace deployment target lacks $allocation"
done

for port in 8182 9467 9468; do
  count=$(awk -F'|' -v port="$port" '$2 ~ "^[[:space:]]*" port "[[:space:]]*$" { count++ } END { print count + 0 }' "$target")
  [[ "$count" == 1 ]] || fail "port $port has $count allocation rows"
done

printf 'Telegram deployment profile contract: PASS (%s)\n' "$revision"
