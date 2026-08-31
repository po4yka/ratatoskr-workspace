#!/usr/bin/env bash
set -euo pipefail
umask 077

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
profile="$workspace_root/integration/compose/export-agent-product.yaml"
namespace=${RATATOSKR_TASK_NAMESPACE:?set RATATOSKR_TASK_NAMESPACE}
runtime_root=${RATATOSKR_XPA020_RUNTIME_DIR:?set RATATOSKR_XPA020_RUNTIME_DIR}
mode=${1:---compose-smoke}

if [[ ! "$namespace" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]]; then
  printf 'RATATOSKR_TASK_NAMESPACE must match [a-z0-9][a-z0-9-]{0,30}\n' >&2
  exit 2
fi
if [[ "$runtime_root" != /* || "$runtime_root" == / || "$runtime_root" == "$HOME" ]]; then
  printf 'RATATOSKR_XPA020_RUNTIME_DIR must be a bounded absolute directory\n' >&2
  exit 2
fi
case "$mode" in
  --validate|--compose-smoke|--system-assertions) ;;
  *) printf 'usage: %s [--validate|--compose-smoke|--system-assertions]\n' "$0" >&2; exit 2 ;;
esac

for command in docker git go openssl python3 rg security swift; do
  command -v "$command" >/dev/null || {
    printf 'required command is unavailable: %s\n' "$command" >&2
    exit 2
  }
done

require_revision() {
  local label=$1 context=$2 revision=$3 actual dirty
  [[ "$context" == /* && -d "$context/.git" || -f "$context/.git" ]] || {
    printf '%s context is not an absolute Git checkout\n' "$label" >&2
    exit 2
  }
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || {
    printf '%s revision must match ^[0-9a-f]{40}$\n' "$label" >&2
    exit 2
  }
  actual=$(git -C "$context" rev-parse HEAD)
  [[ "$actual" == "$revision" ]] || {
    printf '%s context is at %s, expected exact revision %s\n' "$label" "$actual" "$revision" >&2
    exit 2
  }
  dirty=$(git -C "$context" status --porcelain --untracked-files=all)
  [[ -z "$dirty" ]] || {
    printf '%s context is not clean\n' "$label" >&2
    exit 2
  }
  git -C "$context" fetch --quiet origin main
  git -C "$context" merge-base --is-ancestor "$revision" refs/remotes/origin/main || {
    printf '%s revision is not contained by refreshed origin/main\n' "$label" >&2
    exit 2
  }
}

require_revision Contracts \
  "${RATATOSKR_CONTRACTS_CONTEXT:?set RATATOSKR_CONTRACTS_CONTEXT}" \
  "${RATATOSKR_CONTRACTS_REVISION:?set RATATOSKR_CONTRACTS_REVISION}"
require_revision Platform \
  "${RATATOSKR_PLATFORM_CONTEXT:?set RATATOSKR_PLATFORM_CONTEXT}" \
  "${RATATOSKR_PLATFORM_REVISION:?set RATATOSKR_PLATFORM_REVISION}"
require_revision ChatGPT \
  "${RATATOSKR_CHATGPT_CONTEXT:?set RATATOSKR_CHATGPT_CONTEXT}" \
  "${RATATOSKR_CHATGPT_REVISION:?set RATATOSKR_CHATGPT_REVISION}"
require_revision Claude \
  "${RATATOSKR_CLAUDE_CONTEXT:?set RATATOSKR_CLAUDE_CONTEXT}" \
  "${RATATOSKR_CLAUDE_REVISION:?set RATATOSKR_CLAUDE_REVISION}"
require_revision Export-Agent \
  "${RATATOSKR_EXPORT_AGENT_CONTEXT:?set RATATOSKR_EXPORT_AGENT_CONTEXT}" \
  "${RATATOSKR_EXPORT_AGENT_REVISION:?set RATATOSKR_EXPORT_AGENT_REVISION}"
require_revision Workspace \
  "${RATATOSKR_WORKSPACE_CONTEXT:?set RATATOSKR_WORKSPACE_CONTEXT}" \
  "${RATATOSKR_WORKSPACE_REVISION:?set RATATOSKR_WORKSPACE_REVISION}"

mkdir -p "$runtime_root"
task_runtime=$(mktemp -d "$runtime_root/${namespace}.XXXXXX")
export RATATOSKR_XPA020_RUNTIME_DIR=$task_runtime
project="ratatoskr-${namespace}"
evidence_dir="$workspace_root/evidence/$namespace"
mkdir -p "$evidence_dir"
: >"$evidence_dir/timeline.txt"

original_default_keychain=
original_keychains=()
task_keychain=
keychain_password=

compose() {
  docker compose --project-name "$project" --file "$profile" "$@"
}

restore_keychain_search() {
  if ((${#original_keychains[@]} > 0)); then
    security list-keychains -d user -s "${original_keychains[@]}" >/dev/null
  fi
  if [[ -n "$original_default_keychain" ]]; then
    security default-keychain -d user -s "$original_default_keychain" >/dev/null
  fi
}

cleanup() {
  local status=$?
  set +e
  compose ps --all >"$evidence_dir/final-compose-ps.txt" 2>&1
  compose logs --no-color >"$evidence_dir/compose.log" 2>&1
  docker compose --project-name "$project" --file "$profile" \
    down --volumes --remove-orphans >"$evidence_dir/teardown.log" 2>&1
  restore_keychain_search
  if [[ -n "$task_keychain" && -f "$task_keychain" ]]; then
    security delete-keychain "$task_keychain" >/dev/null 2>&1
  fi
  if [[ "$task_runtime" == "$runtime_root"/* && -d "$task_runtime" ]]; then
    rm -rf -- "$task_runtime"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

generate_nkeys() {
  local generator="$task_runtime/nkey-generator"
  mkdir -p "$generator" "$task_runtime/nats"
  cp "$workspace_root/integration/fixtures/export-agent-product-nkeys.go" "$generator/main.go"
  cat >"$generator/go.mod" <<'EOF'
module ratatoskr.local/xpa020-nkeys

go 1.25

require github.com/nats-io/nkeys v0.4.10
EOF
  (cd "$generator" && GOWORK=off go run . "$task_runtime/nats")
  local edge chatgpt claude
  edge=$(tr -d '\r\n' <"$task_runtime/nats/edge.public")
  chatgpt=$(tr -d '\r\n' <"$task_runtime/nats/chatgpt.public")
  claude=$(tr -d '\r\n' <"$task_runtime/nats/claude.public")
  cat >"$task_runtime/nats/ratatoskr.conf" <<EOF
port: 4222
http_port: 8222
jetstream { store_dir: "/data" }
authorization {
  users: [
    {
      nkey: $edge
      permissions: {
        publish: {
          allow: ["cmd.>", "\$JS.API.>", "\$JS.ACK.>"]
          deny: ["\$JS.API.STREAM.DELETE.>", "\$JS.API.STREAM.PURGE.>"]
        }
        subscribe: { allow: ["_INBOX.>"] }
      }
    },
    {
      nkey: $chatgpt
      permissions: {
        publish: { allow: ["evt.ai-archive.chatgpt.operation.reported.v1"] }
        subscribe: { allow: ["_INBOX.>"] }
      }
    },
    {
      nkey: $claude
      permissions: {
        publish: { allow: ["evt.ai-archive.claude.operation.reported.v1"] }
        subscribe: { allow: ["_INBOX.>"] }
      }
    }
  ]
}
EOF
}

generate_tls() {
  mkdir -p "$task_runtime/tls"
  openssl req -x509 -newkey rsa:3072 -nodes -days 1 \
    -subj '/CN=Ratatoskr XPA-020 task CA' \
    -keyout "$task_runtime/tls/ca.key" -out "$task_runtime/tls/ca.crt" >/dev/null 2>&1
  openssl req -newkey rsa:3072 -nodes -subj '/CN=localhost' \
    -keyout "$task_runtime/tls/server.key" -out "$task_runtime/tls/server.csr" >/dev/null 2>&1
  cat >"$task_runtime/tls/server.ext" <<'EOF'
subjectAltName=DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth
keyUsage=digitalSignature,keyEncipherment
EOF
  openssl x509 -req -days 1 -sha256 \
    -in "$task_runtime/tls/server.csr" \
    -CA "$task_runtime/tls/ca.crt" -CAkey "$task_runtime/tls/ca.key" -CAcreateserial \
    -extfile "$task_runtime/tls/server.ext" -out "$task_runtime/tls/server.crt" >/dev/null 2>&1
}

setup_keychain() {
  local line
  while IFS= read -r line; do
    line=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*"?//; s/"?[[:space:]]*$//')
    [[ -n "$line" ]] && original_keychains+=("$line")
  done < <(security list-keychains -d user)
  original_default_keychain=$(security default-keychain -d user | tr -d '"' | xargs)
  task_keychain="$task_runtime/${namespace}.keychain-db"
  keychain_password=$(openssl rand -hex 24)
  security create-keychain -p "$keychain_password" "$task_keychain" >/dev/null
  security unlock-keychain -p "$keychain_password" "$task_keychain" >/dev/null
  security set-keychain-settings -lut 21600 "$task_keychain"
  security list-keychains -d user -s "$task_keychain" "${original_keychains[@]}" >/dev/null
  security default-keychain -d user -s "$task_keychain" >/dev/null
  security add-trusted-cert -r trustRoot -k "$task_keychain" "$task_runtime/tls/ca.crt" >/dev/null
}

run_macos_system_host() {
  local tls_port=$1 host_package="$task_runtime/system-host"
  mkdir -p "$host_package/Sources/XPA020SystemHost" "$task_runtime/inbox" "$task_runtime/support"
  cp "$workspace_root/integration/fixtures/ExportAgentProductSystemHost.swift" \
    "$host_package/Sources/XPA020SystemHost/main.swift"
  cat >"$host_package/Package.swift" <<'EOF'
// swift-tools-version: 6.0
import Foundation
import PackageDescription

let exportAgentContext = ProcessInfo.processInfo.environment["RATATOSKR_EXPORT_AGENT_CONTEXT"]!
let package = Package(
  name: "XPA020SystemHost",
  platforms: [.macOS(.v14)],
  dependencies: [.package(path: exportAgentContext)],
  targets: [
    .executableTarget(
      name: "XPA020SystemHost",
      dependencies: [.product(name: "AgentCore", package: "ratatoskr-export-agent")]
    )
  ]
)
EOF
  RATATOSKR_XPA020_PLATFORM_ORIGIN="https://127.0.0.1:$tls_port" \
  RATATOSKR_XPA020_INBOX_DIR="$task_runtime/inbox" \
  RATATOSKR_XPA020_SUPPORT_DIR="$task_runtime/support/$namespace" \
  RATATOSKR_XPA020_KEYCHAIN_SERVICE="com.po4yka.ratatoskr.xpa020.$namespace" \
  RATATOSKR_XPA020_OWNER_CREDENTIAL='xpa020-owner-fixture-credential' \
    swift run --package-path "$host_package" XPA020SystemHost \
      >"$evidence_dir/system-host.json"
}

# Task 7.3 owns these observed assertions. They are named here so the exact runner has one stable
# extension point, but deliberately fail until a real pre-fix RED and post-fix composed run exist.
raw_receipt_is_nonterminal() { return 2; }
interrupted_transfer_reuses_operation() { return 2; }
both_provider_imports_are_terminal() { return 2; }
duplicate_bytes_do_not_duplicate_import() { return 2; }
evidence_is_privacy_bounded() { return 2; }

generate_nkeys
generate_tls
setup_keychain
bash "$workspace_root/integration/fixtures/export-agent-product-fixtures.sh" "$task_runtime/inbox" \
  >"$evidence_dir/fixture-digests.txt"
compose config --quiet

if [[ "$mode" == --validate ]]; then
  printf 'Export Agent product profile validation: PASS\n'
  exit 0
fi

docker ps --format '{{.ID}} {{.Names}} {{.Ports}}' >"$evidence_dir/docker-before.txt"
compose up --detach --build
tls_port=$(compose port network 8443 | tail -1 | awk -F: '{print $NF}')
for _ in $(seq 1 120); do
  if curl --silent --show-error --fail --cacert "$task_runtime/tls/ca.crt" \
    "https://127.0.0.1:$tls_port/health/live" >"$evidence_dir/platform-live.json"; then
    break
  fi
  sleep 1
done
curl --silent --show-error --fail --cacert "$task_runtime/tls/ca.crt" \
  "https://127.0.0.1:$tls_port/health/live" >"$evidence_dir/platform-live.json"
run_macos_system_host "$tls_port"

if [[ "$mode" == --system-assertions ]]; then
  raw_receipt_is_nonterminal
  interrupted_transfer_reuses_operation
  both_provider_imports_are_terminal
  duplicate_bytes_do_not_duplicate_import
  evidence_is_privacy_bounded
fi

compose ps --all >"$evidence_dir/compose-ps.txt"
shasum -a 256 "$profile" >"$evidence_dir/compose-sha256.txt"
printf 'exact-revision compose and production-graph host smoke: PASS\n' | tee "$evidence_dir/result.txt"
