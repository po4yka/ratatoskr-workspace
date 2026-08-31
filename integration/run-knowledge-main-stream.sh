#!/usr/bin/env bash
set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
profile="$workspace_root/integration/compose/knowledge-main-stream.yaml"
namespace=${RATATOSKR_TASK_NAMESPACE:?set RATATOSKR_TASK_NAMESPACE}

if [[ ! "$namespace" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]] || [[ "$namespace" != *kno018* ]]; then
  printf 'RATATOSKR_TASK_NAMESPACE must match [a-z0-9][a-z0-9-]{0,30} and contain kno018\n' >&2
  exit 2
fi

project="ratatoskr-${namespace}"
if [[ ${1:-} == --teardown-plan ]]; then
  printf 'docker compose --project-name %s --file %s down --volumes --remove-orphans\n' \
    "$project" "$profile"
  exit 0
fi

fail() {
  printf 'KNO-018: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  rg --quiet --fixed-strings -- "$2" "$1" || fail "$3"
}

contract_check() {
  for input in \
    RATATOSKR_TASK_NAMESPACE \
    RATATOSKR_KNOWLEDGE_CONTEXT RATATOSKR_KNOWLEDGE_REVISION \
    RATATOSKR_EXTRACTOR_CONTEXT RATATOSKR_EXTRACTOR_REVISION \
    RATATOSKR_GITHUB_CONTEXT RATATOSKR_GITHUB_REVISION \
    RATATOSKR_KNO018_RUNTIME_DIR \
    RATATOSKR_KNO018_NETWORK_SUBNET RATATOSKR_KNO018_NETWORK_ANCHOR \
    RATATOSKR_KNO018_SOURCE_ADDRESS
  do
    assert_contains "$profile" "${input}:?" "profile does not require $input"
  done
  for service in \
    network postgres nats topology scripted-provider source-fixture \
    github extractor knowledge nats-tools
  do
    assert_contains "$profile" "  ${service}:" "profile does not define $service"
  done
  if rg --quiet 'container_name:|127\.0\.0\.1:[0-9]+:' "$profile"; then
    fail 'profile fixes a global container name or host port'
  fi
  for value in \
    'ratatoskr_knowledge_main' \
    'evt.content.document.extracted.v1' \
    'evt.social.source.removed.v1' \
    'evt.ai_archive.subject.tombstoned.v1' \
    'evt.knowledge.repository_analysis.requested.v1' \
    'RATATOSKR__RUNTIME__ROLE: primary' \
    'RATATOSKR__SERVICE_AUTH__KNOWLEDGE_TOKEN_FILE' \
    'RATATOSKR_KNO018_SOURCE_ADDRESS'
  do
    assert_contains "$profile" "$value" "profile lacks $value"
  done
  assert_contains "$profile" 'condition: service_completed_successfully' \
    'Knowledge can start before exact topology exists'
  assert_contains "$profile" 'pgvector/pgvector:pg17' \
    'profile does not use PostgreSQL 17 with pgvector'
  printf 'KNO-018 profile contract: PASS\n'
}

if [[ ${1:-} == --contract ]]; then
  contract_check
  exit 0
fi

knowledge=${RATATOSKR_KNOWLEDGE_CONTEXT:?set RATATOSKR_KNOWLEDGE_CONTEXT}
knowledge_revision=${RATATOSKR_KNOWLEDGE_REVISION:?set RATATOSKR_KNOWLEDGE_REVISION}
extractor=${RATATOSKR_EXTRACTOR_CONTEXT:?set RATATOSKR_EXTRACTOR_CONTEXT}
extractor_revision=${RATATOSKR_EXTRACTOR_REVISION:?set RATATOSKR_EXTRACTOR_REVISION}
github=${RATATOSKR_GITHUB_CONTEXT:?set RATATOSKR_GITHUB_CONTEXT}
github_revision=${RATATOSKR_GITHUB_REVISION:?set RATATOSKR_GITHUB_REVISION}

source_boundary=published-clean
require_revision() {
  local label=$1 context=$2 revision=$3 actual
  actual=$(git -C "$context" rev-parse HEAD)
  [[ "$actual" == "$revision" ]] || fail "$label context is at $actual, expected $revision"
  if ! git -C "$context" diff --quiet || ! git -C "$context" diff --cached --quiet \
      || [[ -n $(git -C "$context" ls-files --others --exclude-standard) ]]; then
    if [[ ${RATATOSKR_ALLOW_DIRTY_SOURCES:-0} != 1 ]]; then
      fail "$label context is not clean"
    fi
    source_boundary=dirty-worktree-prepublication
  fi
  if [[ ${RATATOSKR_ALLOW_UNPUBLISHED:-0} != 1 ]]; then
    git -C "$context" merge-base --is-ancestor "$revision" "refs/remotes/origin/$(git -C "$context" branch --show-current)" \
      || fail "$label revision is not present on its remote task branch"
  elif [[ "$source_boundary" == published-clean ]]; then
    source_boundary=unpublished-local-revision
  fi
}

require_revision Knowledge "$knowledge" "$knowledge_revision"
require_revision Extractor "$extractor" "$extractor_revision"
require_revision GitHub "$github" "$github_revision"

workspace_revision=$(git -C "$workspace_root" rev-parse HEAD)
if ! git -C "$workspace_root" diff --quiet || ! git -C "$workspace_root" diff --cached --quiet \
    || [[ -n $(git -C "$workspace_root" ls-files --others --exclude-standard) ]]; then
  if [[ ${RATATOSKR_ALLOW_DIRTY_SOURCES:-0} != 1 ]]; then
    fail 'Workspace context is not clean; commit the profile before final evidence'
  fi
  source_boundary=dirty-worktree-prepublication
fi

evidence_dir=${RATATOSKR_EVIDENCE_DIR:-"$workspace_root/evidence/$namespace"}
mkdir -p "$evidence_dir"
: >"$evidence_dir/timeline.txt"

owned_runtime=0
if [[ -z ${RATATOSKR_KNO018_RUNTIME_DIR:-} ]]; then
  RATATOSKR_KNO018_RUNTIME_DIR=$(mktemp -d "$workspace_root/.kno018-runtime.XXXXXX")
  export RATATOSKR_KNO018_RUNTIME_DIR
  owned_runtime=1
fi
runtime_dir=$RATATOSKR_KNO018_RUNTIME_DIR
mkdir -p "$runtime_dir"
printf '%s\n' 'kno018-knowledge-service-token-with-adequate-entropy' >"$runtime_dir/github-token"
chmod 0600 "$runtime_dir/github-token"
mkdir -p "$runtime_dir/bin"
if ! command -v docker-credential-desktop >/dev/null 2>&1; then
  credential_helper=$(command -v docker-credential-osxkeychain) \
    || fail 'Docker credential helper is unavailable'
  ln -s "$credential_helper" "$runtime_dir/bin/docker-credential-desktop"
  PATH="$runtime_dir/bin:$PATH"
  export PATH
fi

namespace_hash=$(printf '%s' "$namespace" | cksum | awk '{print $1}')
network_second=$((namespace_hash % 240 + 1))
network_third=$((namespace_hash / 240 % 240 + 1))
RATATOSKR_KNO018_NETWORK_SUBNET="11.${network_second}.${network_third}.0/28"
RATATOSKR_KNO018_NETWORK_ANCHOR="11.${network_second}.${network_third}.2"
RATATOSKR_KNO018_SOURCE_ADDRESS="11.${network_second}.${network_third}.3"
export RATATOSKR_KNO018_NETWORK_SUBNET RATATOSKR_KNO018_NETWORK_ANCHOR \
  RATATOSKR_KNO018_SOURCE_ADDRESS

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
  if [[ "$owned_runtime" == 1 && "$runtime_dir" == "$workspace_root"/.kno018-runtime.* ]]; then
    rm -rf -- "$runtime_dir"
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

contract_check
compose config --quiet
if [[ ${1:-} == --validate ]]; then
  printf 'KNO-018 Compose validation: PASS\n'
  exit 0
fi

printf '%s profile_build_started\n' "$(date -u +%FT%TZ)" >>"$evidence_dir/timeline.txt"
for service in github extractor knowledge; do
  build-gate -- docker compose --project-name "$project" --file "$profile" build "$service"
done
compose up --detach --wait
printf '%s profile_ready\n' "$(date -u +%FT%TZ)" >>"$evidence_dir/timeline.txt"

psql_query() {
  local database=$1 sql=$2
  compose exec -T postgres psql -U fleet -d "$database" -Atqc "$sql"
}

wait_for_query() {
  local database=$1 sql=$2 expected=$3 actual _
  for _ in $(seq 1 240); do
    actual=$(psql_query "$database" "$sql" 2>/dev/null || true)
    if [[ "$actual" == "$expected" ]]; then
      return 0
    fi
    sleep 1
  done
  fail "timed out waiting for $database query [$sql] to equal $expected (last $actual)"
}

knowledge_url=http://127.0.0.1:9081
wait_for_ready() {
  local expected=$1 code response _
  for _ in $(seq 1 120); do
    response=$(compose exec -T network wget -S -O /dev/null "$knowledge_url/ready" 2>&1 || true)
    code=$(awk '$1 ~ /^HTTP\// { value = $2 } END { print value }' <<<"$response")
    if [[ "$code" == "$expected" ]]; then
      return 0
    fi
    sleep 1
  done
  fail "Knowledge readiness did not become HTTP $expected"
}
wait_for_ready 200

publish() {
  local subject=$1 message_id=$2 file=$3
  compose exec -T nats-tools nats --server nats://127.0.0.1:4222 pub --jetstream \
    --header "Nats-Msg-Id:${message_id}" --force-stdin "$subject" <"$file" >/dev/null
}

owner='user:018f0000-0000-7000-8000-000000000005'
repository_id='018f0000-0000-7000-8000-000000000701'
readme='# Durable Ratatoskr repository'
readme_digest=$(printf '%s' "$readme" | openssl dgst -sha256 -r | awk '{print $1}')
readme_base64=$(printf '%s' "$readme" | openssl base64 -A)

jq -nc --arg owner "$owner" --arg repository_id "$repository_id" \
  --arg digest "$readme_digest" --argjson length "${#readme}" '{
    owner:$owner,
    repository_id:$repository_id,
    github_repository_numeric_id:42,
    request_id:"018f0000-0000-7000-8000-000000000702",
    source_revision:{
      attributes_digest:{algorithm:"sha256",hex:("a"*64)},
      readme:{state:"present",content_ref:{
        owner_service:"ratatoskr-github",
        digest:{algorithm:"sha256",hex:$digest},
        media_type:"text/markdown",
        length_bytes:$length
      }}
    },
    repository_attributes:{
      repository_full_name:"owner/repository",
      description:"Durable Ratatoskr repository",
      primary_language:"Rust"
    },
    requested_contract:"repository_analysis",
    idempotency_key:{algorithm:"sha256",hex:("b"*64)},
    extensions:{}
  }' >"$runtime_dir/repository-payload.json"
repository_payload=$(tr -d '\n' <"$runtime_dir/repository-payload.json")
repository_payload_sql=${repository_payload//\'/\'\'}
compose exec -T postgres psql -v ON_ERROR_STOP=1 -U fleet -d github <<SQL
insert into github_catalog.repositories (repository_id, provider_repository_id)
values ('$repository_id', 42);
insert into github_catalog.repository_readme_blobs
  (content_digest, bytes, media_type, length_bytes)
values ('$readme_digest', decode('$readme_base64', 'base64'), 'text/markdown', ${#readme});
insert into github_catalog.repository_analysis_publications
  (repository_id, source_digest, message_id, payload)
values ('$repository_id', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        '018f0000-0000-7000-8000-000000000703', '$repository_payload_sql'::jsonb);
SQL

jq -nc --arg payload "$repository_payload" '{
  event_id:"018f0000-0000-7000-8000-000000000704",
  event_type:"knowledge.repository_analysis.requested.v1",
  occurred_at:"2026-08-31T09:00:00Z",
  producer:"ratatoskr-github",
  aggregate_id:"repository:018f0000-0000-7000-8000-000000000701",
  correlation_id:"event:018f0000-0000-7000-8000-000000000704",
  tenant_id:"user:018f0000-0000-7000-8000-000000000005",
  schema_version:1,
  payload:($payload|fromjson)
}' >"$runtime_dir/repository-event.json"

jq -nc --arg owner "$owner" '{
  event_id:"018f0000-0000-7000-8000-000000000711",
  event_type:"social.source.captured.v1",
  occurred_at:"2026-08-31T09:00:01Z",
  producer:"ratatoskr-x",
  aggregate_id:"social_source:018f0000-0000-7000-8000-000000000712",
  correlation_id:"event:018f0000-0000-7000-8000-000000000711",
  tenant_id:$owner,
  schema_version:1,
  payload:{source:{
    social_source_id:"018f0000-0000-7000-8000-000000000712",
    platform:"x",external_post_id:"kno018-post",owner:$owner,
    captured_at:"2026-08-31T09:00:01Z",text:"A useful Ratatoskr post.",
    content_digest:{algorithm:"sha256",hex:("c"*64)},
    acquisition:"official_api",saved_authority:"authoritative_platform_state",
    completeness:"complete",upstream_availability:"available"
  }}
}' >"$runtime_dir/social-event.json"

jq -nc --arg owner "$owner" '{
  event_id:"018f0000-0000-7000-8000-000000000721",
  event_type:"ai_archive.conversation.added.v1",
  occurred_at:"2026-08-31T09:00:02Z",
  producer:"ratatoskr-chatgpt",
  aggregate_id:"ai_archive:018f0000-0000-7000-8000-000000000722",
  correlation_id:"event:018f0000-0000-7000-8000-000000000721",
  tenant_id:$owner,
  schema_version:1,
  payload:{
    import_provenance:{
      ai_archive_id:"018f0000-0000-7000-8000-000000000722",provider:"chatgpt",owner:$owner,
      source_export:{owner_service:"ratatoskr-chatgpt",digest:{algorithm:"sha256",hex:("d"*64)},media_type:"application/json",length_bytes:512},
      imported_at:"2026-08-31T08:59:00Z",parser_name:"chatgpt_export",parser_version:"2026.08.1"
    },
    conversation:{
      ai_conversation_id:"018f0000-0000-7000-8000-000000000723",provider:"chatgpt",owner:$owner,
      messages:[{external_message_id:"msg-kno018",author_role:"user",parts:[{part_kind:"text",text:"Keep durable evidence."}],parser_name:"chatgpt_export",parser_version:"2026.08.1"}],
      content_digest:{algorithm:"sha256",hex:("e"*64)},parser_name:"chatgpt_export",parser_version:"2026.08.1"
    }
  }
}' >"$runtime_dir/archive-event.json"

jq -nc --arg owner "$owner" \
  --arg url "http://${RATATOSKR_KNO018_SOURCE_ADDRESS}/article" '{
  command_id:"018f0000-0000-7000-8000-000000000731",
  command_type:"content.capture.requested.v1",
  requested_at:"2026-08-31T09:00:03Z",
  operation_id:"018f0000-0000-7000-8000-000000000732",
  tenant_id:$owner,
  correlation_id:"operation:018f0000-0000-7000-8000-000000000732",
  idempotency_key:"kno018-real-extractor",
  payload:{url:$url}
}' >"$runtime_dir/extractor-command.json"

publish evt.knowledge.repository_analysis.requested.v1 repo-kno018 "$runtime_dir/repository-event.json"
publish evt.social.source.captured.v1 social-kno018 "$runtime_dir/social-event.json"
publish evt.ai_archive.conversation.added.v1 archive-kno018 "$runtime_dir/archive-event.json"
publish cmd.content.capture.requested.v1 extractor-kno018 "$runtime_dir/extractor-command.json"

wait_for_query extractor \
  "select count(*) from extractor.outbox_events where subject='evt.content.document.extracted.v1' and published_at is not null" 1
wait_for_query knowledge "select count(*) from knowledge.primary_event_receipts" 4
wait_for_query knowledge "select count(*) from knowledge.analysis_work where state='completed'" 4
wait_for_query knowledge "select count(*) from knowledge.search_documents" 4
wait_for_query knowledge "select count(*) from knowledge.knowledge_outbox where published_at is not null" 3
wait_for_query knowledge \
  "select string_agg(subject, ',' order by subject) from knowledge.knowledge_outbox where published_at is not null" \
  "evt.knowledge.ai_archive_analysis.completed.v1,evt.knowledge.analysis.completed.v1,evt.knowledge.repository_analysis.completed.v1"
wait_for_query knowledge "select count(*) from knowledge.provider_usage" 4
printf '%s all_primary_families_completed\n' "$(date -u +%FT%TZ)" >>"$evidence_dir/timeline.txt"

compose exec -T nats-tools nats --server nats://127.0.0.1:4222 consumer info \
  ratatoskr_events ratatoskr_knowledge_main --json >"$evidence_dir/consumer.json"
jq -e '.config.durable_name == "ratatoskr_knowledge_main" and
       .config.ack_policy == "explicit" and
       (.config.filter_subjects | length) == 13' "$evidence_dir/consumer.json" >/dev/null

printf 'not-json' >"$runtime_dir/poison.txt"
publish evt.social.source.captured.v1 poison-kno018 "$runtime_dir/poison.txt"
wait_for_query knowledge "select count(*) from knowledge.primary_event_rejections" 1
publish evt.social.source.captured.v1 social-kno018-replay "$runtime_dir/social-event.json"
wait_for_query knowledge "select count(*) from knowledge.primary_event_receipts" 4
wait_for_query knowledge "select count(*) from knowledge.provider_usage" 4
printf '%s poison_and_replay_safe\n' "$(date -u +%FT%TZ)" >>"$evidence_dir/timeline.txt"

outbox_id=$(psql_query knowledge "select outbox_id from knowledge.knowledge_outbox order by created_at limit 1")
compose stop nats >/dev/null
wait_for_ready 503
psql_query knowledge "update knowledge.knowledge_outbox set published_at=null,next_attempt_at=now() where outbox_id='$outbox_id'" >/dev/null
sleep 2
[[ $(psql_query knowledge "select published_at is null from knowledge.knowledge_outbox where outbox_id='$outbox_id'") == t ]] \
  || fail 'broker outage falsely marked terminal publication sent'
compose start nats >/dev/null
wait_for_ready 200
wait_for_query knowledge "select published_at is not null from knowledge.knowledge_outbox where outbox_id='$outbox_id'" t
printf '%s broker_outbox_recovery_safe\n' "$(date -u +%FT%TZ)" >>"$evidence_dir/timeline.txt"

jq -nc --arg owner "$owner" '{
  event_id:"018f0000-0000-7000-8000-000000000741",
  event_type:"social.source.removed.v1",occurred_at:"2026-08-31T10:00:00Z",
  producer:"ratatoskr-x",aggregate_id:"social_source:018f0000-0000-7000-8000-000000000712",
  correlation_id:"event:018f0000-0000-7000-8000-000000000741",tenant_id:$owner,schema_version:1,
  payload:{social_source_id:"018f0000-0000-7000-8000-000000000712",owner:$owner,reason:"user_requested",removed_at:"2026-08-31T10:00:00Z"}
}' >"$runtime_dir/social-removed.json"
publish evt.social.source.removed.v1 social-removed-kno018 "$runtime_dir/social-removed.json"
wait_for_query knowledge \
  "select lifecycle from knowledge.primary_source_heads where family='social' and source_key='018f0000-0000-7000-8000-000000000712'" removed
wait_for_query knowledge \
  "select count(*) from knowledge.source_refs where tenant_ref='$owner' and source_document_id='018f0000-0000-7000-8000-000000000712'" 0
wait_for_query knowledge "select count(*) from knowledge.search_documents" 3
jq '.event_id="018f0000-0000-7000-8000-000000000742" | .correlation_id="event:018f0000-0000-7000-8000-000000000742"' \
  "$runtime_dir/social-event.json" >"$runtime_dir/social-stale.json"
publish evt.social.source.captured.v1 social-stale-kno018 "$runtime_dir/social-stale.json"
wait_for_query knowledge \
  "select lifecycle from knowledge.primary_source_heads where family='social' and source_key='018f0000-0000-7000-8000-000000000712'" removed
wait_for_query knowledge "select count(*) from knowledge.search_documents" 3
wait_for_query knowledge "select count(*) from knowledge.provider_usage" 4

jq -nc --arg owner "$owner" '{
  event_id:"018f0000-0000-7000-8000-000000000751",
  event_type:"ai_archive.subject.tombstoned.v1",occurred_at:"2026-08-31T10:00:01Z",
  producer:"ratatoskr-chatgpt",aggregate_id:"ai_archive:018f0000-0000-7000-8000-000000000722",
  correlation_id:"event:018f0000-0000-7000-8000-000000000751",tenant_id:$owner,schema_version:1,
  payload:{
    ai_archive_id:"018f0000-0000-7000-8000-000000000722",provider:"chatgpt",owner:$owner,
    subject:{subject_kind:"archive"},reason:"provider_deletion_event",
    evidence_ref:{owner_service:"ratatoskr-chatgpt",digest:{algorithm:"sha256",hex:("f"*64)},media_type:"application/json",length_bytes:512},
    observed_at:"2026-08-31T10:00:01Z"
  }
}' >"$runtime_dir/archive-tombstone.json"
publish evt.ai_archive.subject.tombstoned.v1 archive-tombstone-kno018 "$runtime_dir/archive-tombstone.json"
wait_for_query knowledge \
  "select lifecycle from knowledge.primary_source_heads where family='ai_archive' and source_key='archive:018f0000-0000-7000-8000-000000000722'" removed
wait_for_query knowledge \
  "select count(*) from knowledge.source_refs where tenant_ref='$owner' and ai_archive_id='018f0000-0000-7000-8000-000000000722'" 0
wait_for_query knowledge "select count(*) from knowledge.search_documents" 2
jq '.event_id="018f0000-0000-7000-8000-000000000752" | .correlation_id="event:018f0000-0000-7000-8000-000000000752"' \
  "$runtime_dir/archive-event.json" >"$runtime_dir/archive-stale.json"
publish evt.ai_archive.conversation.added.v1 archive-stale-kno018 "$runtime_dir/archive-stale.json"
wait_for_query knowledge \
  "select lifecycle from knowledge.primary_source_heads where family='ai_archive' and source_key='archive:018f0000-0000-7000-8000-000000000722'" removed
wait_for_query knowledge "select count(*) from knowledge.search_documents" 2
wait_for_query knowledge "select count(*) from knowledge.provider_usage" 4
printf '%s tombstone_stale_replay_safe\n' "$(date -u +%FT%TZ)" >>"$evidence_dir/timeline.txt"

compose stop --timeout 15 knowledge >/dev/null
[[ $(compose ps --status exited --format json knowledge \
  | jq -r 'if type == "array" then .[0].ExitCode else .ExitCode end') == 0 ]] \
  || fail 'Knowledge SIGTERM drain did not exit successfully'
compose start knowledge >/dev/null
wait_for_ready 200
printf '%s sigterm_restart_safe\n' "$(date -u +%FT%TZ)" >>"$evidence_dir/timeline.txt"

cat >"$evidence_dir/summary.txt" <<EOF
profile=KNO-018 composed fixture
source_boundary=$source_boundary
workspace_revision=$workspace_revision
knowledge_revision=$knowledge_revision
extractor_revision=$extractor_revision
github_revision=$github_revision
document_path=real Extractor service over isolated task fixture address
repository_path=real authenticated GitHub internal README endpoint
social_path=canonical fixture injection; no live X proof
ai_archive_path=canonical fixture injection; no live ChatGPT or Claude proof
provider=scripted OpenRouter-compatible fixture; no live provider or billing proof
hosted_ci=not observed
deployment=not performed
EOF

printf 'KNO-018 composed primary and fault profile: PASS\n'
