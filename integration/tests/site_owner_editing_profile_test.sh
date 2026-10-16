#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
profile="$root/integration/compose/site-owner-editing.yaml"
runner="$root/integration/run-site-owner-editing.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
[[ -f "$profile" ]] || fail 'missing site-owner-editing composed profile'
[[ -f "$root/integration/fixtures/site-owner-editing.py" ]] || fail "missing real HTTP scenario"
[[ -f "$runner" ]] || fail 'missing site-owner-editing runner'
for service in postgres nats platform sites notes knowledge; do
  rg -q "^  ${service}:" "$profile" || fail "missing $service"
done
for input in TASK_NAMESPACE PLATFORM_CONTEXT PLATFORM_REVISION SITES_CONTEXT SITES_REVISION NOTES_CONTEXT NOTES_REVISION KNOWLEDGE_CONTEXT KNOWLEDGE_REVISION; do
  rg -q -F "RATATOSKR_${input}:?" "$profile" || fail "missing required input $input"
done
! rg -q 'container_name:|external: true|network_mode: host' "$profile" || fail 'global Compose resource'
rg -q -F '127.0.0.1::8080' "$profile" || fail 'Platform port is not dynamic loopback'
rg -q -F 'render_nats_conf' "$runner" || fail 'missing deployed bus ACL renderer'
rg -q -F 'down --volumes --remove-orphans' "$runner" || fail 'missing isolated teardown'
for step in consent_sign_in edit_conflicted edit_completed manual_release_retains_old_text release_published_public_sse knowledge_search_holds_only_owner_documents; do
  rg -q -F "$step" "$runner" || fail "missing scenario $step"
done
[[ -f "$root/integration/sites-privacy/scenario.py" ]] || fail 'missing real privacy scenario'
rg -q -F 'sites-integration:' "$root/.github/workflows/ci.yml" || fail 'missing workspace sites integration job'
printf 'site owner editing profile contract: PASS\n'
