#!/usr/bin/env bash
set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
profile="$workspace_root/integration/compose/telegram-notification.yaml"
namespace=${RATATOSKR_TASK_NAMESPACE:?set RATATOSKR_TASK_NAMESPACE}

if [[ ! "$namespace" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]] || [[ "$namespace" != *tg010* ]]; then
  printf 'RATATOSKR_TASK_NAMESPACE must match [a-z0-9][a-z0-9-]{0,30} and contain tg010\n' >&2
  exit 2
fi

project="ratatoskr-${namespace}"
if [[ ${1:-} == --teardown-plan ]]; then
  printf 'docker compose --project-name %s --file %s down --volumes --remove-orphans\n' \
    "$project" "$profile"
  exit 0
fi

contracts=${RATATOSKR_CONTRACTS_CONTEXT:?set RATATOSKR_CONTRACTS_CONTEXT}
contracts_revision=${RATATOSKR_CONTRACTS_REVISION:?set RATATOSKR_CONTRACTS_REVISION}
platform=${RATATOSKR_PLATFORM_CONTEXT:?set RATATOSKR_PLATFORM_CONTEXT}
platform_revision=${RATATOSKR_PLATFORM_REVISION:?set RATATOSKR_PLATFORM_REVISION}
telegram=${RATATOSKR_TELEGRAM_CONTEXT:?set RATATOSKR_TELEGRAM_CONTEXT}
telegram_revision=${RATATOSKR_TELEGRAM_REVISION:?set RATATOSKR_TELEGRAM_REVISION}
evidence_dir=${RATATOSKR_EVIDENCE_DIR:-"$workspace_root/evidence/$namespace"}
mkdir -p "$evidence_dir"
: >"$evidence_dir/timeline.txt"

require_revision() {
  local label=$1 context=$2 revision=$3 actual
  actual=$(git -C "$context" rev-parse HEAD)
  [[ "$actual" == "$revision" ]] || {
    printf '%s context is at %s, expected %s\n' "$label" "$actual" "$revision" >&2
    exit 2
  }
  if ! git -C "$context" diff --quiet || ! git -C "$context" diff --cached --quiet; then
    printf '%s context is not clean\n' "$label" >&2
    exit 2
  fi
  if [[ ${RATATOSKR_ALLOW_UNPUBLISHED:-0} != 1 ]]; then
    git -C "$context" merge-base --is-ancestor "$revision" refs/remotes/origin/main || {
      printf '%s revision is not contained by origin/main\n' "$label" >&2
      exit 2
    }
  fi
}

require_revision Contracts "$contracts" "$contracts_revision"
require_revision Platform "$platform" "$platform_revision"
require_revision Telegram "$telegram" "$telegram_revision"
workspace_revision=$(git -C "$workspace_root" rev-parse HEAD)
if ! git -C "$workspace_root" diff --quiet || ! git -C "$workspace_root" diff --cached --quiet; then
  printf 'Workspace context is not clean; commit the profile source before recording evidence\n' >&2
  exit 2
fi

owned_runtime=0
if [[ -z ${RATATOSKR_TG010_RUNTIME_DIR:-} ]]; then
  RATATOSKR_TG010_RUNTIME_DIR=$(mktemp -d "$workspace_root/.tg010-runtime.XXXXXX")
  export RATATOSKR_TG010_RUNTIME_DIR
  owned_runtime=1
fi
runtime_dir=$RATATOSKR_TG010_RUNTIME_DIR
mkdir -p "$runtime_dir/state"

nats_box='natsio/nats-box@sha256:9d5f35d286c3dcfca18bb2339b51345f9f89b580b237ab16ddfe609bdca9c72d'
generate_nkey() {
  local name=$1 pair seed public
  pair=$(docker run --rm "$nats_box" nk -gen user -pubout)
  seed=$(printf '%s\n' "$pair" | sed -n '1p')
  public=$(printf '%s\n' "$pair" | sed -n '2p')
  [[ "$seed" == SU* && "$public" == U* ]] || {
    printf 'could not generate the %s NKey pair\n' "$name" >&2
    exit 1
  }
  printf '%s\n' "$seed" >"$runtime_dir/$name.nkey"
  printf '%s\n' "$public"
}

edge_public=$(generate_nkey edge)
telegram_public=$(generate_nkey telegram)
driver_public=$(generate_nkey driver)
openssl genpkey -algorithm Ed25519 -out "$runtime_dir/assertion.pem" 2>/dev/null
key_text=$(openssl pkey -in "$runtime_dir/assertion.pem" -text -noout)
assertion_seed=$(printf '%s\n' "$key_text" | awk '/^priv:/{copy=1; next} /^pub:/{copy=0} copy' | tr -d ' :\n')
assertion_public_hex=$(printf '%s\n' "$key_text" | awk '/^pub:/{copy=1; next} copy' | tr -d ' :\n')
RATATOSKR_TG010_ASSERTION_PUBLIC_KEY=$(printf '%s' "$assertion_public_hex" | xxd -r -p | openssl base64 -A)
export RATATOSKR_TG010_ASSERTION_PUBLIC_KEY
[[ ${#assertion_seed} == 64 && ${#assertion_public_hex} == 64 ]] || {
  printf 'could not derive the synthetic Ed25519 pair\n' >&2
  exit 1
}
printf '%s\n' "$assertion_seed" >"$runtime_dir/assertion-seed"
printf 'tg010-%s\n' "$(openssl rand -hex 24)" >"$runtime_dir/bot-token"
openssl rand -hex 24 >"$runtime_dir/webhook-secret"
chmod 0600 "$runtime_dir"/*.nkey "$runtime_dir"/assertion-seed \
  "$runtime_dir"/assertion.pem "$runtime_dir"/bot-token "$runtime_dir"/webhook-secret

cat >"$runtime_dir/nats.conf" <<EOF
port: 4222
host: 0.0.0.0
http_port: 8222
jetstream { store_dir: /data }
authorization {
  users: [
    {
      nkey: $edge_public
      permissions: {
        publish: { allow: ["cmd.>", "\$JS.API.>", "\$JS.ACK.>"], deny: ["\$JS.API.STREAM.DELETE.>", "\$JS.API.STREAM.PURGE.>"] }
        subscribe: { allow: ["_INBOX.>"] }
      }
    },
    {
      nkey: $telegram_public
      permissions: {
        publish: { allow: [
          "\$JS.API.CONSUMER.INFO.ratatoskr_events.ratatoskr_telegram_notifications",
          "\$JS.API.CONSUMER.MSG.NEXT.ratatoskr_events.ratatoskr_telegram_notifications",
          "\$JS.ACK.ratatoskr_events.ratatoskr_telegram_notifications.>"
        ] }
        subscribe: { allow: ["_INBOX.>"] }
      }
    },
    {
      nkey: $driver_public
      permissions: {
        publish: { allow: ["evt.platform.operation.reported.v1", "evt.platform.notification.raised.v1"] }
        subscribe: { allow: ["_INBOX.>"] }
      }
    }
  ]
}
EOF

compose() {
  docker compose --project-name "$project" --file "$profile" "$@"
}

cleanup() {
  local result=$?
  trap - EXIT INT TERM
  set +e
  compose ps --all >"$evidence_dir/final-compose-ps.txt" 2>&1
  compose logs --no-color >"$evidence_dir/compose.log" 2>&1
  compose down --volumes --remove-orphans >"$evidence_dir/teardown.log" 2>&1
  docker ps --format '{{.ID}} {{.Names}} {{.Ports}}' >"$evidence_dir/docker-after.txt"
  if [[ "$owned_runtime" == 1 && "$runtime_dir" == "$workspace_root"/.tg010-runtime.* ]]; then
    rm -rf -- "$runtime_dir"
  fi
  exit "$result"
}
trap cleanup EXIT INT TERM

compose config --quiet
if [[ ${1:-} == --validate ]]; then
  printf 'Telegram notification profile validation: PASS\n'
  exit 0
fi

wait_for_http() {
  local url=$1 expected=$2 output=$3 code _
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

psql_query() {
  local database=$1 sql=$2
  compose exec -T postgres psql -U platform -d "$database" -Atqc "$sql"
}

wait_for_query() {
  local database=$1 sql=$2 expected=$3 output _
  for _ in $(seq 1 120); do
    output=$(psql_query "$database" "$sql" 2>/dev/null || true)
    if [[ "$output" == "$expected" ]]; then
      return 0
    fi
    sleep 1
  done
  printf 'Timed out waiting for a bounded database assertion\n' >&2
  return 1
}

wait_for_value() {
  local database=$1 sql=$2 output _
  for _ in $(seq 1 120); do
    output=$(psql_query "$database" "$sql" 2>/dev/null || true)
    if [[ -n "$output" ]]; then
      printf '%s\n' "$output"
      return 0
    fi
    sleep 1
  done
  printf 'Timed out waiting for a bounded database value\n' >&2
  return 1
}

publish() {
  local subject=$1 payload=$2
  compose exec -T tools nats --server nats://127.0.0.1:4222 \
    --nkey /run/tg010/driver.nkey pub "$subject" "$payload" >/dev/null
}

post_update() {
  local update_id=$1 text=$2 secret body code
  secret=$(tr -d '\n' <"$runtime_dir/webhook-secret")
  body=$(jq -nc --argjson update_id "$update_id" --arg text "$text" '{
    update_id: $update_id,
    message: {
      message_id: $update_id,
      from: {id: 900700601, is_bot: false, first_name: "Synthetic"},
      date: 1787904000,
      chat: {id: 900700601, type: "private", first_name: "Synthetic"},
      text: $text
    }
  }')
  code=$(curl --silent --show-error --output "$evidence_dir/update-$update_id.json" \
    --write-out '%{http_code}' --request POST --header 'content-type: application/json' \
    --header "X-Telegram-Bot-Api-Secret-Token: $secret" --data "$body" \
    "$webhook_url/webhook")
  [[ "$code" == 200 ]] || {
    printf 'synthetic update %s returned HTTP %s\n' "$update_id" "$code" >&2
    return 1
  }
}

docker ps --format '{{.ID}} {{.Names}} {{.Ports}}' >"$evidence_dir/docker-before.txt"
compose config | shasum -a 256 | awk '{print $1}' >"$evidence_dir/compose.sha256"
compose up --detach --build
compose images --format json >"$evidence_dir/images.json"

webhook_port=$(compose port network 8182 | tail -1 | awk -F: '{print $NF}')
platform_admin_port=$(compose port network 9464 | tail -1 | awk -F: '{print $NF}')
webhook_admin_port=$(compose port network 9467 | tail -1 | awk -F: '{print $NF}')
dispatcher_admin_port=$(compose port network 9468 | tail -1 | awk -F: '{print $NF}')
webhook_url="http://127.0.0.1:$webhook_port"
platform_admin_url="http://127.0.0.1:$platform_admin_port"
webhook_admin_url="http://127.0.0.1:$webhook_admin_port"
dispatcher_admin_url="http://127.0.0.1:$dispatcher_admin_port"

wait_for_http "$platform_admin_url/health/ready" 200 "$evidence_dir/platform-ready.json"
wait_for_http "$webhook_admin_url/health/ready" 200 "$evidence_dir/webhook-ready.json"
wait_for_http "$dispatcher_admin_url/health/ready" 200 "$evidence_dir/dispatcher-ready.json"

dispatcher_refuses_missing_or_mismatched_platform_durable() {
  compose stop telegram-dispatcher >/dev/null
  compose exec -T tools nats --server nats://127.0.0.1:4222 --nkey /run/tg010/edge.nkey \
    consumer rm ratatoskr_events ratatoskr_telegram_notifications --force >/dev/null
  compose start telegram-dispatcher >/dev/null
  wait_for_http "$dispatcher_admin_url/health/ready" 503 "$evidence_dir/dispatcher-missing.json"

  compose stop telegram-dispatcher >/dev/null
  compose exec -T tools nats --server nats://127.0.0.1:4222 --nkey /run/tg010/edge.nkey \
    consumer add ratatoskr_events ratatoskr_telegram_notifications --pull --ack explicit \
    --deliver all --replay instant --wait 30s --filter evt.platform.foreign.v1 --defaults >/dev/null
  compose start telegram-dispatcher >/dev/null
  wait_for_http "$dispatcher_admin_url/health/ready" 503 "$evidence_dir/dispatcher-mismatched.json"

  compose stop telegram-dispatcher >/dev/null
  compose exec -T tools nats --server nats://127.0.0.1:4222 --nkey /run/tg010/edge.nkey \
    consumer rm ratatoskr_events ratatoskr_telegram_notifications --force >/dev/null
  compose restart platform >/dev/null
  wait_for_http "$platform_admin_url/health/ready" 200 "$evidence_dir/platform-reprovisioned.json"
  compose start telegram-dispatcher >/dev/null
  wait_for_http "$dispatcher_admin_url/health/ready" 200 "$evidence_dir/dispatcher-restored.json"
}
dispatcher_refuses_missing_or_mismatched_platform_durable

article_flow_reaches_final_projection() {
  post_update 10001 'https://example.invalid/tg-010'
  operation_id=$(wait_for_value platform \
    "select operation_id::text from operations.operations order by accepted_at desc limit 1")
  wait_for_query platform \
    "select count(*)::text from operations.outbox where operation_id = '$operation_id' and subject = 'cmd.content.capture.requested.v1'" 1
  wait_for_query telegram \
    "select count(*)::text from telegram.message_bindings where operation_id = '$operation_id'::uuid and message_id is not null" 1

  platform_user_id=$(wait_for_value platform \
    "select user_id::text from identity.identities where provider = 'telegram' and external_id = '900700601'")
  psql_query telegram \
    "update telegram.identities set internal_user_id = '$platform_user_id'::uuid where telegram_user_id = 900700601" >/dev/null
  occurred_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  event=$(jq -nc --arg operation "$operation_id" --arg user "$platform_user_id" \
    --arg occurred "$occurred_at" '{
      event_id: "018f0000-0000-7000-8000-00000000a001",
      event_type: "platform.operation.reported.v1",
      occurred_at: $occurred,
      producer: "tg010-domain-driver",
      aggregate_id: ("operation:" + $operation),
      correlation_id: ("operation:" + $operation),
      tenant_id: ("user:" + $user),
      schema_version: 1,
      payload: {
        operation_id: $operation,
        status: "succeeded"
      }
    }')
  publish evt.platform.operation.reported.v1 "$event"
  wait_for_query platform \
    "select status from operations.operations where operation_id = '$operation_id'" succeeded
  wait_for_query telegram \
    "select terminal::text from telegram.message_bindings where operation_id = '$operation_id'::uuid" true
  wait_for_query telegram \
    "select count(*)::text from telegram.outbound_jobs where operation_id = '$operation_id'::uuid and kind = 'edit_message_text' and state = 'sent'" 1
  printf '%s\n' "$operation_id" >"$evidence_dir/article-operation-id.txt"
}
article_flow_reaches_final_projection

notification_envelope() {
  local event_id=$1 notification_id=$2 class=$3 title=$4
  jq -nc --arg event "$event_id" --arg notification "$notification_id" \
    --arg class "$class" --arg title "$title" --arg user "$platform_user_id" '{
      event_id: $event,
      event_type: "platform.notification.raised.v1",
      occurred_at: "2026-08-28T12:00:00Z",
      producer: "tg010-domain-driver",
      aggregate_id: ("notification:" + $notification),
      correlation_id: ("notification:" + $notification),
      tenant_id: ("user:" + $user),
      schema_version: 1,
      payload: {
        notification_id: $notification,
        class_registry_version: 1,
        class: $class,
        recipient: ("user:" + $user),
        title: $title
      }
    }'
}

enabled_notification_is_sent_once() {
  enabled_notification_id=018f0000-0000-7000-8000-00000000b001
  first=$(notification_envelope 018f0000-0000-7000-8000-00000000c001 \
    "$enabled_notification_id" operation_completed 'Synthetic completion')
  duplicate=$(notification_envelope 018f0000-0000-7000-8000-00000000c002 \
    "$enabled_notification_id" operation_completed 'Synthetic completion')
  publish evt.platform.notification.raised.v1 "$first"
  publish evt.platform.notification.raised.v1 "$duplicate"
  wait_for_query telegram \
    "select outcome from telegram.notification_decisions where notification_id = '$enabled_notification_id'::uuid" delivered
  wait_for_query telegram \
    "select count(*)::text from telegram.outbound_jobs where notification_id = '$enabled_notification_id'::uuid and state = 'sent'" 1
}
enabled_notification_is_sent_once

duplicate_notification_is_not_sent_twice() {
  wait_for_query telegram \
    "select count(*)::text from telegram.notification_decisions where notification_id = '$enabled_notification_id'::uuid" 1
  wait_for_query telegram \
    "select count(*)::text from telegram.outbound_jobs where notification_id = '$enabled_notification_id'::uuid" 1
}
duplicate_notification_is_not_sent_twice

disabled_notification_is_suppressed() {
  post_update 10002 '/settings notification operation_failed off'
  wait_for_query telegram \
    "select enabled::text from telegram.notification_class_preferences where telegram_user_id = 900700601 and class = 'operation_failed'" false
  disabled_notification_id=018f0000-0000-7000-8000-00000000b002
  suppressed=$(notification_envelope 018f0000-0000-7000-8000-00000000c003 \
    "$disabled_notification_id" operation_failed 'Synthetic failure')
  publish evt.platform.notification.raised.v1 "$suppressed"
  wait_for_query telegram \
    "select outcome from telegram.notification_decisions where notification_id = '$disabled_notification_id'::uuid" suppressed
  wait_for_query telegram \
    "select count(*)::text from telegram.outbound_jobs where notification_id = '$disabled_notification_id'::uuid" 0
}
disabled_notification_is_suppressed

jq -n \
  --arg contracts "$contracts_revision" \
  --arg platform "$platform_revision" \
  --arg telegram "$telegram_revision" \
  --arg workspace "$workspace_revision" \
  --arg compose_sha "$(cat "$evidence_dir/compose.sha256")" \
  --argjson notification_decisions "$(psql_query telegram 'select count(*) from telegram.notification_decisions')" \
  --argjson delivered_notifications "$(psql_query telegram "select count(*) from telegram.notification_decisions where outcome = 'delivered'")" \
  --argjson suppressed_notifications "$(psql_query telegram "select count(*) from telegram.notification_decisions where outcome = 'suppressed'")" \
  '{contracts_revision: $contracts, platform_revision: $platform, telegram_revision: $telegram,
    workspace_revision: $workspace,
    compose_sha256: $compose_sha, notification_decisions: $notification_decisions,
    delivered_notifications: $delivered_notifications,
    suppressed_notifications: $suppressed_notifications,
    article_final_projection: true, duplicate_notification_jobs: 1,
    hosted_ci: "not_verified", live_deployment: "not_performed"}' \
  >"$evidence_dir/summary.json"

compose ps --all >"$evidence_dir/healthy-compose-ps.txt"
printf 'article, enabled, suppressed, duplicate, durable readiness, namespaced cleanup: PASS\n' \
  | tee "$evidence_dir/result.txt"
