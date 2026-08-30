#!/bin/sh
set -eu

server=nats://127.0.0.1:4222
seed=/run/ghb017/platform.nkey
source_file=/platform/crates/eventing/src/stream.rs

for expected in \
  ratatoskr_github_sync \
  ratatoskr_github_analysis_completed \
  ratatoskr_github_analysis_failed \
  ratatoskr_github_vault_policy_ack
do
  grep -q "$expected" "$source_file"
done

if ! nats --server "$server" --nkey "$seed" stream info ratatoskr_commands >/dev/null 2>&1; then
  nats --server "$server" --nkey "$seed" stream add ratatoskr_commands \
    --subjects 'cmd.>' --storage file --retention limits --discard new --max-bytes 1073741824 \
    --max-age 168h --dupe-window 2m --replicas 1 --defaults
fi
if ! nats --server "$server" --nkey "$seed" stream info ratatoskr_events >/dev/null 2>&1; then
  nats --server "$server" --nkey "$seed" stream add ratatoskr_events \
    --subjects 'evt.>' --storage file --retention limits --discard old --max-bytes 1073741824 \
    --max-age 168h --dupe-window 2m --replicas 1 --defaults
fi

add_consumer() {
  stream=$1
  durable=$2
  filter=$3
  if ! nats --server "$server" --nkey "$seed" consumer info "$stream" "$durable" >/dev/null 2>&1; then
    nats --server "$server" --nkey "$seed" consumer add "$stream" "$durable" \
      --filter "$filter" --ack explicit --deliver all --replay instant --wait 2m \
      --max-deliver 10 --pull --defaults
  fi
}

add_consumer ratatoskr_commands ratatoskr_github_sync cmd.github.sync.requested.v1
add_consumer ratatoskr_events ratatoskr_github_analysis_completed \
  evt.knowledge.repository_analysis.completed.v1
add_consumer ratatoskr_events ratatoskr_github_analysis_failed \
  evt.knowledge.repository_analysis.failed.v1
add_consumer ratatoskr_events ratatoskr_github_vault_policy_ack \
  evt.vault.backup_policy.acknowledged.v1
