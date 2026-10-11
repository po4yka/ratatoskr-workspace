#!/usr/bin/env bash
# shellcheck disable=SC2034
# F0 Topology and provisioning (Edge, no flow). Sourced by run.sh; defines the flow, runs nothing.
#
# Provenance: assembled from the by-hand runs under .workspaces/XR-021/smoke/{ai,kp} (infrastructure, durables, roles) and written new for the inbox probes of R3-01. Run through run.sh as committed: NO. The Round 3 smoke results in the changeset came from the by-hand scripts.

FLOW_ID=f0
FLOW_TITLE="Topology and provisioning (Edge, no flow): roles, durables, inbox ACL, 8 MiB limit"
FLOW_BINARIES=("platform:ratatoskr-edge render-nats-config")
FLOW_PORTS="$INFRA_PORTS"
FLOW_REPOS="platform"
FLOW_EVIDENCE="by-hand run in the Round 3 AI-archive and Knowledge smokes covered steps 1 to 3 and 5; the inbox probes of step 4 were not run before this harness"
FLOW_HONESTY=(
  "seeded: none in this flow"
  "faked: nothing"
  "not exercised: any service other than Edge; the roles are exercised only by connecting as each one"
)

# identity|nk file|own prefix|stream|owned durable (empty when the identity owns none)
F0_IDENTITIES=(
  "telegram|telegram|_INBOX_telegram|ratatoskr_events|ratatoskr_telegram_notifications"
  "chatgpt|chatgpt|_INBOX_chatgpt||"
  "claude|claude|_INBOX_claude||"
  "x|x|_INBOX_x|ratatoskr_commands|ratatoskr_x_browser_capture"
  "instagram|instagram|_INBOX_instagram|ratatoskr_commands|ratatoskr_instagram_browser_capture"
  "threads|threads|_INBOX_threads|ratatoskr_commands|threads_browser_capture"
  "extractor|extractor|_INBOX_extractor|ratatoskr_commands|ratatoskr_extractor_capture"
  "extractor-browser-worker|extractor-browser-worker|_INBOX_extractor_browser_worker|ratatoskr_commands|ratatoskr_browser_worker"
  "knowledge|knowledge|_INBOX_knowledge|ratatoskr_events|ratatoskr_knowledge_documents"
  "github|github|_INBOX_github|ratatoskr_events|ratatoskr_github_analysis_completed"
  "vault|vault|_INBOX_vault|ratatoskr_commands|ratatoskr_vault_backup_policy"
  "channel-digests|channel-digests|_INBOX_channel_digests|ratatoskr_commands|ratatoskr_channel_digest_runs"
)

# repository|role: every role file of the fleet, run as written.
F0_ROLES=(
  "extractor|ratatoskr_extractor" "chatgpt|ratatoskr_chatgpt" "claude|ratatoskr_claude" "knowledge|ratatoskr_knowledge"
  "channel-digests|ratatoskr_channel_digests" "telegram|ratatoskr_telegram" "x|ratatoskr_x" "instagram|ratatoskr_instagram"
  "threads|ratatoskr_threads" "vault|ratatoskr_vault" "github|ratatoskr_github"
)

flow_run() {
  infra_fresh || { assert infra_up 'false' "PostgreSQL or NATS did not start"; return; }
  assert nats_diff_is_only_host_http_and_store_dir '[ "$(grep -c "^[<>]" "$EV/nats-conf.diff")" = 6 ]' "$(grep "^[<>]" "$EV/nats-conf.diff" | tr "\n" "|" | cut -c1-300)"
  assert nats_max_payload_8MiB '[ "$(curl -s "$NATS_MON/varz" | jq .max_payload)" = 8388608 ]'
  assert nats_max_file_store_kept_8GB '[ "$(curl -s "$NATS_MON/jsz" | jq .config.max_storage)" = 8589934592 ]'

  info "step 1: Edge starts with every receiver down"
  edge_up || { assert edge_started 'false' "Edge did not become ready"; return; }
  assert edge_ready_with_every_receiver_down '[ "$(code "$EDGE_ADMIN/health/ready")" = 200 ]' "R3-13: the receiver checks are reported, they do not gate readiness"
  assert edge_public_listening '[ "$(code "$EDGE/v1/capabilities")" != 000 ]'

  info "step 2: every role.sql as written, and each role connects as itself without privileges"
  local row repo role as_role role_rc
  for row in "${F0_ROLES[@]}"; do
    IFS='|' read -r repo role <<<"$row"
    pg_role "$repo" "$role"
    role_rc=$?
    assert "role_file_ran_as_written_$role" '[ "$role_rc" = 0 ]' "rc=$role_rc $(tail -1 "$EV/provision-role-$role.txt" 2>/dev/null)"
    as_role=$(PGPASSWORD=$(pg_password "$role") PGHOST=127.0.0.1 psql -X -At "postgres://$role@127.0.0.1:$PG_PORT/ratatoskr" -c "select current_user || '|' || (select rolsuper::text || rolcreatedb::text || rolcreaterole::text || rolreplication::text || rolbypassrls::text from pg_roles where rolname = current_user)" 2>&1)
    assert "role_connects_unprivileged_$role" '[ "$as_role" = "$role|falsefalsefalsefalsefalse" ]' "$as_role"
  done
  assert pgvector_created_by_the_knowledge_role_file '[ "$(q ratatoskr "select count(*) from pg_extension where extname='"'"'vector'"'"'")" = 1 ]'

  info "step 3: the durables of S04"
  assert_s04_durables

  info "step 4: inbox ACL (R3-01) with the real seeds"
  wc -l <"$S/logs/nats.log" >"$S/run/probe.begin"
  local entry name file prefix stream durable other probe own_ok
  for entry in "${F0_IDENTITIES[@]}"; do
    IFS='|' read -r name file prefix stream durable <<<"$entry"
    other=_INBOX_edge_foreign
    for row in "${F0_IDENTITIES[@]}"; do
      [[ "${row%%|*}" != "$name" ]] && { other=$(cut -d'|' -f3 <<<"$row"); break; }
    done
    probe=$(python3 -I "$NATIVE_ROOT/fixtures/natsprobe.py" acl "$S/nk/$file.nkey" "$prefix" "$other" "$stream" "$durable" 2>"$EV/probe-$name.err")
    echo "$probe" >"$EV/probe-$name.json"
    assert "inbox_shared_namespace_refused_$name" '[ "$(jq -r .shared_inbox_refused <<<"$probe")" = true ]' "$probe"
    assert "inbox_foreign_prefix_refused_$name" '[ "$(jq -r .foreign_inbox_refused <<<"$probe")" = true ]' "foreign=$other"
    assert "inbox_own_prefix_allowed_$name" '[ "$(jq -r .own_inbox_allowed <<<"$probe")" = true ]'
    if [[ -n "$durable" ]]; then
      assert "own_durable_info_allowed_$name" '[ "$(jq -r .owned_consumer_info_ok <<<"$probe")" = true ]' "$durable"
    fi
  done
  sleep 1
  wc -l <"$S/logs/nats.log" >"$S/run/probe.end"
  local expected=$((${#F0_IDENTITIES[@]} * 3)) window
  window=$(awk -v b="$(cat "$S/run/probe.begin")" -v e="$(cat "$S/run/probe.end")" 'NR > b && NR <= e && /Publish Violation|Subscription Violation/ { n++ } END { print n + 0 }' "$S/logs/nats.log")
  assert probe_window_holds_the_deliberate_violations '[ "$window" -ge "$expected" ]' "violations in the probe window: $window, expected at least $expected (two refused subscriptions and one refused publish per identity)"
}

