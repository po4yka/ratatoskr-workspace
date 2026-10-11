#!/usr/bin/env bash
# shellcheck disable=SC2034
# F4 Channel digests (Edge, channel-digests API and worker, Knowledge; R3-09, R3-10, R2-05). Sourced by run.sh; defines the flow, runs nothing.
#
# Provenance: ported from the by-hand channel-digests smoke of Round 3 (.workspaces/XR-021/smoke/cdr3: legA, legRun1, legRun2, legRun3, legNeg), which was reported passed with MTProto acquisition faulted. Knowledge runs the recap in the shipped openrouter mode against a loopback fake (the scripted provider is refused by the deployed ACL by design). Run through run.sh as committed: NO.

FLOW_ID=f4
FLOW_TITLE="Channel digests: subscription set, run deadline, recap (faulted acquisition), read hop, schedule owner"
FLOW_BINARIES=("platform:ratatoskr-edge render-nats-config" "knowledge:ratatoskr-knowledge-service" "channel-digests:ratatoskr-channel-digests-api ratatoskr-channel-digests-worker")
FLOW_PORTS="$INFRA_PORTS 8091 9081 8098 9469 9470 $FAKE_OPENROUTER_PORT"
FLOW_REPOS="platform knowledge channel-digests"
FLOW_EVIDENCE="by-hand run in Round 3 (cdr3): ran, passed, with the MTProto hop faulted and OpenRouter faked; the logging assertions are new"
FLOW_HONESTY=(
  "faked: OpenRouter is a loopback fake, so the recap text is not a live provider result"
  "FAULTED HOP: the MTProto acquisition. fixtures/legb (the 'legb' helper) commits a manifest of two synthetic posts through the service's own ManifestBuilder and DigestCoordinator::commit_manifest for a run the real worker accepted; everything after the commit is the real path"
  "seeded: two users and their browser sessions (fixtures/platform-seed.sql)"
  "not exercised: leg C, partial acquisition. MTProto cannot be faked without credentials; the repository's executor tests are the evidence"
  "deviations: RATATOSKR__LIMITS__RUN_DEADLINE_SECONDS=60 and a dummy API_HASH; the worker's provider session file is a synthetic encrypted session whose connection fails, so the worker logs provider_unavailable and stays not ready while its bus intake works"
)

flow_run() {
  infra_fresh || { assert infra_up 'false' "PostgreSQL or NATS did not start"; return; }
  edge_up || { assert edge_started 'false' "Edge did not become ready"; return; }
  assert_s04_durables
  seed_principals
  local row repo role
  for row in "channel-digests|ratatoskr_channel_digests" "knowledge|ratatoskr_knowledge"; do
    IFS='|' read -r repo role <<<"$row"
    pg_role "$repo" "$role" || { assert "role_$role" 'false' "role.sql failed"; return; }
  done
  mkdir -p "$S/blobs/knowledge"
  fake_start fake-openrouter fake_openrouter.py "$FAKE_OPENROUTER_PORT" "$S/logs/fake-openrouter.jsonl" "$S/run"
  conf_knowledge true && conf_api && conf_worker 60 "$U1" || return
  svc_start knowledge
  svc_start api
  svc_start worker
  svc_wait_ready knowledge 90
  svc_wait_ready api 60
  local T1 T2 status op rid
  T1=$(secret browser1)
  T2=$(secret browser2)
  sleep 5
  assert api_ready '[ "$(code 127.0.0.1:9469/ready)" = 200 ]'
  assert api_listener_requires_a_bearer '[ "$(code 127.0.0.1:8098/ready)" = 401 ]'
  info "the worker is not ready without MTProto credentials: $(code 127.0.0.1:9470/ready); its bus intake works"
  assert worker_logs_the_closed_class_and_is_not_silent '[ "$(rg -c "provider_unavailable" "$S/logs/worker.log" || true)" -ge 1 ]' "R3-10 rule 5: the binaries install a tracing subscriber"
  assert api_log_is_not_empty '[ -s "$S/logs/api.log" ]'

  info "leg A: subscription set, the read hop, idempotency"
  status=$(call noauth PUT "$EDGE/v1/channel-digests/subscriptions/smoke_alpha" "" '{"desired_state":"active"}' k0)
  assert no_bearer_is_401 '[ "$status" = 401 ]' "http=$status"
  status=$(call put-sub PUT "$EDGE/v1/channel-digests/subscriptions/smoke_alpha" "$T1" '{"desired_state":"active"}' cd-r3-sub-1)
  op=$(jq -r .operation_id "$EV/put-sub.resp.body")
  assert subscription_set_accepted '[ "$status" = 202 ]' "http=$status"
  assert subscription_operation_succeeded '[ "$(pollop "$op" "$T1" 60 sub)" = succeeded ]'
  status=$(call put-sub-replay PUT "$EDGE/v1/channel-digests/subscriptions/smoke_alpha" "$T1" '{"desired_state":"active"}' cd-r3-sub-1)
  assert replay_returns_the_same_operation '[ "$status" = 202 ] && [ "$(jq -r .operation_id "$EV/put-sub-replay.resp.body")" = "$op" ]'
  status=$(call list-subs GET "$EDGE/v1/channel-digests/subscriptions" "$T1")
  assert read_hop_through_edge_to_the_api_lists_it '[ "$status" = 200 ] && jq -e ".subscriptions[] | select(.channel_username==\"smoke_alpha\" and .enabled==true)" "$EV/list-subs.resp.body" >/dev/null' "http=$status"
  status=$(call list-subs-u2 GET "$EDGE/v1/channel-digests/subscriptions" "$T2")
  assert another_owner_sees_an_empty_list '[ "$status" = 200 ] && [ "$(jq ".subscriptions | length" "$EV/list-subs-u2.resp.body")" = 0 ]'
  svc_stop api
  sleep 10
  assert knowledge_ready_while_the_digest_api_is_stopped '[ "$(code 127.0.0.1:9081/ready)" = 200 ]' "R3-09: reachability of the source does not gate readiness"
  svc_start api
  svc_wait_ready api 60

  info "the worker's schedule registration reached Edge, and a stranger's owner is refused (R2-14)"
  untilt '[ "$(q ratatoskr "select count(*) from operations.schedules where service_name like '"'"'%channel-digests%'"'"'")" -ge 1 ]' 60
  assert schedule_registration_reached_edge '[ "$(q ratatoskr "select count(*) from operations.schedules where service_name like '"'"'%channel-digests%'"'"'")" -ge 1 ]' "$(q ratatoskr "select name from operations.schedules" | tr "\n" ",")"
  assert registration_audited_allowed '[ "$(q ratatoskr "select count(*) from identity.audit_events where action='"'"'schedule.registration'"'"' and outcome='"'"'allowed'"'"'")" -ge 1 ]'
  local schedules_before
  schedules_before=$(q ratatoskr "select count(*) from operations.schedules")
  svc_stop worker
  conf_worker 60 "$(python3 -c 'import uuid;print(uuid.uuid4())')" || return
  svc_start worker
  untilt '[ "$(q ratatoskr "select count(*) from identity.audit_events where action='"'"'schedule.registration'"'"' and outcome='"'"'denied'"'"'")" -ge 1 ]' 60
  assert unknown_owner_registration_is_audited_denied '[ "$(q ratatoskr "select count(*) from identity.audit_events where action='"'"'schedule.registration'"'"' and outcome='"'"'denied'"'"'")" -ge 1 ]'
  assert edge_logs_the_closed_class '[ "$(rg -c "schedule_owner_unknown" "$S/logs/edge.log" || true)" -ge 1 ]'
  assert no_second_schedule_row '[ "$(q ratatoskr "select count(*) from operations.schedules")" = "$schedules_before" ]'
  svc_stop worker
  conf_worker 60 "$U1" || return
  svc_start worker
  sleep 5

  info "leg Run1: no acquisition possible, the run waits and then fails at its deadline"
  status=$(call post-run1 POST "$EDGE/v1/channel-digests/runs" "$T1" '{"output_language":"en"}' cd-r3-run-1)
  op=$(jq -r .operation_id "$EV/post-run1.resp.body")
  assert run_accepted '[ "$status" = 202 ]' "http=$status"
  sleep 6
  curl -s -H "Authorization: Bearer $T1" "$EDGE/v1/operations/$op" >"$EV/op-early.json"
  assert run_is_queued_awaiting_acquisition_not_acquiring '[ "$(jq -r .status "$EV/op-early.json")" = queued ] && [ "$(jq -r .stage "$EV/op-early.json")" = awaiting_acquisition ]' "status=$(jq -r .status "$EV/op-early.json") stage=$(jq -r .stage "$EV/op-early.json")"
  assert run_ends_failed_at_its_deadline '[ "$(pollop "$op" "$T1" 170 run1)" = failed ] && grep -q run_deadline_exceeded "$EV/op-run1.json"' "$(jq -c "[.status,.stage,.errors]" "$EV/op-run1.json" | cut -c1-200)"
  assert run_row_failed_deadline_exceeded '[ "$(q ratatoskr "select state || '"'"'/'"'"' || coalesce(safe_failure_class, '"'"''"'"') from channel_digests.digest_runs where operation_id='"'"'$op'"'"'")" = failed/deadline_exceeded ]' "$(q ratatoskr "select state, safe_failure_class from channel_digests.digest_runs where operation_id='$op'")"
  assert worker_logged_the_deadline_class '[ "$(rg -c "deadline_exceeded" "$S/logs/worker.log" || true)" -ge 1 ]'

  info "leg Run2 and B: recap with a faulted acquisition hop, everything after the commit is real"
  build_legb || { assert legb_built 'false' "the helper did not build"; return; }
  status=$(call post-run2 POST "$EDGE/v1/channel-digests/runs" "$T1" '{"output_language":"en"}' cd-r3-run-2)
  op=$(jq -r .operation_id "$EV/post-run2.resp.body")
  assert recap_run_accepted '[ "$status" = 202 ]' "http=$status"
  untilt '[ -n "$(q ratatoskr "select run_id from channel_digests.digest_runs where operation_id='"'"'$op'"'"' and state='"'"'accepted'"'"'")" ]' 30
  rid=$(q ratatoskr "select run_id from channel_digests.digest_runs where operation_id='$op' and state='accepted'")
  assert worker_accepted_the_run_from_the_bus '[ -n "$rid" ]' "run $rid"
  "$S/bin/legb" "$(db_url ratatoskr_channel_digests)" "$rid" 2>&1 | tee "$EV/legb.txt" | sed -E 's#://[^@]*@#://<redacted>@#'
  assert recap_operation_succeeded '[ "$(pollop "$op" "$T1" 150 run2)" = succeeded ]'
  assert fake_openrouter_received_exactly_one_completion_with_two_refs '[ "$(jq -s "[.[] | select(.family==\"channel_recap\" and .answered==true)] | length" "$S/logs/fake-openrouter.jsonl")" = 1 ]' "$(tail -1 "$S/logs/fake-openrouter.jsonl" | cut -c1-200)"
  status=$(call results GET "$EDGE/v1/channel-digests/results" "$T1")
  local result_id
  result_id=$(jq -r '(.results // .items // [])[0].result_id // empty' "$EV/results.resp.body")
  assert result_listed '[ "$status" = 200 ] && [ -n "$result_id" ]' "http=$status"
  status=$(call result GET "$EDGE/v1/channel-digests/results/$result_id" "$T1")
  assert result_outcome_completed_with_two_citations '[ "$status" = 200 ] && [ "$(jq -r .outcome "$EV/result.resp.body")" = completed ] && [ "$(jq -r .citation_count "$EV/result.resp.body")" = 2 ]' "$(jq -c "{outcome,citation_count,headline:.recap.headline}" "$EV/result.resp.body")"
  status=$(call result-u2 GET "$EDGE/v1/channel-digests/results/$result_id" "$T2")
  assert another_owner_gets_404 '[ "$status" = 404 ]'
  status=$(call result-noauth GET "$EDGE/v1/channel-digests/results/$result_id" "")
  assert no_bearer_gets_401 '[ "$status" = 401 ]'
  assert knowledge_recap_run_completed '[ "$(q ratatoskr "select count(*) from knowledge.channel_recap_runs where state='"'"'completed'"'"'")" = 1 ]'

  info "negatives"
  status=$(call bad-name PUT "$EDGE/v1/channel-digests/subscriptions/Bad-Name" "$T1" '{"desired_state":"active"}' k-bad)
  assert noncanonical_username_400 '[ "$status" = 400 ]' "http=$status"
  status=$(call bad-state PUT "$EDGE/v1/channel-digests/subscriptions/smoke_bravo" "$T1" '{"desired_state":"bogus"}' k-bad2)
  assert invalid_desired_state_400 '[ "$status" = 400 ]' "http=$status"
  status=$(call no-idem PUT "$EDGE/v1/channel-digests/subscriptions/smoke_bravo" "$T1" '{"desired_state":"active"}')
  assert missing_idempotency_key_400 '[ "$status" = 400 ]' "http=$status"
  status=$(call idem-conflict PUT "$EDGE/v1/channel-digests/subscriptions/smoke_alpha" "$T1" '{"desired_state":"inactive"}' cd-r3-sub-1)
  assert key_reuse_with_a_different_body_409 '[ "$status" = 409 ]' "http=$status"
  status=$(call run-replay POST "$EDGE/v1/channel-digests/runs" "$T1" '{"output_language":"en"}' cd-r3-run-2)
  assert run_replay_returns_the_same_operation '[ "$status" = 202 ] && [ "$(jq -r .operation_id "$EV/run-replay.resp.body")" = "$op" ]'
  status=$(call bad-lang POST "$EDGE/v1/channel-digests/runs" "$T1" '{"output_language":"xx"}' k-lang)
  assert invalid_output_language_400 '[ "$status" = 400 ]' "http=$status"

  info "leg Run3: the recap provider fails permanently, the operation still terminates"
  : >"$S/run/fake-fail"
  status=$(call post-run3 POST "$EDGE/v1/channel-digests/runs" "$T1" '{"output_language":"ru"}' cd-r3-run-3)
  op=$(jq -r .operation_id "$EV/post-run3.resp.body")
  untilt '[ -n "$(q ratatoskr "select run_id from channel_digests.digest_runs where operation_id='"'"'$op'"'"' and state='"'"'accepted'"'"'")" ]' 30
  rid=$(q ratatoskr "select run_id from channel_digests.digest_runs where operation_id='$op' and state='accepted'")
  "$S/bin/legb" "$(db_url ratatoskr_channel_digests)" "$rid" >"$EV/legb3.txt" 2>&1
  assert provider_failure_ends_the_operation_failed '[ "$(pollop "$op" "$T1" 150 run3)" = failed ] && grep -q "channel_digest.recap.provider_unavailable" "$EV/op-run3.json"' "$(jq -c "[.status,.stage,.errors]" "$EV/op-run3.json" | cut -c1-200)"
  assert run_row_failed_provider_unavailable '[ "$(q ratatoskr "select safe_failure_class from channel_digests.digest_runs where run_id='"'"'$rid'"'"'")" = provider_unavailable ]'
  assert knowledge_recap_run_failed '[ "$(q ratatoskr "select count(*) from knowledge.channel_recap_runs where state='"'"'failed'"'"'")" -ge 1 ]'
  rm -f "$S/run/fake-fail"
  info "leg C (partial acquisition) NOT RUN: MTProto cannot be faked without credentials"
  info "events stream and consumers: $(curl -s "$NATS_MON/jsz?streams=true&consumers=true" | jq -c "[.account_details[].stream_detail[] | {s:.name, msgs:.state.messages}]")"
}
