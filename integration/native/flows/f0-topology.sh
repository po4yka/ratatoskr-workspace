#!/usr/bin/env bash
# shellcheck disable=SC2034
# F0 Topology and provisioning (Edge, no flow). Sourced by run.sh; defines the flow, runs nothing.
#
# Provenance: assembled from the by-hand runs under .workspaces/XR-021/smoke/{ai,kp} (infrastructure, durables, roles) and written new for the inbox probes of R3-01. Round 4 added the legs of step 5 (R4-08, R4-11 and the max_payload probe). Run through run.sh as committed in Round 5 (the results are in README.md).

FLOW_ID=f0
FLOW_TITLE="Topology and provisioning (Edge, no flow): roles, durables, inbox ACL, 8 MiB limit, notification ack wait"
FLOW_BINARIES=("platform:ratatoskr-edge render-nats-config" "telegram:ratatoskr-telegram-dispatcher ratatoskr-telegram-webhook")
FLOW_PORTS="$INFRA_PORTS"
FLOW_REPOS="platform telegram extractor chatgpt claude knowledge channel-digests x instagram threads vault github"
FLOW_EVIDENCE="by-hand run in the Round 3 AI-archive and Knowledge smokes covered steps 1 to 3 and 5; the inbox probes of step 4 were not run before this harness"
FLOW_HONESTY=(
  "seeded: none in this flow"
  "faked: nothing; the oversize probe declares a 9 MiB publish and sends the PUB header only, because the broker checks the declared size when it parses the line (no 9 MiB payload crosses the socket)"
  "deviation: the dispatcher runs only its check-config command, from its shipped example with RATATOSKR__NOTIFICATION_BUS__ACK_WAIT_SECONDS set to 31 and then to 30; no dispatcher process is started"
  "faked (R5): the lag leg publishes three probe messages with the ChatGPT identity to evt.ai_archive.archive.imported.v1; they are not archive facts, nothing consumes them in this flow, and the NATS store is deleted at the end. The ACL probes publish marker payloads and read the broker's log for the violation"
  "not exercised: any service other than Edge; the roles are exercised only by connecting as each one; the fall of the lag series to zero when the consumer starts is shown in F2 (the outage leg)"
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
    probe=$("$PY" -I "$NATIVE_ROOT/fixtures/natsprobe.py" acl "$S/nk/$file.nkey" "$prefix" "$other" "$stream" "$durable" 2>"$EV/probe-$name.err")
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

  info "step 5: the 8 MiB ceiling, the notification ack wait (R4-08) and the idle notification subject (R4-11)"
  local oversize rc31=0 rc30=0
  oversize=$("$PY" -I "$NATIVE_ROOT/fixtures/natsprobe.py" oversize "$S/nk/edge.nkey" cmd.content.capture.requested.v1 9437184 2>"$EV/oversize.err")
  echo "$oversize" >"$EV/oversize.json"
  assert broker_refuses_a_publish_above_max_payload '[ "$(jq -r .refused <<<"$oversize")" = true ]' "$oversize"
  # The dispatcher refuses to start without its Platform assertion key, so the key comes from the webhook's own command first; with it, an ack wait of 31 is the only problem check-config can name.
  "$S/bin/ratatoskr-telegram-webhook" assertion-key generate "$S/keys/telegram-signing-key" >/dev/null 2>"$EV/assertion-key-generate.err"
  conf_dispatcher_variant dispatcher-ack31 31 || return
  conf_dispatcher_variant dispatcher-ack30 30 || return
  "$PY" -I "$NATIVE_ROOT/lib/envrun.py" "$S/conf/dispatcher-ack31.env" "$S/bin/ratatoskr-telegram-dispatcher" check-config >"$EV/dispatcher-check-config-31.out" 2>&1 || rc31=$?
  "$PY" -I "$NATIVE_ROOT/lib/envrun.py" "$S/conf/dispatcher-ack30.env" "$S/bin/ratatoskr-telegram-dispatcher" check-config >"$EV/dispatcher-check-config-30.out" 2>&1 || rc30=$?
  assert dispatcher_check_config_refuses_an_ack_wait_of_31 '[ "$rc31" != 0 ] && grep -Eqi "notification_bus.ack_wait" "$EV/dispatcher-check-config-31.out" && grep -Eqi "1 configuration problem" "$EV/dispatcher-check-config-31.out"' "rc=$rc31: $(head -c 240 "$EV/dispatcher-check-config-31.out" | tr "\n" " ")"
  assert dispatcher_check_config_accepts_an_ack_wait_of_30 '[ "$rc30" = 0 ]' "rc=$rc30: $(head -c 240 "$EV/dispatcher-check-config-30.out" | tr "\n" " ")"
  "$PY" -I "$NATIVE_ROOT/fixtures/natsprobe.py" stream "$S/nk/edge.nkey" ratatoskr_events 'evt.platform.notification.>' >"$EV/notification-subjects.json" 2>&1
  assert nothing_is_published_to_the_notification_subject '[ "$(jq -r ".subjects // {} | length" "$EV/notification-subjects.json" 2>/dev/null || echo error)" = 0 ]' "R4-11: nothing in the fleet raises a notification; the dispatcher's durable stays idle"
  assert the_notification_durable_has_nothing_pending '[ "$(pending ratatoskr_telegram_notifications)" = 0 ]' "pending + ack-pending: $(pending ratatoskr_telegram_notifications)"

  f0_deletion_delivery_acl
  f0_bus_observability
}

# violations_of SUBJECT: how many Publish Violations the NATS log holds for a subject since the probe window began.
violations_of() { awk -v b="$(cat "$S/run/probe.begin")" -v subject="$1" 'NR > b && /Publish Violation/ && index($0, "Subject \"" subject "\"") { n++ } END { print n + 0 }' "$S/logs/nats.log"; }
# answered IDENTITY-NKEY-FILE PREFIX STREAM DURABLE: whether the identity may pull from a durable (a pull request the ACL does not allow is dropped without an answer).
answered() { "$PY" -I "$NATIVE_ROOT/fixtures/natsprobe.py" fetch "$S/nk/$1.nkey" "$2" "$3" "$4" "${5:-2}" | jq -r .answered; }

# R5-11 and R5-12 on the deployed ACL, with the real seeds, inside the probe window: producers cannot touch the stream, can ask Edge to erase their own messages, and cannot forge Knowledge's acknowledgement; each of the five producers reads its own acknowledgement durable and no sibling's.
f0_deletion_delivery_acl() {
  info "step 6: deletion delivery and stream erasure on the deployed ACL (R5-11, R5-12), probes with the real seeds"
  local probe="$NATIVE_ROOT/fixtures/natsprobe.py" erase=cmd.platform.stream_erasure.requested.v1 ack=evt.knowledge.deletion.acknowledged.v1 who subject before
  for who in chatgpt claude; do
    for subject in '$JS.API.STREAM.MSG.DELETE.ratatoskr_events' '$JS.API.STREAM.PURGE.ratatoskr_events'; do
      before=$(violations_of "$subject")
      "$PY" -I "$probe" publish "$S/nk/$who.nkey" "_INBOX_$who" "$subject" '{"seq":1}'
      sleep 0.5
      assert "acl_${who}_cannot_publish_${subject//[^A-Za-z]/_}" '[ "$(violations_of "$subject")" -gt "$before" ]' "violations $before -> $(violations_of "$subject")"
    done
    before=$(violations_of "$erase")
    "$PY" -I "$probe" publish "$S/nk/$who.nkey" "_INBOX_$who" "$erase" '{"probe":"f0"}'
    sleep 0.5
    assert "acl_${who}_can_publish_the_stream_erasure_command" '[ "$(violations_of "$erase")" = "$before" ]' "no Publish Violation for $erase"
    before=$(violations_of "$ack")
    "$PY" -I "$probe" publish "$S/nk/$who.nkey" "_INBOX_$who" "$ack" '{"probe":"f0"}'
    sleep 0.5
    assert "acl_${who}_cannot_forge_the_knowledge_acknowledgement" '[ "$(violations_of "$ack")" -gt "$before" ]' "violations $before -> $(violations_of "$ack")"
  done
  before=$(violations_of "$ack")
  "$PY" -I "$probe" publish "$S/nk/knowledge.nkey" _INBOX_knowledge "$ack" '{"probe":"f0"}'
  sleep 0.5
  assert acl_knowledge_can_publish_the_acknowledgement '[ "$(violations_of "$ack")" = "$before" ]'
  before=$(violations_of "$erase")
  "$PY" -I "$probe" publish "$S/nk/knowledge.nkey" _INBOX_knowledge "$erase" '{"probe":"f0"}'
  sleep 0.5
  assert acl_knowledge_cannot_publish_the_erasure_command '[ "$(violations_of "$erase")" -gt "$before" ]' "violations $before -> $(violations_of "$erase")"

  local producers=(chatgpt claude x instagram threads) other own_answer
  for who in "${producers[@]}"; do
    own_answer=$(answered "$who" "_INBOX_$who" ratatoskr_events "ratatoskr_${who}_deletion_acks")
    assert "ack_durable_${who}_reads_its_own" '[ "$own_answer" = true ]' "pull request answered: $own_answer"
    for other in "${producers[@]}"; do
      [[ "$other" == "$who" ]] && continue
      assert "ack_durable_${who}_cannot_read_the_${other}_durable" '[ "$(answered "$who" "_INBOX_$who" ratatoskr_events "ratatoskr_${other}_deletion_acks" 1)" = false ]'
    done
  done
  assert edge_internal_stream_erasure_durable_exists '[ "$(dur platform_stream_erasure | cut -d" " -f1)" = cmd.platform.stream_erasure.requested.v1 ]' "$(dur platform_stream_erasure)"
  wc -l <"$S/logs/nats.log" >"$S/run/probe.end"
}

# R5-13: the bus series Edge exports on 9464 follow a stuck consumer and move when it is drained. Knowledge is not running in this flow, so N well-formed-looking probe facts (labelled: they are not archive facts) sit undelivered on the durable of Knowledge's AI-archive intake.
f0_bus_observability() {
  info "step 7: bus lag series on 127.0.0.1:9464 (R5-13); N=3 probe messages published with the ChatGPT identity to a durable nobody consumes"
  local n=3 age1 age2 durable='durable="ratatoskr_knowledge_ai_archive"' i
  for ((i = 0; i < n; i++)); do
    "$PY" -I "$NATIVE_ROOT/fixtures/natsprobe.py" publish "$S/nk/chatgpt.nkey" _INBOX_chatgpt evt.ai_archive.archive.imported.v1 '{"probe":"f0-lag"}'
  done
  untilt '[ "$(metric 9464 platform_bus_consumer_pending "$durable")" = "$n" ]' 40
  assert lag_series_pending_equals_the_published_count '[ "$(metric 9464 platform_bus_consumer_pending "$durable")" = "$n" ]' "pending=$(metric 9464 platform_bus_consumer_pending "$durable")"
  age1=$(metric 9464 platform_bus_consumer_oldest_unacked_age_seconds "$durable")
  sleep 20
  age2=$(metric 9464 platform_bus_consumer_oldest_unacked_age_seconds "$durable")
  assert oldest_unacked_age_is_above_zero_and_rises '"$PY" -c "import sys; a, b = float(sys.argv[1]), float(sys.argv[2]); sys.exit(0 if 0 < a < b else 1)" "$age1" "$age2"' "age $age1 -> $age2 seconds"
  assert stream_bytes_and_ceiling_are_exported '[ "$(metric 9464 platform_bus_stream_bytes '"'"'stream="ratatoskr_events"'"'"')" -ge 0 ] && [ "$(metric 9464 platform_bus_stream_max_bytes '"'"'stream="ratatoskr_events"'"'"')" -gt 0 ]' "bytes $(metric 9464 platform_bus_stream_bytes 'stream="ratatoskr_events"') of $(metric 9464 platform_bus_stream_max_bytes 'stream="ratatoskr_events"')"
  local rules
  rules=$(repo_dir platform)/deploy/monitoring/ratatoskr-bus-alerts.rules.yml
  if "$PY" -c 'import yaml' 2>/dev/null; then
    assert alert_rules_file_parses_as_yaml '"$PY" -c "import sys, yaml; d = yaml.safe_load(open(sys.argv[1])); assert d[\"groups\"] and all(r.get(\"for\") and r[\"labels\"][\"severity\"] and r[\"annotations\"][\"summary\"] for g in d[\"groups\"] for r in g[\"rules\"] if \"alert\" in r)" "$rules"' "$rules"
  elif command -v ruby >/dev/null 2>&1; then
    assert alert_rules_file_parses_as_yaml 'ruby -ryaml -e "d = YAML.load_file(ARGV[0]); abort unless d[%q(groups)].all? { |g| g[%q(rules)].all? { |r| !r[%q(alert)] || (r[%q(for)] && r[%q(labels)][%q(severity)] && r[%q(annotations)][%q(summary)]) } }" "$rules"' "$rules (ruby)"
  else
    info "NOT RUN: the alert rule file was not parsed; the selected python has no PyYAML and ruby is not installed"
  fi
}
