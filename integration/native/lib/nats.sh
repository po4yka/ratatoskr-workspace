#!/usr/bin/env bash
# shellcheck disable=SC2034
# NATS for the native smoke: the deployed ACL of Platform's deploy/nats/ratatoskr.conf with fresh nkeys, on the production ports 4222 and 8222. Source after lib/common.sh.
#
# nk, nsc and the nats CLI are not installed on the machine this was built for, so the nkeys come from Platform's own render-nats-config (build it with build_bins platform render-nats-config). Only host, the monitoring bind and jetstream.store_dir change; the diff against the deployed file is saved as evidence and must show nothing else besides the nkey lines. max_payload 8MB and max_file_store 8GB stay: a smaller max_file_store stops Edge at the KV bucket.

NATS_IDENTITY_COUNT=13

nats_up() {
  local render=$S/render
  rm -rf -- "${render:?}"/* 2>/dev/null
  "$S/bin/render-nats-config" "$(repo_dir platform)/deploy/nats/ratatoskr.conf" "$render" >"$S/logs/render-nats.log" 2>&1 || { note "nats: render-nats-config failed"; return 1; }
  local seed
  for seed in "$render"/*.nkey; do
    cp "$seed" "$S/nk/$(basename "$seed")"
    chmod 600 "$S/nk/$(basename "$seed")"
  done
  RENDERED="$render/ratatoskr.conf" OUT="$S/nats.conf" STORE="$S/nats-js" python3 -I - <<'PY' || return 1
import os, pathlib, re
text = pathlib.Path(os.environ["RENDERED"]).read_text()
text, host = re.subn(r"^host: 0\.0\.0\.0$", "host: 127.0.0.1", text, flags=re.M)
text, http = re.subn(r"^http: 0\.0\.0\.0:8222$", "http: 127.0.0.1:8222", text, flags=re.M)
text, store = re.subn(r"^(\s*)store_dir: .*$", lambda m: m.group(1) + "store_dir: " + os.environ["STORE"], text, flags=re.M)
assert (host, http, store) == (1, 1, 1), (host, http, store)
out = pathlib.Path(os.environ["OUT"])
out.write_text(text)
out.chmod(0o600)
PY
  diff <(sed -E 's/nkey: .*/nkey: <NKEY>/' "$(repo_dir platform)/deploy/nats/ratatoskr.conf") <(sed -E 's/nkey: .*/nkey: <NKEY>/' "$S/nats.conf") >"$EV/nats-conf.diff"
  nats-server -t -c "$S/nats.conf" >"$S/logs/nats-test.log" 2>&1 || { note "nats: configuration test failed"; return 1; }
  nohup nats-server -c "$S/nats.conf" -l "$S/logs/nats.log" >"$S/logs/nats.stdout" 2>&1 &
  echo $! >"$S/run/nats.pid"
  local i
  for ((i = 0; i < 30; i++)); do
    curl -fsS "$NATS_MON/healthz" >/dev/null 2>&1 && break
    sleep 1
  done
  curl -s "$NATS_MON/varz" | jq '{port, max_payload, host}' >"$EV/varz.json"
  curl -s "$NATS_MON/jsz" | jq '.config | {max_memory, max_storage}' >"$EV/jsz-config.json"
  note "nats: up ($(ls "$S"/nk/*.nkey | wc -l | tr -d ' ') identities)"
}

# Stops the broker through the pid file nats_up wrote: SIGTERM, 15 seconds, then SIGKILL of that pid only.
nats_down() { pid_stop nats; }

# The broker has to be restartable on purpose (F2 outage leg): same configuration, same store.
nats_restart() {
  nohup nats-server -c "$S/nats.conf" -l "$S/logs/nats.log" >>"$S/logs/nats.stdout" 2>&1 &
  echo $! >"$S/run/nats.pid"
  local i
  for ((i = 0; i < 30; i++)); do
    curl -fsS "$NATS_MON/healthz" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

# The S04 table: durable, filter, ack wait in seconds, max_deliver. Edge provisions every one of them at startup.
S04_DURABLES=(
  "ratatoskr_extractor_capture|cmd.content.capture.requested.v1|30|12"
  "ratatoskr_browser_worker|cmd.content.render.requested.v1|300|12"
  "ratatoskr_knowledge_channel_recap|cmd.knowledge.channel_digest_recap.requested.v1|30|-1"
  "ratatoskr_channel_digest_subscriptions|cmd.channel_digest.subscription.set_requested.v1|30|-1"
  "ratatoskr_channel_digest_runs|cmd.channel_digest.run.requested.v1|30|-1"
  "ratatoskr_channel_digest_schedule_occurrences|cmd.channel_digest.schedule.occurrence_requested.v1|30|-1"
  "ratatoskr_vault_backup_policy|cmd.vault.backup_policy.apply_requested.v1|30|-1"
  "ratatoskr_knowledge_documents|evt.content.document.extracted.v1|120|-1"
  "ratatoskr_knowledge_social_sources|evt.social.source.>|120|-1"
  "ratatoskr_knowledge_ai_archive|evt.ai_archive.>|120|-1"
  "ratatoskr_knowledge_repository_requests|evt.knowledge.repository_analysis.requested.v1|120|-1"
  "ratatoskr_github_analysis_completed|evt.knowledge.repository_analysis.completed.v1|30|-1"
  "ratatoskr_github_analysis_failed|evt.knowledge.repository_analysis.failed.v1|30|-1"
  "ratatoskr_github_policy_acknowledged|evt.vault.backup_policy.acknowledged.v1|30|-1"
  "ratatoskr_x_extractor_reports|evt.platform.operation.reported.v1|30|-1"
  "ratatoskr_channel_digest_recap_completed|evt.knowledge.channel_digest_recap.completed.v1|30|-1"
  "ratatoskr_channel_digest_recap_failed|evt.knowledge.channel_digest_recap.failed.v1|30|-1"
)

# Asserts that every durable of the S04 table exists with its filter, ack wait and max_deliver, and writes durables.tsv.
assert_s04_durables() {
  local row durable_name durable_filter durable_wait durable_max
  jsz | jq -r '.account_details[].stream_detail[].consumer_detail[]? | [.stream_name, .name, .config.filter_subject, (.config.ack_wait/1e9|floor|tostring), (.config.max_deliver|tostring), (.config.ack_policy|tostring)] | @tsv' >"$EV/durables.tsv"
  for row in "${S04_DURABLES[@]}"; do
    IFS='|' read -r durable_name durable_filter durable_wait durable_max <<<"$row"
    assert "durable_$durable_name" '[ "$(dur "$durable_name")" = "$durable_filter $durable_wait $durable_max" ]' "$(dur "$durable_name")"
  done
  assert durable_render_awaits_is_ack_none '[ "$(awk -F"\t" "\$2==\"ratatoskr_extractor_render_awaits\" {print \$6}" "$EV/durables.tsv")" = none ]' "$(awk -F'\t' '$2=="ratatoskr_extractor_render_awaits" {print $6}' "$EV/durables.tsv")"
  assert kv_bucket_browser_worker_completions '[ "$(curl -s "$NATS_MON/jsz?streams=true" | jq "[.account_details[].stream_detail[].name] | index(\"KV_browser_worker_completions\") != null")" = true ]'
}
