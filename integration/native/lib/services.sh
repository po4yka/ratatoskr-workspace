#!/usr/bin/env bash
# shellcheck disable=SC2034
# Starting, stopping and configuring the services of the native smoke. Source after lib/common.sh, lib/postgres.sh and lib/assert.sh.
#
# Services run exactly as deployed: configuration only through the RATATOSKR__* keys of each repository's deploy/systemd/*.conf.example, rendered by render_conf, which may change only addresses, paths under $S, the CHANGE-ME secrets, PLATFORM_ACCOUNTS user ids and the per-flow keys a flow names. Every change is appended to $S/conf/deviations.txt and copied into the flow's result.txt. There are no flags and no test-only seams except the two the plan documents: the OpenRouter BASE_URL pointing at the loopback fake, and X's EXTRA_CA_FILE (R3-15).
#
# A process is stopped only through the pid file this library wrote: SIGTERM, wait 15 seconds, then SIGKILL of that pid. There is no pkill, killall or kill by name anywhere in the smoke.

svc_bin() {
  case "$1" in
    edge) echo ratatoskr-edge ;;
    chatgpt) echo ratatoskr-chatgpt-archive ;;
    claude) echo ratatoskr-claude-archive ;;
    knowledge) echo ratatoskr-knowledge-service ;;
    extractor) echo ratatoskr-extractor ;;
    api) echo ratatoskr-channel-digests-api ;;
    worker) echo ratatoskr-channel-digests-worker ;;
    x) echo ratatoskr-x ;;
    instagram) echo ratatoskr-instagram-archive ;;
    threads) echo ratatoskr-threads-archive ;;
    github) echo ratatoskr-github-catalog ;;
    webhook) echo ratatoskr-telegram-webhook ;;
    dispatcher) echo ratatoskr-telegram-dispatcher ;;
    *) smoke_die "unknown service $1" ;;
  esac
}

# The operator readiness URL of a service. The channel-digests worker is not ready without MTProto credentials (R3-10), so a flow never waits for it.
svc_ready_url() {
  case "$1" in
    edge) echo 127.0.0.1:9464/health/ready ;;
    chatgpt) echo 127.0.0.1:9085/health/ready ;;
    claude) echo 127.0.0.1:9086/health/ready ;;
    knowledge) echo 127.0.0.1:9081/ready ;;
    extractor) echo 127.0.0.1:9088/health/ready ;;
    api) echo 127.0.0.1:9469/ready ;;
    worker) echo 127.0.0.1:9470/ready ;;
    x) echo 127.0.0.1:9087/health/ready ;;
    instagram) echo 127.0.0.1:9082/health/ready ;;
    threads) echo 127.0.0.1:9084/health/ready ;;
    github) echo 127.0.0.1:9095/ready ;;
    webhook) echo 127.0.0.1:9467/health/ready ;;
    dispatcher) echo 127.0.0.1:9468/health/ready ;;
    *) smoke_die "unknown service $1" ;;
  esac
}

svc_start() {
  local name=$1
  nohup python3 -I "$NATIVE_ROOT/lib/envrun.py" "$S/conf/$name.env" "$S/bin/$(svc_bin "$name")" >>"$S/logs/$name.log" 2>&1 &
  echo $! >"$S/run/$name.pid"
  note "started $name pid $(cat "$S/run/$name.pid")"
}

svc_wait_ready() { waitready "$(svc_ready_url "$1")" "${2:-60}"; }

# SIGTERM, wait 15 seconds, then SIGKILL, of the pid in $S/run/NAME.pid only.
pid_stop() {
  local name=$1 pid i
  pid=$(cat "$S/run/$name.pid" 2>/dev/null) || return 0
  if kill -TERM "$pid" 2>/dev/null; then
    for ((i = 0; i < 15; i++)); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
      note "SIGKILL $name pid $pid after 15 s"
      kill -KILL "$pid" 2>/dev/null
    fi
  fi
  rm -f "$S/run/$name.pid"
}
svc_stop() { pid_stop "$1"; }

# A hard kill of the recorded pid, for the legs that need a crash rather than a shutdown.
svc_kill() {
  local pid
  pid=$(cat "$S/run/$1.pid" 2>/dev/null) || return 0
  kill -KILL "$pid" 2>/dev/null
  rm -f "$S/run/$1.pid"
}

# Stops every process that has a pid file, services and fakes alike; used by the cleanup of every flow.
stop_all() {
  local file
  for file in "$S"/run/*.pid; do
    [[ -e "$file" ]] || continue
    pid_stop "$(basename "$file" .pid)"
  done
}

# fake_start NAME SCRIPT ARGS...: a loopback fake from fixtures/, labelled in result.txt by the flow.
fake_start() {
  local name=$1 script=$2
  shift 2
  nohup python3 -I "$NATIVE_ROOT/fixtures/$script" "$@" >>"$S/logs/$name.log" 2>&1 &
  echo $! >"$S/run/$name.pid"
}

# render_conf REPO_ID EXAMPLE DST_NAME RULE...: renders repos/<id>/deploy/systemd/<EXAMPLE> into $S/conf/<DST_NAME>.env.
render_conf() {
  local repo=$1 example=$2 dst=$3
  shift 3
  python3 -I "$NATIVE_ROOT/lib/render_conf.py" "$(repo_dir "$repo")/deploy/systemd/$example" "$S/conf/$dst.env" "$S/conf/deviations.txt" "$@"
}

nkey() { printf '%s/nk/%s.nkey' "$S" "$1"; }

# Edge. $1 is the base64 public assertion key, or empty to use the example's documented opt-out (no Telegram Mini App in the flow).
conf_edge() {
  local rules=(
    "--set RATATOSKR__ADMIN__BIND=127.0.0.1:9464"
    "--set RATATOSKR__ARCHIVE_STAGING__ROOT=$S/staging/edge"
    "--set RATATOSKR__CHANNEL_DIGESTS__SERVICE_SECRET=$(secret digest)"
    "--set RATATOSKR__DATABASE__URL=$(db_url ratatoskr_edge)"
    "--set RATATOSKR__BUS__NKEY_SEED_PATH=$(nkey edge)"
  )
  if [[ -n "${1:-}" ]]; then
    rules+=("--set RATATOSKR__IDENTITY__ASSERTION_KEY=$1")
  else
    rules+=("--remove RATATOSKR__IDENTITY__ASSERTION_KEY")
  fi
  render_conf platform edge.conf.example edge "${rules[@]}"
}

# ChatGPT and Claude. $1 is the PLATFORM_ACCOUNTS value (comma separated user=account pairs); U2 is left out until a flow maps it.
chatgpt_accounts() { printf '%s=smoke-chatgpt-account-1' "$U1"; }
claude_accounts() { printf '%s=00000000-0000-7000-8000-0000000000b1' "$U1"; }

conf_chatgpt() {
  render_conf chatgpt chatgpt.conf.example chatgpt \
    "--set RATATOSKR__STORAGE__DATABASE_URL=$(db_url ratatoskr_chatgpt)" \
    "--set RATATOSKR__STORAGE__BLOB_ROOT=$S/blobs/chatgpt" \
    "--set RATATOSKR__STORAGE__RECEIPT_STAGING_ROOT=$S/staging/chatgpt" \
    "--set RATATOSKR__RECEIPT__PLATFORM_ACCOUNTS=${1:-$(chatgpt_accounts)}" \
    "--set RATATOSKR__RECEIPT__EVENT_BUS_NKEY_SEED_PATH=$(nkey chatgpt)"
}

conf_claude() {
  render_conf claude claude.conf.example claude \
    "--set RATATOSKR__STORAGE__DATABASE_URL=$(db_url ratatoskr_claude)" \
    "--set RATATOSKR__STORAGE__BLOB_ROOT=$S/blobs/claude" \
    "--set RATATOSKR__RECEIPT__PLATFORM_ACCOUNTS=${1:-$(claude_accounts)}" \
    "--set RATATOSKR__RECEIPT__EVENT_BUS_NKEY_SEED_PATH=$(nkey claude)"
}

conf_extractor() {
  render_conf extractor extractor.conf.example extractor \
    "--set RATATOSKR__BLOBS__ROOT=$S/blobs/extractor" \
    "--set RATATOSKR__BLOBS__TELEGRAM_ROOT=$S/blobs/telegram" \
    "--set RATATOSKR__DATABASE__URL=$(db_url ratatoskr_extractor)" \
    "--set RATATOSKR__BUS__NKEY_SEED_PATH=$(nkey extractor)"
}

# Knowledge. $1 is the recap switch (true or false). The OpenRouter base URL is the documented seam and points at the loopback fake.
conf_knowledge() {
  render_conf knowledge knowledge.conf.example knowledge \
    "--set RATATOSKR__STORAGE__DATABASE_URL=$(db_url ratatoskr_knowledge)" \
    "--set RATATOSKR__STORAGE__BLOB_ROOT=$S/blobs/knowledge" \
    "--set RATATOSKR__PROVIDER__OPENROUTER__API_KEY=sk-or-smoke-not-a-real-key" \
    "--set RATATOSKR__INGEST__BUS_CREDENTIALS_FILE=$(nkey knowledge)" \
    "--set RATATOSKR__INGEST__GITHUB_README_SERVICE_SECRET=$(secret readme)" \
    "--set RATATOSKR__CHANNEL_RECAP__ENABLED=${1:-false}" \
    "--set RATATOSKR__CHANNEL_RECAP__BUS_CREDENTIALS_FILE=$(nkey knowledge)" \
    "--set RATATOSKR__CHANNEL_RECAP__DIGEST_SOURCE_SERVICE_SECRET=$(secret digest)" \
    "--set RATATOSKR__CHANNEL_RECAP__RESULT_READER_SERVICE_SECRET=$(secret reader)" \
    "--add RATATOSKR__PROVIDER__OPENROUTER__BASE_URL=http://127.0.0.1:$FAKE_OPENROUTER_PORT/api/v1"
}

conf_api() {
  render_conf channel-digests api.conf.example api \
    "--set RATATOSKR__DATABASE__URL=$(db_url ratatoskr_channel_digests)" \
    "--set RATATOSKR__AUTH__SERVICE_SECRET=$(secret digest)" \
    "--set RATATOSKR__KNOWLEDGE__RESULT_READER_SERVICE_SECRET=$(secret reader)"
}

# The worker needs an encrypted provider session file (fixtures/session_file.py); the MTProto connection fails because the smoke has no credentials. $1 is the run deadline, $2 the schedule owner.
conf_worker() {
  python3 -I "$NATIVE_ROOT/fixtures/session_file.py" "$S/keys" || return 1
  render_conf channel-digests worker.conf.example worker \
    "--set RATATOSKR__DATABASE__URL=$(db_url ratatoskr_channel_digests)" \
    "--set RATATOSKR__AUTH__SERVICE_SECRET=$(secret digest)" \
    "--set RATATOSKR__BUS__NKEY_SEED_PATH=$(nkey channel-digests)" \
    "--set RATATOSKR__PROVIDER__API_HASH=0123456789abcdef0123456789abcdef" \
    "--set RATATOSKR__PROVIDER__SESSION_FILE=$S/keys/session.enc" \
    "--set RATATOSKR__PROVIDER__SESSION_KEY_FILE=$S/keys/session.key" \
    "--set RATATOSKR__SCHEDULE__OWNER_USER_ID=${2:-$U1}" \
    "--set RATATOSKR__LIMITS__RUN_DEADLINE_SECONDS=${1:-60}"
}

# X. The only X-specific deviation is the fake API base URL and the throwaway CA for it (R3-15).
conf_x() {
  [[ -f "$S/keys/x-public-capture.token" ]] || (umask 077 && printf 'dummy-app-only-bearer-token-for-the-fake-x-api' >"$S/keys/x-public-capture.token")
  render_conf x x.conf.example x \
    "--set RATATOSKR__DATABASE__URL=$(db_url ratatoskr_x)" \
    "--set RATATOSKR__BUS__NKEY_SEED_PATH=$(nkey x)" \
    "--set RATATOSKR__PUBLIC_CAPTURE__BEARER_TOKEN_PATH=$S/keys/x-public-capture.token" \
    "--set RATATOSKR__PUBLIC_CAPTURE__API_BASE_URL=https://127.0.0.1:$FAKE_X_PORT" \
    "--uncomment RATATOSKR__PUBLIC_CAPTURE__EXTRA_CA_FILE=$S/pki/ca.pem"
}

conf_instagram() {
  [[ -f "$S/keys/instagram-meta-token" ]] || (umask 077 && printf 'dummy-meta-token' >"$S/keys/instagram-meta-token")
  render_conf instagram instagram.conf.example instagram \
    "--set RATATOSKR__STORAGE__DATABASE_URL=$(db_url ratatoskr_instagram)" \
    "--set RATATOSKR__BUS__NKEY_SEED_PATH=$(nkey instagram)" \
    "--set RATATOSKR__PUBLIC_RESOLUTION__ACCESS_TOKEN_PATH=$S/keys/instagram-meta-token"
}

conf_threads() {
  render_conf threads threads.conf.example threads \
    "--set RATATOSKR__STORAGE__DATABASE_URL=$(db_url ratatoskr_threads)" \
    "--set RATATOSKR__BUS__NKEY_SEED_PATH=$(nkey threads)" \
    "--set RATATOSKR__PUBLIC_RESOLUTION__RAW_OBJECT_ROOT=$S/blobs/threads"
}

# GitHub. The provider base URL is the loopback fake; the observer interval is shortened for the flow (the plan names both).
conf_github() {
  local key
  key=$(secret githubkey)
  [[ ${#key} -ge 32 ]] || smoke_die "secret too short"
  render_conf github github.conf.example github \
    "--set RATATOSKR__STORAGE__DATABASE_URL=$(db_url ratatoskr_github)" \
    "--set RATATOSKR__CREDENTIALS__ENCRYPTION_KEY_HEX=$(sha256_text "$key")" \
    "--set RATATOSKR__BUS__NKEY_SEED_PATH=$(nkey github)" \
    "--set RATATOSKR__INTERNAL__READER_SERVICE_SECRET=$(secret readme)" \
    "--set RATATOSKR__WATCH__OBSERVE_INTERVAL_SECONDS=${1:-10}" \
    "--set RATATOSKR__PROVIDER__TIMEOUT_MS=${2:-30000}" \
    "--add RATATOSKR__PROVIDER__BASE_URL=http://127.0.0.1:$FAKE_GITHUB_PORT"
}

# Telegram: webhook and dispatcher share one role and one signing key. The Bot API base URL points at the loopback fake bot, and the Platform base URL at the recording tap in front of Edge (the one deviation of flow F3, so the request the webhook sends can be read).
# The settings the webhook and the dispatcher share, in the global array TELEGRAM_COMMON, and the secret files they read.
telegram_common() {
  TELEGRAM_COMMON=(
    "--set RATATOSKR__DATABASE__URL=$(db_url ratatoskr_telegram)"
    "--set RATATOSKR__BOT_API__TOKEN_FILE=$S/keys/bot-token"
    "--set RATATOSKR__PLATFORM__ASSERTION_SIGNING_KEY_FILE=$S/keys/telegram-signing-key"
    "--add RATATOSKR__BOT_API__BASE_URL=http://127.0.0.1:$FAKE_BOT_PORT"
    "--set RATATOSKR__PLATFORM__BASE_URL=http://127.0.0.1:$FAKE_TAP_PORT"
  )
  [[ -f "$S/keys/bot-token" ]] || (umask 077 && printf 'smoke-%s' "$(secret bottoken)" >"$S/keys/bot-token")
  [[ -f "$S/keys/webhook-secret" ]] || (umask 077 && secret webhooksecret >"$S/keys/webhook-secret")
}

conf_telegram() {
  telegram_common
  render_conf telegram webhook.conf.example webhook "${TELEGRAM_COMMON[@]}" \
    "--set RATATOSKR__ADMIN__BIND=127.0.0.1:9467" \
    "--set RATATOSKR__ACCESS__OWNER_TELEGRAM_USER_ID=900700601" \
    "--set RATATOSKR__WEBHOOK__SECRET_TOKEN_FILE=$S/keys/webhook-secret" \
    "--set RATATOSKR__INGESTION__BLOB_ROOT=$S/blobs/telegram"
  conf_dispatcher_variant dispatcher 30
}

# conf_dispatcher_variant NAME ACK_WAIT_SECONDS: the dispatcher's configuration as shipped, with only the notification ack wait changed, rendered to $S/conf/NAME.env. Flow F0 uses it to show that check-config refuses a wait other than Edge's fixed 30 (R4-08).
conf_dispatcher_variant() {
  telegram_common
  render_conf telegram dispatcher.conf.example "$1" "${TELEGRAM_COMMON[@]}" \
    "--set RATATOSKR__ADMIN__BIND=127.0.0.1:9468" \
    "--set RATATOSKR__NOTIFICATION_BUS__ACK_WAIT_SECONDS=$2" \
    "--set RATATOSKR__NOTIFICATION_BUS__CREDENTIALS_FILE=$(nkey telegram)"
}

# Fresh PostgreSQL and NATS for a flow.
infra_fresh() {
  : >"$S/logs/nats.log"
  rm -f "$S/run/probe.begin" "$S/run/probe.end"
  pg_up || return 1
  nats_up || return 1
}

# PostgreSQL and NATS again over the state a previous flow kept (FLOW_KEEP_DATA=1): same clusters, same keys, same configuration, no provisioning.
infra_resume() {
  pg_start || return 1
  : >"$S/logs/nats.log"
  nohup nats-server -c "$S/nats.conf" -l "$S/logs/nats.log" >>"$S/logs/nats.stdout" 2>&1 &
  echo $! >"$S/run/nats.pid"
  local i
  for ((i = 0; i < 30; i++)); do
    curl -fsS "$NATS_MON/healthz" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

# Edge first, in the order Platform's deploy/README.md documents: its password, its first start (it applies schema.sql and provisions the streams, every durable of S04 and the KV bucket), then 02-grants.sql. $1 is the base64 public assertion key, or empty.
edge_up() {
  pg_set_password ratatoskr_edge || return 1
  conf_edge "${1:-}" || return 1
  svc_start edge
  svc_wait_ready edge 90 || return 1
  pg_grants
}

# Maps the second Platform user on both archive receivers and restarts them (flow F1 section s13): until then user 2 is deliberately unmapped so that the 403 for an unmapped user can be observed.
map_second_user() {
  conf_chatgpt "$U1=smoke-chatgpt-account-1,$U2=smoke-chatgpt-account-2" || return 1
  conf_claude "$U1=00000000-0000-7000-8000-0000000000b1,$U2=00000000-0000-7000-8000-0000000000b2" || return 1
  pid_stop chatgpt
  pid_stop claude
  svc_start chatgpt
  svc_start claude
  svc_wait_ready chatgpt 60 && svc_wait_ready claude 60
}


# upload_archive PROVIDER FILE DEVICE_CREDENTIAL: the export agent's sequence for an archive of one chunk (at most 64 KiB): prepare, open, PUT, finalize, poll; sets ARCHIVE_STATUS. Needs lib/assert.sh for call and pollop.
upload_archive() {
  local provider=$1 file=$2 device=$3 sha size status operation upload_path token
  sha=$(sha256_file "$file")
  size=$(wc -c <"$file" | tr -d ' ')
  local t0 tries
  t0=$(date +%s)
  while :; do
    status=$(call prepare POST "$EDGE/v1/ai-archives/$provider" "$device" "$(jq -nc --arg s "$sha" --argjson n "$size" '{sha256:$s,byte_size:$n}')" "smoke-ai-$sha")
    [[ "$status" != 404 ]] && break
    (($(date +%s) - t0 >= 150)) && break
    sleep 3
  done
  operation=$(jq -r .operation_id "$EV/prepare.resp.body")
  upload_path=$(jq -r .upload_path "$EV/prepare.resp.body")
  [[ "$upload_path" == /* ]] || upload_path=/$upload_path
  status=$(call open POST "$EDGE$upload_path" "$device" "$(jq -nc --arg s "$sha" --argjson n "$size" '{declared_size_bytes:$n,media_type:"application/zip",digest:{algorithm:"sha256",hex:$s},chunk_size_bytes:65536}')")
  token=$(jq -r .resumption_token "$EV/open.resp.body")
  curl -s -o "$EV/chunk0.resp.body" -X PUT -H "Authorization: Bearer $device" -H 'Content-Type: application/octet-stream' --data-binary @"$file" "$EDGE$upload_path/$token/chunks/0" >/dev/null
  status=$(call finalize POST "$EDGE$upload_path/$token/finalize" "$device" "$(jq -nc --arg t "$token" '{resumption_token:$t}')")
  ARCHIVE_STATUS=$(pollop "$operation" "$device" 150 ai)
}
