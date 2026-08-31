#!/usr/bin/env bash
set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
profile="$workspace_root/integration/compose/export-agent-product.yaml"
runner="$workspace_root/integration/run-export-agent-product.sh"
fixture_builder="$workspace_root/integration/fixtures/export-agent-product-fixtures.sh"
database_seed="$workspace_root/integration/fixtures/export-agent-product-init.sql"
evidence_summary="$workspace_root/integration/evidence/XPA-020.md"
tls_proxy="$workspace_root/integration/nginx/export-agent-product.conf"
system_host="$workspace_root/integration/fixtures/ExportAgentProductSystemHost.swift"
nkey_generator="$workspace_root/integration/fixtures/export-agent-product-nkeys.go"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_file() { [[ -f "$1" ]] || fail "missing $1"; }
assert_contains() {
  rg --quiet --fixed-strings -- "$2" "$1" || fail "$3"
}

for file in \
  "$profile" "$runner" "$fixture_builder" "$database_seed" "$evidence_summary" \
  "$tls_proxy" "$system_host" "$nkey_generator"
do
  assert_file "$file"
done

for input in \
  RATATOSKR_TASK_NAMESPACE RATATOSKR_XPA020_RUNTIME_DIR \
  RATATOSKR_CONTRACTS_CONTEXT RATATOSKR_CONTRACTS_REVISION \
  RATATOSKR_PLATFORM_CONTEXT RATATOSKR_PLATFORM_REVISION \
  RATATOSKR_CHATGPT_CONTEXT RATATOSKR_CHATGPT_REVISION \
  RATATOSKR_CLAUDE_CONTEXT RATATOSKR_CLAUDE_REVISION \
  RATATOSKR_EXPORT_AGENT_CONTEXT RATATOSKR_EXPORT_AGENT_REVISION \
  RATATOSKR_WORKSPACE_CONTEXT RATATOSKR_WORKSPACE_REVISION
do
  assert_contains "$profile" "${input}:?" "profile does not require $input"
  assert_contains "$runner" "$input" "runner does not validate $input"
done

for service in network postgres nats platform chatgpt claude tls-edge; do
  assert_contains "$profile" "  ${service}:" "profile does not define $service"
done
if rg --quiet 'container_name:|127\.0\.0\.1:[0-9]+:' "$profile"; then
  fail "profile fixes a global container name or host port"
fi
if rg --quiet '[a-z][a-z0-9+.-]*://[^/:@[:space:]\"]+:[^/@[:space:]\"]+@' \
  "$profile" "$database_seed"; then
  fail "profile assets embed a database credential in a URL"
fi
for mapping in \
  '127.0.0.1::8080' '127.0.0.1::8096' '127.0.0.1::8097' \
  '127.0.0.1::8443' '127.0.0.1::9464'
do
  assert_contains "$profile" "$mapping" "profile lacks ephemeral mapping $mapping"
done
for service in platform chatgpt claude tls-edge; do
  assert_contains "$profile" 'network_mode: service:network' \
    "profile does not share the task loopback namespace for $service"
done
assert_contains "$profile" 'RATATOSKR__BUS__NKEY_SEED_PATH' \
  "Platform does not read its generated NKey seed"
assert_contains "$profile" 'RATATOSKR__RECEIPT__EVENT_BUS_NKEY_SEED_PATH' \
  "provider services do not read generated NKey seeds"
assert_contains "$profile" '/run/xpa020/tls/server.crt' "TLS edge lacks its runtime certificate"
assert_contains "$tls_proxy" 'ssl_protocols TLSv1.3' "TLS edge does not require TLS 1.3"
assert_contains "$tls_proxy" 'proxy_pass http://127.0.0.1:8080' \
  "TLS edge does not terminate into the loopback Platform listener"

for subject in \
  'evt.ai-archive.chatgpt.operation.reported.v1' \
  'evt.ai-archive.claude.operation.reported.v1'
do
  assert_contains "$runner" "$subject" "runner does not generate secured permission for $subject"
done
assert_contains "$runner" 'merge-base --is-ancestor' "runner does not require published revisions"
assert_contains "$runner" '^[0-9a-f]{40}$' "runner does not require full SHA inputs"
assert_contains "$runner" 'status --porcelain' "runner does not refuse dirty source checkouts"
assert_contains "$runner" 'fetch --quiet origin main' "runner does not refresh origin/main"
if rg --quiet 'ALLOW_DIRTY|ALLOW_UNPUBLISHED' "$runner"; then
  fail "XPA-020 runner offers an override around exact clean published inputs"
fi
assert_contains "$runner" 'down --volumes --remove-orphans' "runner lacks exact teardown"
assert_contains "$runner" 'run_macos_system_host' "runner lacks the macOS production-graph host phase"
assert_contains "$runner" 'openssl req' "runner does not generate its task-only TLS authority"
assert_contains "$runner" 'security create-keychain' "runner does not isolate macOS trust and credentials"
assert_contains "$runner" 'security default-keychain' "runner does not isolate the default Keychain"
assert_contains "$runner" 'security delete-keychain' "runner does not delete its exact task Keychain"
assert_contains "$runner" 'restore_keychain_search' "runner does not restore the Keychain search list"
assert_contains "$runner" 'RATATOSKR_XPA020_KEYCHAIN_SERVICE' \
  "runner does not pass a unique credential-service namespace"
assert_contains "$runner" 'RATATOSKR_XPA020_SUPPORT_DIR' \
  "runner does not pass a unique support namespace"
assert_contains "$runner" '.package(path: exportAgentContext)' \
  "system host package is not generated against the exact Export Agent checkout"
assert_contains "$system_host" 'import AgentCore' "system host does not use the production AgentCore graph"
assert_contains "$system_host" 'OperationalAgentRuntime' \
  "system host does not compose the production operational runtime"
assert_contains "$nkey_generator" 'nkeys.CreateUser' "runtime NKey generator does not create user seeds"
assert_contains "$runner" 'go mod tidy' \
  "runner does not materialize checksums for its pinned NKey generator dependency"

validate_exit_line=$(grep -nF "if [[ \"\$mode\" == --validate ]]" "$runner" | cut -d: -f1)
keychain_setup_line=$(grep -n '^setup_keychain$' "$runner" | cut -d: -f1)
[[ "$validate_exit_line" -lt "$keychain_setup_line" ]] || \
  fail "validation mode mutates the user Keychain before exiting"

for assertion in \
  raw_receipt_is_nonterminal \
  interrupted_transfer_reuses_operation \
  both_provider_imports_are_terminal \
  duplicate_bytes_do_not_duplicate_import \
  evidence_is_privacy_bounded
do
  assert_contains "$runner" "$assertion" "runner lacks system assertion $assertion"
done

for marker in chatgpt claude conversations.json projects.json user.json users.json; do
  assert_contains "$fixture_builder" "$marker" "fixture builder lacks $marker evidence"
done

for field in \
  'Contracts revision' 'Platform revision' 'ChatGPT revision' 'Claude revision' \
  'Export Agent revision' 'Workspace revision' 'Source boundary' 'Compose SHA-256' \
  'Raw receipt' 'Interrupted resume' 'ChatGPT terminal summary' 'Claude terminal summary' \
  'Duplicate suppression' 'Privacy scan' 'Teardown' 'Apple notarization' 'Clean Mac'
do
  assert_contains "$evidence_summary" "$field" "evidence omits $field"
done

if rg --quiet --hidden -g '!export_agent_product_profile_test.sh' \
  '(BEGIN [A-Z ]*PRIVATE KEY|\bSU[A-Z2-7]{20,}|Bearer [A-Za-z0-9._-]+)' \
  "$profile" "$runner" "$fixture_builder" "$database_seed" "$evidence_summary" \
  "$tls_proxy" "$system_host" "$nkey_generator"; then
  fail "profile assets contain credential material"
fi

printf 'Export Agent product profile contract: PASS\n'
