#!/usr/bin/env bash
set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
profile="$workspace_root/integration/compose/github-fleet-bus.yaml"
runner="$workspace_root/integration/run-github-fleet-bus.sh"
provider="$workspace_root/integration/fixtures/github-fake-api.py"
proxy="$workspace_root/integration/fixtures/github-loopback-proxy.py"
topology="$workspace_root/integration/fixtures/github-provision-topology.sh"
evidence="$workspace_root/integration/evidence/GHB-017.md"

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

for file in "$profile" "$runner" "$provider" "$proxy" "$topology" "$evidence"; do
  assert_file "$file"
done

for input in \
  RATATOSKR_TASK_NAMESPACE RATATOSKR_PLATFORM_CONTEXT RATATOSKR_PLATFORM_REVISION \
  RATATOSKR_GITHUB_CONTEXT RATATOSKR_GITHUB_REVISION RATATOSKR_GHB017_RUNTIME_DIR
do
  assert_contains "$profile" "${input}:?" "profile does not require $input"
done

for service in network postgres nats fake-github topology github peers; do
  assert_contains "$profile" "  ${service}:" "profile does not define $service"
done

assert_contains "$profile" 'postgres:17' "profile does not pin PostgreSQL 17"
assert_contains "$profile" '127.0.0.1::8092' "profile lacks ephemeral domain port"
assert_contains "$profile" '127.0.0.1::9469' "profile lacks ephemeral operator port"
assert_contains "$profile" 'RATATOSKR__API__LISTEN_ADDRESS: 127.0.0.1:18092' \
  "GitHub does not retain a strict loopback domain bind"
assert_contains "$profile" 'RATATOSKR__ADMIN__LISTEN_ADDRESS: 127.0.0.1:19469' \
  "GitHub does not retain a strict loopback operator bind"
assert_contains "$profile" 'ratatoskr_github_sync' "profile lacks sync durable"
assert_contains "$profile" 'ratatoskr_github_analysis_completed' "profile lacks completion durable"
assert_contains "$profile" 'ratatoskr_github_analysis_failed' "profile lacks failure durable"
assert_contains "$profile" 'ratatoskr_github_vault_policy_ack' "profile lacks Vault durable"
assert_contains "$profile" 'cmd.github.sync.requested.v1' "profile lacks sync subject"
assert_contains "$profile" 'evt.knowledge.repository_analysis.requested.v1' \
  "profile lacks Knowledge request subject"
assert_contains "$profile" 'cmd.vault.target.desired.v1' "profile lacks Vault command subject"
assert_contains "$topology" 'stream info' "topology fixture is not restart-idempotent"
assert_contains "$topology" 'consumer info' "consumer fixture is not restart-idempotent"

if rg --quiet 'container_name:|127\.0\.0\.1:[0-9]+:' "$profile"; then
  fail "profile fixes a global container name or host port"
fi

# These are literal source snippets, not expressions evaluated by this test.
# shellcheck disable=SC2016
assert_contains "$runner" 'project="ratatoskr-${namespace}"' "runner does not namespace Compose"
# shellcheck disable=SC2016
assert_contains "$runner" '[[ "$namespace" != *ghb017* ]]' "runner does not require GHB-017 namespace"
assert_contains "$runner" 'down --volumes --remove-orphans' "runner lacks exact teardown"
assert_contains "$runner" 'scheduled_sync_is_consumed_once' "runner lacks sync assertion"
assert_contains "$runner" 'knowledge_completion_and_failure_are_terminal' \
  "runner lacks Knowledge terminal assertions"
assert_contains "$runner" 'vault_acknowledgment_is_consumed_once' "runner lacks Vault assertion"
assert_contains "$runner" 'broker_ack_before_mark_replays_identical_bytes' \
  "runner lacks outbound crash-window assertion"
assert_contains "$runner" 'inbox_commit_before_ack_absorbs_duplicate' \
  "runner lacks inbound crash-window assertion"
assert_contains "$runner" 'all_durable_ack_floors_advance' "runner lacks cursor assertion"
assert_contains "$runner" 'bounded_shutdown_preserves_readiness_truth' \
  "runner lacks readiness and drain assertion"

for field in \
  'Platform revision' 'GitHub revision' 'Workspace revision' 'Compose SHA-256' \
  'Platform topology source' 'GitHub image ID' 'Scheduled sync' 'Knowledge request' \
  'Vault desired policy' 'Restart recovery' 'Durable acknowledgement floors' \
  'Hosted CI' 'Live deployment' 'Live GitHub provider' 'Live Knowledge or Vault'
do
  assert_contains "$evidence" "$field" "evidence omits $field"
done
assert_contains "$evidence" 'synthetic' "evidence omits its fixture boundary"

if rg --quiet --hidden -g '!github_fleet_bus_profile_test.sh' \
  '(BEGIN [A-Z ]*PRIVATE KEY|\bSU[A-Z2-7]{20,}|github_pat_|ghp_[A-Za-z0-9])' \
  "$profile" "$runner" "$provider" "$evidence"; then
  fail "profile source or evidence contains credential material"
fi

RATATOSKR_TASK_NAMESPACE=ghb017-static \
  RATATOSKR_PLATFORM_CONTEXT=/tmp/platform RATATOSKR_PLATFORM_REVISION=platform \
  RATATOSKR_GITHUB_CONTEXT=/tmp/github RATATOSKR_GITHUB_REVISION=github \
  RATATOSKR_GHB017_RUNTIME_DIR=/tmp/ghb017-runtime \
  "$runner" --teardown-plan >/tmp/ghb017-teardown-plan.txt
assert_contains /tmp/ghb017-teardown-plan.txt '--project-name ratatoskr-ghb017-static' \
  "teardown plan omits exact project"
assert_contains /tmp/ghb017-teardown-plan.txt "$profile" "teardown plan omits exact profile"

printf 'GitHub fleet-bus profile contract: PASS\n'
