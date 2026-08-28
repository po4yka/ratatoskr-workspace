#!/usr/bin/env bash
set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
profile="$workspace_root/integration/compose/telegram-library.yaml"
namespace=${RATATOSKR_TASK_NAMESPACE:?set RATATOSKR_TASK_NAMESPACE}

if [[ ! "$namespace" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]] || [[ "$namespace" != *tg011* ]]; then
  printf 'RATATOSKR_TASK_NAMESPACE must match [a-z0-9][a-z0-9-]{0,30} and contain tg011\n' >&2
  exit 2
fi

project="ratatoskr-${namespace}"
if [[ ${1:-} == --teardown-plan ]]; then
  printf 'docker compose --project-name %s --file %s down --volumes --remove-orphans\n' \
    "$project" "$profile"
  exit 0
fi

knowledge=${RATATOSKR_KNOWLEDGE_CONTEXT:?set RATATOSKR_KNOWLEDGE_CONTEXT}
knowledge_revision=${RATATOSKR_KNOWLEDGE_REVISION:?set RATATOSKR_KNOWLEDGE_REVISION}
platform=${RATATOSKR_PLATFORM_CONTEXT:?set RATATOSKR_PLATFORM_CONTEXT}
platform_revision=${RATATOSKR_PLATFORM_REVISION:?set RATATOSKR_PLATFORM_REVISION}
telegram=${RATATOSKR_TELEGRAM_CONTEXT:?set RATATOSKR_TELEGRAM_CONTEXT}
telegram_revision=${RATATOSKR_TELEGRAM_REVISION:?set RATATOSKR_TELEGRAM_REVISION}
evidence_dir=${RATATOSKR_EVIDENCE_DIR:-"$workspace_root/evidence/$namespace"}
mkdir -p "$evidence_dir"
: >"$evidence_dir/timeline.txt"

source_boundary=published-clean
require_revision() {
  local label=$1 context=$2 revision=$3 actual
  actual=$(git -C "$context" rev-parse HEAD)
  [[ "$actual" == "$revision" ]] || {
    printf '%s context is at %s, expected %s\n' "$label" "$actual" "$revision" >&2
    exit 2
  }
  if ! git -C "$context" diff --quiet || ! git -C "$context" diff --cached --quiet \
      || [[ -n $(git -C "$context" ls-files --others --exclude-standard) ]]; then
    if [[ ${RATATOSKR_ALLOW_DIRTY_SOURCES:-0} != 1 ]]; then
      printf '%s context is not clean\n' "$label" >&2
      exit 2
    fi
    source_boundary=dirty-worktree-prepublication
  fi
  if [[ ${RATATOSKR_ALLOW_UNPUBLISHED:-0} != 1 ]]; then
    git -C "$context" merge-base --is-ancestor "$revision" refs/remotes/origin/main || {
      printf '%s revision is not contained by origin/main\n' "$label" >&2
      exit 2
    }
  elif [[ "$source_boundary" == published-clean ]]; then
    source_boundary=unpublished-local-revision
  fi
}

require_revision Knowledge "$knowledge" "$knowledge_revision"
require_revision Platform "$platform" "$platform_revision"
require_revision Telegram "$telegram" "$telegram_revision"
workspace_revision=$(git -C "$workspace_root" rev-parse HEAD)
if ! git -C "$workspace_root" diff --quiet || ! git -C "$workspace_root" diff --cached --quiet \
    || [[ -n $(git -C "$workspace_root" ls-files --others --exclude-standard) ]]; then
  if [[ ${RATATOSKR_ALLOW_DIRTY_SOURCES:-0} != 1 ]]; then
    printf 'Workspace context is not clean; commit the profile source before recording final evidence\n' >&2
    exit 2
  fi
  source_boundary=dirty-worktree-prepublication
fi

owned_runtime=0
if [[ -z ${RATATOSKR_TG011_RUNTIME_DIR:-} ]]; then
  RATATOSKR_TG011_RUNTIME_DIR=$(mktemp -d "$workspace_root/.tg011-runtime.XXXXXX")
  export RATATOSKR_TG011_RUNTIME_DIR
  owned_runtime=1
fi
runtime_dir=$RATATOSKR_TG011_RUNTIME_DIR
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
openssl genpkey -algorithm Ed25519 -out "$runtime_dir/assertion.pem" 2>/dev/null
key_text=$(openssl pkey -in "$runtime_dir/assertion.pem" -text -noout)
assertion_seed=$(printf '%s\n' "$key_text" | awk '/^priv:/{copy=1; next} /^pub:/{copy=0} copy' | tr -d ' :\n')
assertion_public_hex=$(printf '%s\n' "$key_text" | awk '/^pub:/{copy=1; next} copy' | tr -d ' :\n')
RATATOSKR_TG011_ASSERTION_PUBLIC_KEY=$(printf '%s' "$assertion_public_hex" | xxd -r -p | openssl base64 -A)
export RATATOSKR_TG011_ASSERTION_PUBLIC_KEY
[[ ${#assertion_seed} == 64 && ${#assertion_public_hex} == 64 ]] || {
  printf 'could not derive the synthetic Ed25519 pair\n' >&2
  exit 1
}
printf '%s\n' "$assertion_seed" >"$runtime_dir/assertion-seed"
printf 'tg011-%s\n' "$(openssl rand -hex 24)" >"$runtime_dir/bot-token"
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
  if docker ps --format '{{.Names}}' | rg --quiet "^${project}-"; then
    printf 'namespaced Compose resources survived teardown\n' >&2
    result=1
  fi
  if [[ "$owned_runtime" == 1 && "$runtime_dir" == "$workspace_root"/.tg011-runtime.* ]]; then
    rm -rf -- "$runtime_dir"
  fi
  exit "$result"
}
trap cleanup EXIT INT TERM

compose config --quiet
if [[ ${1:-} == --validate ]]; then
  printf 'Telegram library profile validation: PASS\n'
  exit 0
fi

wait_for_http() {
  local url=$1 expected=$2 output=$3 code _
  for _ in $(seq 1 180); do
    code=$(curl --silent --show-error --output "$output" --write-out '%{http_code}' "$url" || true)
    if [[ "$code" == "$expected" ]]; then
      return 0
    fi
    sleep 1
  done
  printf 'Timed out waiting for %s to return %s\n' "$url" "$expected" >&2
  return 1
}

wait_for_knowledge() {
  local output=$1 body _
  for _ in $(seq 1 180); do
    if body=$(compose exec -T network wget -q -O- http://127.0.0.1:8091/ready 2>/dev/null); then
      printf '%s\n' "$body" >"$output"
      return 0
    fi
    sleep 1
  done
  printf 'Timed out waiting for the loopback-only Knowledge readiness route\n' >&2
  return 1
}

psql_query() {
  local database=$1 sql=$2
  compose exec -T postgres psql -U platform -d "$database" -Atqc "$sql"
}

wait_for_query() {
  local database=$1 sql=$2 expected=$3 output _
  for _ in $(seq 1 180); do
    output=$(psql_query "$database" "$sql" 2>/dev/null || true)
    if [[ "$output" == "$expected" ]]; then
      return 0
    fi
    sleep 1
  done
  printf 'Timed out waiting for database assertion: %s\n' "$sql" >&2
  return 1
}

wait_for_value() {
  local database=$1 sql=$2 output _
  for _ in $(seq 1 180); do
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

wait_for_metric() {
  local capability=$1 expected=$2 output=$3 _
  for _ in $(seq 1 90); do
    curl --silent --show-error "$platform_admin_url/metrics" >"$output" || true
    if rg --quiet "platform_capability_available\\{capability=\"${capability}\"\\} ${expected}(\\.0)?$" "$output"; then
      return 0
    fi
    sleep 1
  done
  printf 'Timed out waiting for %s capability metric to become %s\n' "$capability" "$expected" >&2
  return 1
}

post_update() {
  local update_id=$1 text=$2 user_id chat_id secret body code
  user_id=${3:-900700601}
  chat_id=${4:-$user_id}
  secret=$(tr -d '\n' <"$runtime_dir/webhook-secret")
  body=$(jq -nc --argjson update_id "$update_id" --arg text "$text" \
    --argjson user_id "$user_id" --argjson chat_id "$chat_id" '{
      update_id: $update_id,
      message: {
        message_id: $update_id,
        from: {id: $user_id, is_bot: false, first_name: "Synthetic"},
        date: 1787904000,
        chat: {id: $chat_id, type: "private", first_name: "Synthetic"},
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
  wait_for_query telegram \
    "select state from telegram.updates where bot_id = 700100200 and update_id = $update_id" processed
}

wait_for_sent_jobs() {
  local expected=$1
  wait_for_query telegram "select count(*)::text from telegram.outbound_jobs where state = 'sent'" "$expected"
}

latest_sent_text() {
  psql_query telegram \
    "select payload->>'text' from telegram.outbound_jobs where state = 'sent' order by created_at desc, id desc limit 1"
}

docker ps --format '{{.ID}} {{.Names}} {{.Ports}}' >"$evidence_dir/docker-before.txt"
compose config | shasum -a 256 | awk '{print $1}' >"$evidence_dir/compose.sha256"
compose up --detach --build
compose images --format json >"$evidence_dir/images.json"

webhook_port=$(compose port network 8182 | tail -1 | awk -F: '{print $NF}')
platform_admin_port=$(compose port network 9464 | tail -1 | awk -F: '{print $NF}')
webhook_admin_port=$(compose port network 9467 | tail -1 | awk -F: '{print $NF}')
dispatcher_admin_port=$(compose port network 9468 | tail -1 | awk -F: '{print $NF}')
fake_bot_port=$(compose port network 18080 | tail -1 | awk -F: '{print $NF}')
webhook_url="http://127.0.0.1:$webhook_port"
platform_admin_url="http://127.0.0.1:$platform_admin_port"
webhook_admin_url="http://127.0.0.1:$webhook_admin_port"
dispatcher_admin_url="http://127.0.0.1:$dispatcher_admin_port"
fake_bot_url="http://127.0.0.1:$fake_bot_port"

wait_for_knowledge "$evidence_dir/knowledge-ready.txt"
wait_for_http "$platform_admin_url/health/ready" 200 "$evidence_dir/platform-ready.json"
wait_for_http "$webhook_admin_url/health/ready" 200 "$evidence_dir/webhook-ready.json"
wait_for_http "$dispatcher_admin_url/health/ready" 200 "$evidence_dir/dispatcher-ready.json"
wait_for_metric library.search 1 "$evidence_dir/platform-capabilities-initial.prom"
wait_for_metric library.read_state 1 "$evidence_dir/platform-capabilities-initial.prom"

owner_user_id=018f0000-0000-7000-8000-000000011001
foreign_user_id=018f0000-0000-7000-8000-000000011002
owner_read_id=018f0000-0000-7000-8000-000000011101
owner_favorite_id=018f0000-0000-7000-8000-000000011102
owner_unread_id=018f0000-0000-7000-8000-000000011103
foreign_analysis_id=018f0000-0000-7000-8000-000000011104

seed_two_tenant_library_fixture() {
  psql_query platform "
    insert into identity.users (user_id, status, created_at, updated_at)
    values ('$owner_user_id', 'active', now(), now());
    insert into identity.identities
      (identity_id, user_id, provider, external_id, created_at, last_seen_at)
    values ('018f0000-0000-7000-8000-000000011010', '$owner_user_id',
            'telegram', '900700601', now(), now());" >/dev/null

  psql_query telegram "
    insert into telegram.identities (telegram_user_id, first_name, access_state)
    values (900700602, 'Synthetic foreign', 'enabled');" >/dev/null

  psql_query knowledge "
    insert into knowledge.source_refs
      (source_ref_id, tenant_ref, owner_context, source_document_id,
       content_digest_algorithm, content_digest_hex, source_blob, created_at)
    values
      ('018f0000-0000-7000-8000-000000011201', 'user:$owner_user_id', 'integration',
       '018f0000-0000-7000-8000-000000011301', 'sha256', repeat('1', 64), '{}'::jsonb, now()),
      ('018f0000-0000-7000-8000-000000011202', 'user:$owner_user_id', 'integration',
       '018f0000-0000-7000-8000-000000011302', 'sha256', repeat('2', 64), '{}'::jsonb, now()),
      ('018f0000-0000-7000-8000-000000011203', 'user:$owner_user_id', 'integration',
       '018f0000-0000-7000-8000-000000011303', 'sha256', repeat('3', 64), '{}'::jsonb, now()),
      ('018f0000-0000-7000-8000-000000011204', 'user:$foreign_user_id', 'integration',
       '018f0000-0000-7000-8000-000000011304', 'sha256', repeat('4', 64), '{}'::jsonb, now());
    insert into knowledge.analysis_runs
      (run_id, source_ref_id, contract_version, prompt_version,
       context_builder_version, model_policy, state, created_at, updated_at)
    values
      ('018f0000-0000-7000-8000-000000011401', '018f0000-0000-7000-8000-000000011201', 'tg011-a', 'tg011', 'tg011', 'tg011', 'completed', now(), now()),
      ('018f0000-0000-7000-8000-000000011402', '018f0000-0000-7000-8000-000000011202', 'tg011-b', 'tg011', 'tg011', 'tg011', 'completed', now(), now()),
      ('018f0000-0000-7000-8000-000000011403', '018f0000-0000-7000-8000-000000011203', 'tg011-c', 'tg011', 'tg011', 'tg011', 'completed', now(), now()),
      ('018f0000-0000-7000-8000-000000011404', '018f0000-0000-7000-8000-000000011204', 'tg011-d', 'tg011', 'tg011', 'tg011', 'completed', now(), now());
    insert into knowledge.analysis_outputs (output_id, run_id, result, raw_response, accepted)
    values
      ('$owner_read_id', '018f0000-0000-7000-8000-000000011401', '{}'::jsonb, '{}'::jsonb, true),
      ('$owner_favorite_id', '018f0000-0000-7000-8000-000000011402', '{}'::jsonb, '{}'::jsonb, true),
      ('$owner_unread_id', '018f0000-0000-7000-8000-000000011403', '{}'::jsonb, '{}'::jsonb, true),
      ('$foreign_analysis_id', '018f0000-0000-7000-8000-000000011404', '{}'::jsonb, '{}'::jsonb, true);
    insert into knowledge.search_documents
      (search_document_id, source_ref_id, latest_output_id, tenant_ref, owner_context,
       document_id, title, lead, body, updated_at)
    values
      ('018f0000-0000-7000-8000-000000011501', '018f0000-0000-7000-8000-000000011201', '$owner_read_id', 'user:$owner_user_id', 'integration', '018f0000-0000-7000-8000-000000011301', 'Owner read recovery', 'read fixture', 'recovery owner read body', now() - interval '3 minutes'),
      ('018f0000-0000-7000-8000-000000011502', '018f0000-0000-7000-8000-000000011202', '$owner_favorite_id', 'user:$owner_user_id', 'integration', '018f0000-0000-7000-8000-000000011302', 'Owner favorite recovery', 'favorite fixture', 'recovery owner favorite body', now() - interval '1 minute'),
      ('018f0000-0000-7000-8000-000000011503', '018f0000-0000-7000-8000-000000011203', '$owner_unread_id', 'user:$owner_user_id', 'integration', '018f0000-0000-7000-8000-000000011303', 'Owner unread recovery', 'unread fixture', 'recovery owner unread body', now() - interval '2 minutes'),
      ('018f0000-0000-7000-8000-000000011504', '018f0000-0000-7000-8000-000000011204', '$foreign_analysis_id', 'user:$foreign_user_id', 'integration', '018f0000-0000-7000-8000-000000011304', 'Foreign recovery secret', 'foreign fixture', 'recovery foreign body', now());
    insert into knowledge.analysis_user_states (tenant_ref, output_id, read_state, favorite)
    values
      ('user:$owner_user_id', '$owner_read_id', 'read', false),
      ('user:$owner_user_id', '$owner_favorite_id', 'unread', true),
      ('user:$foreign_user_id', '$foreign_analysis_id', 'unread', false);" >/dev/null
  printf 'seeded deterministic owner and foreign fixtures\n' >>"$evidence_dir/timeline.txt"
}
seed_two_tenant_library_fixture

search_returns_owner_results_only() {
  post_update 11001 '/search recovery'
  wait_for_sent_jobs 1
  search_text=$(latest_sent_text)
  [[ "$search_text" == *'Owner read recovery'* ]]
  [[ "$search_text" == *'Owner favorite recovery'* ]]
  [[ "$search_text" == *'Owner unread recovery'* ]]
  [[ "$search_text" != *'Foreign recovery secret'* ]]
  printf '%s\n' "$search_text" >"$evidence_dir/search-reply.txt"
}
search_returns_owner_results_only

unread_returns_two_owner_items() {
  post_update 11002 '/unread'
  wait_for_sent_jobs 2
  initial_unread_text=$(latest_sent_text)
  [[ "$initial_unread_text" == *'Owner favorite recovery'* ]]
  [[ "$initial_unread_text" == *'Owner unread recovery'* ]]
  [[ "$initial_unread_text" != *'Owner read recovery'* ]]
  [[ "$initial_unread_text" != *'Foreign recovery secret'* ]]
  wait_for_query telegram \
    "select count(*)::text from telegram.interaction_tokens where action = 'library_read' and analysis_id in ('$owner_favorite_id'::uuid, '$owner_unread_id'::uuid)" 4
  favorite_token=$(wait_for_value telegram \
    "select token from telegram.interaction_tokens where action = 'library_read' and analysis_id = '$owner_favorite_id'::uuid order by created_at desc limit 1")
  foreign_scope_token=$(wait_for_value telegram \
    "select token from telegram.interaction_tokens where action = 'library_read' and analysis_id = '$owner_unread_id'::uuid order by created_at desc limit 1")
  printf '%s\n' "$initial_unread_text" >"$evidence_dir/initial-unread-reply.txt"
}
unread_returns_two_owner_items

foreign_read_token_is_refused() {
  post_update 11003 "/read $foreign_scope_token" 900700602 900700602
  wait_for_sent_jobs 3
  foreign_reply=$(latest_sent_text)
  [[ "$foreign_reply" == *'expired'* ]]
  wait_for_query telegram \
    "select (consumed_at is null)::text from telegram.interaction_tokens where token = '$foreign_scope_token'" true
  wait_for_query knowledge \
    "select coalesce((select read_state from knowledge.analysis_user_states where tenant_ref = 'user:$owner_user_id' and output_id = '$owner_unread_id'::uuid), 'unread')" unread
}
foreign_read_token_is_refused

captured_read_token_changes_authoritative_state() {
  post_update 11004 "/read $favorite_token"
  wait_for_sent_jobs 4
  read_reply=$(latest_sent_text)
  [[ "$read_reply" == *'Item marked as read.'* ]]
  wait_for_query knowledge \
    "select read_state from knowledge.analysis_user_states where tenant_ref = 'user:$owner_user_id' and output_id = '$owner_favorite_id'::uuid" read
  wait_for_query telegram \
    "select (consumed_at is not null)::text from telegram.interaction_tokens where token = '$favorite_token'" true
}
captured_read_token_changes_authoritative_state

replayed_read_token_is_refused() {
  post_update 11005 "/read $favorite_token"
  wait_for_sent_jobs 5
  replay_reply=$(latest_sent_text)
  [[ "$replay_reply" == *'expired'* ]]
  wait_for_query telegram \
    "select count(*)::text from telegram.interaction_tokens where token = '$favorite_token' and consumed_at is not null" 1
}
replayed_read_token_is_refused

final_unread_omits_marked_item() {
  post_update 11006 '/unread'
  wait_for_sent_jobs 6
  final_unread_text=$(latest_sent_text)
  [[ "$final_unread_text" == *'Owner unread recovery'* ]]
  [[ "$final_unread_text" != *'Owner favorite recovery'* ]]
  [[ "$final_unread_text" != *'Owner read recovery'* ]]
  printf '%s\n' "$final_unread_text" >"$evidence_dir/final-unread-reply.txt"
}
final_unread_omits_marked_item

favorite_state_is_preserved() {
  wait_for_query knowledge \
    "select favorite::text from knowledge.analysis_user_states where tenant_ref = 'user:$owner_user_id' and output_id = '$owner_favorite_id'::uuid" true
}
favorite_state_is_preserved

knowledge_failure_removes_capabilities() {
  compose stop knowledge >/dev/null
  wait_for_metric library.search 0 "$evidence_dir/platform-capabilities-down.prom"
  wait_for_metric library.read_state 0 "$evidence_dir/platform-capabilities-down.prom"
  post_update 11007 '/unread'
  wait_for_sent_jobs 7
  unavailable_reply=$(latest_sent_text)
  [[ "$unavailable_reply" == *'temporarily unavailable'* ]]
}
knowledge_failure_removes_capabilities

knowledge_recovery_restores_capabilities() {
  compose start knowledge >/dev/null
  wait_for_knowledge "$evidence_dir/knowledge-recovered.txt"
  wait_for_metric library.search 1 "$evidence_dir/platform-capabilities-recovered.prom"
  wait_for_metric library.read_state 1 "$evidence_dir/platform-capabilities-recovered.prom"
  post_update 11008 '/unread'
  wait_for_sent_jobs 8
  recovered_reply=$(latest_sent_text)
  [[ "$recovered_reply" == *'Owner unread recovery'* ]]
}
knowledge_recovery_restores_capabilities

curl --silent --show-error "$fake_bot_url/requests" >"$evidence_dir/bot-api-requests.json"
psql_query knowledge \
  "select jsonb_build_object('owner_read', (select read_state from knowledge.analysis_user_states where output_id = '$owner_read_id'), 'marked_read', (select read_state from knowledge.analysis_user_states where output_id = '$owner_favorite_id'), 'remaining_unread', coalesce((select read_state from knowledge.analysis_user_states where output_id = '$owner_unread_id'), 'unread'), 'favorite_preserved', (select favorite from knowledge.analysis_user_states where output_id = '$owner_favorite_id'))" \
  >"$evidence_dir/knowledge-state.json"

images_json=$(compose images --format json)
knowledge_image=$(printf '%s\n' "$images_json" \
  | jq -r '.[] | select(.ContainerName | endswith("-knowledge-1")) | .ID' | head -1)
platform_image=$(printf '%s\n' "$images_json" \
  | jq -r '.[] | select(.ContainerName | endswith("-platform-1")) | .ID' | head -1)
telegram_image=$(printf '%s\n' "$images_json" \
  | jq -r '.[] | select(.ContainerName | endswith("-telegram-webhook-1")) | .ID' | head -1)
jq -n \
  --arg knowledge "$knowledge_revision" \
  --arg platform "$platform_revision" \
  --arg telegram "$telegram_revision" \
  --arg workspace "$workspace_revision" \
  --arg compose_sha "$(cat "$evidence_dir/compose.sha256")" \
  --arg source_boundary "$source_boundary" \
  --arg knowledge_image "$knowledge_image" \
  --arg platform_image "$platform_image" \
  --arg telegram_image "$telegram_image" \
  '{knowledge_revision: $knowledge, platform_revision: $platform, telegram_revision: $telegram,
    workspace_revision: $workspace, compose_sha256: $compose_sha,
    source_boundary: $source_boundary, knowledge_image: $knowledge_image,
    platform_image: $platform_image, telegram_image: $telegram_image,
    search_owner_results: 3, initial_unread_results: 2, final_unread_results: 1,
    read_token_replay: "refused", foreign_token: "refused_without_consumption",
    favorite_preserved: true, capability_disappearance: true, capability_recovery: true,
    synthetic_bot_api: true, live_telegram: "not_performed", hosted_ci: "not_verified"}' \
  >"$evidence_dir/summary.json"

compose ps --all >"$evidence_dir/healthy-compose-ps.txt"
printf 'search, unread, read, replay, scope, favorite, capability recovery, cleanup: PASS\n' \
  | tee "$evidence_dir/result.txt"
