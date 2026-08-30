#!/usr/bin/env bash
set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
profile="$workspace_root/integration/compose/github-fleet-bus.yaml"
namespace=${RATATOSKR_TASK_NAMESPACE:-}
project="ratatoskr-${namespace}"

die() {
  printf 'GHB-017: %s\n' "$1" >&2
  exit 1
}

[[ -n "$namespace" ]] || die 'RATATOSKR_TASK_NAMESPACE is required'
[[ "$namespace" =~ ^[a-z0-9][a-z0-9-]{2,47}$ ]] || die 'task namespace is invalid'
[[ "$namespace" != *ghb017* ]] && die 'task namespace must contain ghb017'

compose=(docker compose --project-name "$project" --file "$profile")
if [[ ${1:-} == --teardown-plan ]]; then
  printf 'docker compose --project-name %s --file %s down --volumes --remove-orphans\n' \
    "$project" "$profile"
  exit 0
fi

for command in docker git jq openssl shasum curl; do
  command -v "$command" >/dev/null || die "$command is required"
done
for name in RATATOSKR_PLATFORM_CONTEXT RATATOSKR_PLATFORM_REVISION \
  RATATOSKR_GITHUB_CONTEXT RATATOSKR_GITHUB_REVISION RATATOSKR_GHB017_RUNTIME_DIR
do
  [[ -n ${!name:-} ]] || die "$name is required"
done

platform_context=$(cd "$RATATOSKR_PLATFORM_CONTEXT" && pwd)
github_context=$(cd "$RATATOSKR_GITHUB_CONTEXT" && pwd)
runtime_dir=$(cd "$RATATOSKR_GHB017_RUNTIME_DIR" && pwd -P)
evidence_output=${RATATOSKR_GHB017_EVIDENCE_OUTPUT:-$runtime_dir/evidence.env}
allow_unpublished=${RATATOSKR_ALLOW_UNPUBLISHED:-0}

verify_checkout() {
  local checkout=$1 expected=$2 label=$3
  [[ $(git -C "$checkout" rev-parse HEAD) == "$expected" ]] || die "$label checkout is not at $expected"
  [[ -z $(git -C "$checkout" status --porcelain) ]] || die "$label checkout is dirty"
  git -C "$checkout" cat-file -e "$expected^{commit}" || die "$label revision is not a commit"
  if ! git -C "$checkout" merge-base --is-ancestor "$expected" refs/remotes/origin/main; then
    [[ "$allow_unpublished" == 1 ]] || die "$label revision is not published on origin/main"
  fi
}

verify_checkout "$platform_context" "$RATATOSKR_PLATFORM_REVISION" Platform
verify_checkout "$github_context" "$RATATOSKR_GITHUB_REVISION" GitHub
[[ -z $(git -C "$workspace_root" status --porcelain) ]] || die 'workspace checkout must be clean'
workspace_revision=$(git -C "$workspace_root" rev-parse HEAD)

mkdir -p "$runtime_dir/state"
chmod 700 "$runtime_dir"
rm -f "$runtime_dir"/*.nkey "$runtime_dir/nats.conf" "$runtime_dir/credential-key"

nats_box='natsio/nats-box@sha256:9d5f35d286c3dcfca18bb2339b51345f9f89b580b237ab16ddfe609bdca9c72d'
new_nkey() {
  local label=$1 pair seed public
  pair=$(docker run --rm "$nats_box" nk -gen user -pubout)
  seed=$(printf '%s\n' "$pair" | sed -n '1p')
  public=$(printf '%s\n' "$pair" | sed -n '2p')
  printf '%s\n' "$seed" >"$runtime_dir/$label.nkey"
  chmod 600 "$runtime_dir/$label.nkey"
  printf '%s' "$public"
}

platform_public=$(new_nkey platform)
github_public=$(new_nkey github)
peers_public=$(new_nkey peers)
openssl rand -hex 32 >"$runtime_dir/credential-key"
chmod 600 "$runtime_dir/credential-key"

cat >"$runtime_dir/nats.conf" <<EOF
host: 0.0.0.0
port: 4222
http_port: 8222
jetstream { store_dir: /data, max_file_store: 2147483648 }
authorization {
  users: [
    { nkey: "$platform_public", permissions: {
      publish: { allow: [">"], deny: ["\$JS.API.STREAM.DELETE.>", "\$JS.API.STREAM.PURGE.>", "\$JS.API.CONSUMER.DELETE.>"] },
      subscribe: { allow: [">"] }
    } },
    { nkey: "$github_public", permissions: {
      publish: { allow: [
        "evt.knowledge.repository_analysis.requested.v1", "cmd.vault.target.desired.v1",
        "\$JS.API.STREAM.INFO.ratatoskr_commands", "\$JS.API.STREAM.INFO.ratatoskr_events",
        "\$JS.API.CONSUMER.INFO.ratatoskr_commands.ratatoskr_github_sync",
        "\$JS.API.CONSUMER.INFO.ratatoskr_events.ratatoskr_github_analysis_completed",
        "\$JS.API.CONSUMER.INFO.ratatoskr_events.ratatoskr_github_analysis_failed",
        "\$JS.API.CONSUMER.INFO.ratatoskr_events.ratatoskr_github_vault_policy_ack",
        "\$JS.API.CONSUMER.MSG.NEXT.ratatoskr_commands.ratatoskr_github_sync",
        "\$JS.API.CONSUMER.MSG.NEXT.ratatoskr_events.ratatoskr_github_analysis_completed",
        "\$JS.API.CONSUMER.MSG.NEXT.ratatoskr_events.ratatoskr_github_analysis_failed",
        "\$JS.API.CONSUMER.MSG.NEXT.ratatoskr_events.ratatoskr_github_vault_policy_ack",
        "\$JS.ACK.ratatoskr_commands.>", "\$JS.ACK.ratatoskr_events.>"
      ] },
      subscribe: { allow: ["_INBOX.>"] }
    } },
    { nkey: "$peers_public", permissions: {
      publish: { allow: [
        "cmd.github.sync.requested.v1",
        "evt.knowledge.repository_analysis.completed.v1",
        "evt.knowledge.repository_analysis.failed.v1",
        "evt.vault.backup_policy.acknowledged.v1",
        "\$JS.API.STREAM.INFO.*", "\$JS.API.CONSUMER.INFO.*.*"
      ] },
      subscribe: { allow: ["_INBOX.>"] }
    } }
  ]
}
EOF

export RATATOSKR_PLATFORM_CONTEXT="$platform_context"
export RATATOSKR_GITHUB_CONTEXT="$github_context"
export RATATOSKR_GHB017_RUNTIME_DIR="$runtime_dir"

cleaned=0
cleanup() {
  local status=$?
  if [[ $cleaned -eq 0 ]]; then
    "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
    cleaned=1
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

wait_until() {
  local label=$1 command=$2 deadline=$((SECONDS + 90))
  until eval "$command"; do
    (( SECONDS < deadline )) || die "timed out waiting for $label"
    sleep 1
  done
}

db() {
  "${compose[@]}" exec -T postgres psql -v ON_ERROR_STOP=1 -U github -d github -Atqc "$1"
}

db_file() {
  "${compose[@]}" exec -T postgres psql -v ON_ERROR_STOP=1 -U github -d github
}

publish() {
  local subject=$1 payload=$2
  "${compose[@]}" exec -T peers nats --server nats://127.0.0.1:4222 \
    --nkey /run/ghb017/peers.nkey pub "$subject" "$payload" >/dev/null
}

nats_json() {
  "${compose[@]}" exec -T peers nats --server nats://127.0.0.1:4222 \
    --nkey /run/ghb017/peers.nkey "$@" --json
}

scheduled_sync_is_consumed_once() {
  local command_id=018f0000-0000-7000-8000-000000000921
  sync_envelope=$(jq -cn --arg id "$command_id" '{
    command_id:$id, command_type:"github.sync.requested.v1",
    requested_at:"2026-08-30T12:00:00Z",
    operation_id:"018f0000-0000-7000-8000-000000000922",
    tenant_id:"user:018f0000-0000-7000-8000-000000000901",
    correlation_id:"sched/github-sync/ghb017", idempotency_key:$id,
    payload:{account:"user:018f0000-0000-7000-8000-000000000901",mode:"full"}
  }')
  publish cmd.github.sync.requested.v1 "$sync_envelope"
  wait_until 'one consumed sync command' \
    "[[ \$(db \"select count(*) from github_catalog.inbox_events where message_id='$command_id' and state='consumed'\") == 1 ]]"
  wait_until 'two completed sync modes' \
    "[[ \$(db \"select count(*) from github_catalog.sync_runs where status='completed' and mode in ('full','star_lists')\") == 2 ]]"
  publish cmd.github.sync.requested.v1 "$sync_envelope"
  sleep 2
  [[ $(db "select count(*) from github_catalog.sync_runs") == 2 ]] || die 'duplicate sync performed a second effect'
  sync_result='one inbox identity; two expected full/star-list runs; duplicate produced zero runs'
}

knowledge_completion_and_failure_are_terminal() {
  db_file <"$workspace_root/integration/fixtures/github-fleet-bus-workflows.sql"
  wait_until 'two published Knowledge requests' \
    "[[ \$(db \"select count(*) from github_catalog.outbox_events where subject='evt.knowledge.repository_analysis.requested.v1' and published_at is not null\") == 2 ]]"
  wait_until 'one published Vault policy' \
    "[[ \$(db \"select count(*) from github_catalog.outbox_events where subject='cmd.vault.target.desired.v1' and published_at is not null\") == 1 ]]"

  completed=$(jq -cn '{
    event_id:"018f0000-0000-7000-8000-000000000931",
    event_type:"knowledge.repository_analysis.completed.v1",
    occurred_at:"2026-08-30T12:01:00Z",producer:"ratatoskr-knowledge",
    aggregate_id:"repository:018f0000-0000-7000-8000-000000000902",
    correlation_id:"operation:018f0000-0000-7000-8000-000000000941",
    tenant_id:"user:018f0000-0000-7000-8000-000000000901",schema_version:1,
    payload:{owner:"user:018f0000-0000-7000-8000-000000000901",
      repository_id:"018f0000-0000-7000-8000-000000000902",
      github_repository_numeric_id:99002,
      request_id:"018f0000-0000-7000-8000-000000000911",
      source_revision:{attributes_digest:{algorithm:"sha256",hex:("a"*64)},readme:{state:"absent",reason:"not_found"}},
      analysis_result_ref:"analysis:018f0000-0000-7000-8000-000000000951",
      completed_at:"2026-08-30T12:01:00Z"}}
  ')
  failed=$(jq -cn '{
    event_id:"018f0000-0000-7000-8000-000000000932",
    event_type:"knowledge.repository_analysis.failed.v1",
    occurred_at:"2026-08-30T12:01:01Z",producer:"ratatoskr-knowledge",
    aggregate_id:"repository:018f0000-0000-7000-8000-000000000903",
    correlation_id:"operation:018f0000-0000-7000-8000-000000000942",
    tenant_id:"user:018f0000-0000-7000-8000-000000000901",schema_version:1,
    payload:{owner:"user:018f0000-0000-7000-8000-000000000901",
      repository_id:"018f0000-0000-7000-8000-000000000903",
      github_repository_numeric_id:99003,
      request_id:"018f0000-0000-7000-8000-000000000912",
      source_revision:{attributes_digest:{algorithm:"sha256",hex:("b"*64)},readme:{state:"absent",reason:"not_found"}},
      failure_code:"dependency_unavailable",retryable:true,failed_at:"2026-08-30T12:01:01Z"}}
  ')
  publish evt.knowledge.repository_analysis.completed.v1 "$completed"
  publish evt.knowledge.repository_analysis.failed.v1 "$failed"
  wait_until 'terminal Knowledge outcomes' \
    "[[ \$(db \"select string_agg(status,',' order by request_id) from github_catalog.repository_analysis_requests where request_id in ('018f0000-0000-7000-8000-000000000911','018f0000-0000-7000-8000-000000000912')\") == completed,failed ]]"
  knowledge_result='two requested events published; completion and failure each resolved one request'
}

vault_acknowledgment_is_consumed_once() {
  policy_version=$(db 'select max(policy_version) from github_catalog.backup_policy_publications')
  vault_ack=$(jq -cn --argjson version "$policy_version" '{
    event_id:"018f0000-0000-7000-8000-000000000933",
    event_type:"vault.backup_policy.acknowledged.v1",
    occurred_at:"2026-08-30T12:01:02Z",producer:"ratatoskr-vault",
    aggregate_id:("backup_policy:"+($version|tostring)),
    correlation_id:"operation:018f0000-0000-7000-8000-000000000943",
    schema_version:1,payload:{acknowledged_policy_version:$version,outcome:"accepted",
      last_applied_policy_version:($version-1)}}
  ')
  publish evt.vault.backup_policy.acknowledged.v1 "$vault_ack"
  wait_until 'Vault acknowledgment' \
    "[[ \$(db \"select count(*) from github_catalog.backup_policy_feedback where acknowledged_policy_version=$policy_version and outcome='accepted'\") == 1 ]]"
  publish evt.vault.backup_policy.acknowledged.v1 "$vault_ack"
  sleep 2
  [[ $(db 'select count(*) from github_catalog.backup_policy_feedback') == 1 ]] || die 'Vault duplicate performed a second effect'
  vault_result="policy version $policy_version acknowledged once under duplicate delivery"
}

broker_ack_before_mark_replays_identical_bytes() {
  local id before_bytes before_count after_count before_attempt
  id=$(db "select message_id from github_catalog.outbox_events where subject='evt.knowledge.repository_analysis.requested.v1' order by created_at limit 1")
  before_bytes=$(db "select encode(envelope,'hex') from github_catalog.outbox_events where message_id='$id'")
  before_attempt=$(db "select attempt_count from github_catalog.outbox_events where message_id='$id'")
  before_count=$(nats_json stream info ratatoskr_events | jq -r '.state.messages')
  db "update github_catalog.outbox_events set published_at=null where message_id='$id'"
  wait_until 'outbox replay confirmation' \
    "[[ \$(db \"select (published_at is not null)::int from github_catalog.outbox_events where message_id='$id'\") == 1 ]]"
  after_count=$(nats_json stream info ratatoskr_events | jq -r '.state.messages')
  [[ $(db "select encode(envelope,'hex') from github_catalog.outbox_events where message_id='$id'") == "$before_bytes" ]] || die 'outbox replay changed envelope bytes'
  [[ "$after_count" == "$before_count" ]] || die 'stable Nats-Msg-Id did not collapse replay'
  [[ $(db "select attempt_count from github_catalog.outbox_events where message_id='$id'") -gt "$before_attempt" ]] || die 'outbox replay was not attempted'
  replay_result="message $id replayed byte-identically; stream count stayed $before_count"
}

inbox_commit_before_ack_absorbs_duplicate() {
  "${compose[@]}" stop --timeout 12 github >/dev/null
  publish evt.knowledge.repository_analysis.completed.v1 "$completed"
  "${compose[@]}" start github >/dev/null
  wait_until 'GitHub readiness after duplicate restart' "curl -fsS http://127.0.0.1:$operator_port/ready >/dev/null"
  wait_until 'duplicate completion consumed' \
    "[[ \$(db \"select count(*) from github_catalog.inbox_events where message_id='018f0000-0000-7000-8000-000000000931' and state='consumed'\") == 1 ]]"
  [[ $(db "select count(*) from github_catalog.repository_analysis_links where request_id='018f0000-0000-7000-8000-000000000911'") == 1 ]] || die 'duplicate completion created a second link'
  inbox_restart_result='committed completion replayed after restart and remained one terminal effect'
}

all_durable_ack_floors_advance() {
  local durable stream floor floors=''
  for durable in ratatoskr_github_sync ratatoskr_github_analysis_completed \
    ratatoskr_github_analysis_failed ratatoskr_github_vault_policy_ack
  do
    if [[ "$durable" == ratatoskr_github_sync ]]; then stream=ratatoskr_commands; else stream=ratatoskr_events; fi
    floor=$(nats_json consumer info "$stream" "$durable" | jq -r '.ack_floor.stream_seq')
    [[ "$floor" =~ ^[1-9][0-9]*$ ]] || die "$durable acknowledgement floor did not advance"
    floors="${floors}${durable}=${floor};"
  done
  durable_floors=$floors
}

bounded_shutdown_preserves_readiness_truth() {
  curl -fsS "http://127.0.0.1:$operator_port/ready" >/dev/null
  local started elapsed status
  started=$(date +%s)
  "${compose[@]}" stop --timeout 12 github >/dev/null
  elapsed=$(( $(date +%s) - started ))
  (( elapsed <= 15 )) || die "GitHub shutdown exceeded 15 seconds ($elapsed)"
  status=$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$operator_port/ready" || true)
  [[ "$status" != 200 ]] || die 'readiness remained true after shutdown'
  "${compose[@]}" start github >/dev/null
  wait_until 'GitHub readiness after bounded shutdown' "curl -fsS http://127.0.0.1:$operator_port/ready >/dev/null"
  shutdown_result="SIGTERM completed in ${elapsed}s; readiness was unavailable; restart became ready"
}

printf 'GHB-017: building and starting %s\n' "$project"
"${compose[@]}" up --detach --build --wait --wait-timeout 900
operator_port=$("${compose[@]}" port network 9469 | awk -F: '{print $NF}')
domain_port=$("${compose[@]}" port network 8092 | awk -F: '{print $NF}')
[[ "$operator_port" =~ ^[0-9]+$ && "$domain_port" =~ ^[0-9]+$ ]] || die 'ephemeral ports were not allocated'
wait_until 'GitHub readiness' "curl -fsS http://127.0.0.1:$operator_port/ready >/dev/null"

db "insert into github_catalog.github_accounts (account_id,owner_ref,status) values ('018f0000-0000-7000-8000-000000000901','user:018f0000-0000-7000-8000-000000000901','reauthorization_required')"
printf 'synthetic-ghb017-pat\n' | "${compose[@]}" run --rm --no-deps -T github reconnect-pat 018f0000-0000-7000-8000-000000000901 >/dev/null

scheduled_sync_is_consumed_once
knowledge_completion_and_failure_are_terminal
vault_acknowledgment_is_consumed_once
broker_ack_before_mark_replays_identical_bytes
inbox_commit_before_ack_absorbs_duplicate
all_durable_ack_floors_advance
bounded_shutdown_preserves_readiness_truth

logs=$("${compose[@]}" logs --no-color)
for secret_file in platform.nkey github.nkey peers.nkey credential-key; do
  secret=$(tr -d '\n' <"$runtime_dir/$secret_file")
  [[ "$logs" != *"$secret"* ]] || die "$secret_file appeared in service logs"
done
[[ "$logs" != *synthetic-ghb017-pat* ]] || die 'synthetic PAT appeared in service logs'

compose_sha=$(shasum -a 256 "$profile" | awk '{print $1}')
image_id=$(docker image inspect --format '{{.Id}}' "ratatoskr-ghb017-github:$RATATOSKR_GITHUB_REVISION")
provider_requests=$(wc -l <"$runtime_dir/state/requests.jsonl" | tr -d ' ')
publication_counts=$(db "select subject||'='||count(*) from github_catalog.outbox_events where published_at is not null group by subject order by subject" | paste -sd ';' -)
inbox_counts=$(db "select subject||'='||count(*) from github_catalog.inbox_events where state in ('consumed','rejected') group by subject order by subject" | paste -sd ';' -)

cat >"$evidence_output" <<EOF
platform_revision=$RATATOSKR_PLATFORM_REVISION
github_revision=$RATATOSKR_GITHUB_REVISION
workspace_revision=$workspace_revision
compose_sha256=$compose_sha
platform_topology_source=crates/eventing/src/stream.rs@$RATATOSKR_PLATFORM_REVISION
github_image_id=$image_id
scheduled_sync=$sync_result
knowledge_request=$knowledge_result
vault_desired_policy=$vault_result
restart_recovery=$inbox_restart_result; $replay_result
durable_acknowledgement_floors=$durable_floors
bounded_shutdown=$shutdown_result
publication_counts=$publication_counts
inbox_counts=$inbox_counts
fake_provider_requests=$provider_requests
hosted_ci=unverified
live_deployment=unverified
live_github_provider=unverified
live_knowledge_or_vault=unverified
fixture_boundary=synthetic provider, identities, events, PAT and disposable PostgreSQL/NATS only
EOF

printf 'GHB-017: PASS; evidence=%s\n' "$evidence_output"
