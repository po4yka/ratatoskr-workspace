#!/usr/bin/env bash
# shellcheck disable=SC2034
# F7 GitHub analysis loop (Edge, GitHub, Knowledge; R2-08). Sourced by run.sh; defines the flow, runs nothing.
#
# Provenance: written new for this harness. The GitHub service, its originating `track` action and the Knowledge side of the loop were never run in a native smoke before (Round 2 recorded F7 as never run). The track body is the shape of services/catalog/tests/action_support (mode, target, confirmation_evidence_ref, idempotency_key). Round 4 added the completed closure, the failed closure and the PAT leg. Run through run.sh as committed in Round 5: see README.md for the verdict.

FLOW_ID=f7
FLOW_TITLE="GitHub analysis loop: track action, request on the bus, README fetch, completed or failed fact, observer, bounded provider calls"
FLOW_BINARIES=("platform:ratatoskr-edge render-nats-config" "knowledge:ratatoskr-knowledge-service" "github:ratatoskr-github-catalog")
FLOW_PORTS="$INFRA_PORTS 8091 9081 8092 9095 $FAKE_GITHUB_PORT $FAKE_OPENROUTER_PORT"
FLOW_REPOS="platform knowledge github"
FLOW_EVIDENCE="not run before this harness"
FLOW_HONESTY=(
  "faked: the GitHub API is a loopback fake (fixtures/fake_github.py, RATATOSKR__PROVIDER__BASE_URL, a key the example does not state but DEVELOPMENT.md documents); OpenRouter is a loopback fake (fixtures/fake_openrouter.py) that answers the repository family with a schema-valid analysis grounded in the README the prompt carries, so no analysis text is a live provider result"
  "labelled: the loop must close with a COMPLETED fact consumed by GitHub; the failed closure is a separate leg that switches the fake OpenRouter to 401 (RUNDIR/fake-fail) before the observer queues a second request, and a failed closure alone never counts as the loop working"
  "seeded: the GitHub account row of the PAT leg (the way services/catalog/tests/repository_api.rs creates it); the PAT is a synthetic string and never leaves the machine"
  "seeded: two users and their browser sessions (fixtures/platform-seed.sql)"
  "deviation: RATATOSKR__WATCH__OBSERVE_INTERVAL_SECONDS=10 (the example states 3600), and RATATOSKR__PROVIDER__TIMEOUT_MS=1000 for the stalled-provider leg"
  "not exercised: a real GitHub token, OAuth, star and revoke against GitHub"
  "faked (R4-09): the fake GitHub answers GET /user with a login and a numeric id for the PAT leg; the fake's stall control is the existence of RUN/github-stall"
  "NOT RUN: the account-erasure transport of GitHub (excluded, R4-13)"
)

# track_body KEY [NUMERIC_ID FULL_NAME]: the repository defaults to owner/repository (numeric id 42), the one the fake GitHub serves with id 42.
track_body() {
  jq -nc --arg key "$1" --argjson id "${2:-42}" --arg name "${3:-owner/repository}" '{mode:"track",target:{github_repository_numeric_id:$id,repository_full_name:$name,canonical_url:("https://github.com/" + $name)},confirmation_evidence_ref:"telegram-confirmation:018f0000-0000-7000-8000-000000000613",idempotency_key:$key}'
}

flow_run() {
  infra_fresh || { assert infra_up 'false' "PostgreSQL or NATS did not start"; return; }
  edge_up || { assert edge_started 'false' "Edge did not become ready"; return; }
  assert_s04_durables
  seed_principals
  local row repo role
  for row in "github|ratatoskr_github" "knowledge|ratatoskr_knowledge"; do
    IFS='|' read -r repo role <<<"$row"
    pg_role "$repo" "$role" || { assert "role_$role" 'false' "role.sql failed"; return; }
  done
  mkdir -p "$S/blobs/knowledge"
  fake_start fake-github fake_github.py "$FAKE_GITHUB_PORT" "$S/logs/fake-github.jsonl" "$S/run"
  fake_start fake-openrouter fake_openrouter.py "$FAKE_OPENROUTER_PORT" "$S/logs/fake-openrouter.jsonl" "$S/run"
  conf_knowledge false && conf_github 10 || return
  svc_start knowledge
  svc_start github
  svc_wait_ready knowledge 90
  svc_wait_ready github 60
  local T1 T2 status
  T1=$(secret browser1)
  T2=$(secret browser2)
  assert github_ready '[ "$(code 127.0.0.1:9095/ready)" = 200 ]'
  assert github_example_database_is_the_shared_one '[ "$(q ratatoskr "select count(*) from pg_namespace where nspname='"'"'github_catalog'"'"'")" = 1 ]' "R3-11: the catalog lives in the shared database, schema github_catalog"

  info "the track action through Edge"
  status=$(call track POST "$EDGE/v1/gh/repositories/actions" "$T1" "$(track_body "f7-track-1")" f7-track-1)
  assert track_action_accepted '[ "$status" = 200 ]' "http=$status $(head -c 200 "$EV/track.resp.body")"
  assert exactly_one_analysis_request_for_the_owner '[ "$(q ratatoskr "select count(*) from github_catalog.repository_analysis_requests where owner_ref='"'"'user:$U1'"'"'")" = 1 ]'
  assert request_names_the_fetched_readme '[ "$(q ratatoskr "select source_revision #>> '"'"'{readme,state}'"'"' from github_catalog.repository_analysis_requests limit 1")" = present ]'
  untilt '[ "$("$PY" -I "$NATIVE_ROOT/fixtures/natsprobe.py" messages "$S/nk/edge.nkey" ratatoskr_events evt.knowledge.repository_analysis.requested.v1 | wc -l | tr -d " ")" -ge 1 ]' 60
  assert request_event_is_on_the_stream '[ "$("$PY" -I "$NATIVE_ROOT/fixtures/natsprobe.py" messages "$S/nk/edge.nkey" ratatoskr_events evt.knowledge.repository_analysis.requested.v1 | wc -l | tr -d " ")" -ge 1 ]'
  untilt '[ "$(q ratatoskr "select status from github_catalog.repository_analysis_requests order by created_at limit 1")" = completed ]' 180
  assert knowledge_fetched_the_readme_with_the_shared_secret '[ "$(jq -s "[.[] | select(.path | endswith(\"/readme\"))] | length" "$S/logs/fake-github.jsonl")" -ge 1 ]' "README requests seen by the fake provider"
  assert loop_closed_with_a_completed_fact_consumed_by_github '[ "$(q ratatoskr "select status from github_catalog.repository_analysis_requests order by created_at limit 1")" = completed ] && [ -n "$(q ratatoskr "select analysis_result_ref from github_catalog.repository_analysis_requests order by created_at limit 1")" ]' "status=$(q ratatoskr "select status || '/' || coalesce(failure_code, '') from github_catalog.repository_analysis_requests order by created_at limit 1")"
  assert completed_request_has_a_link_for_the_owner '[ "$(q ratatoskr "select count(*) from github_catalog.repository_analysis_links where owner_ref = '"'"'user:$U1'"'"'")" = 1 ]'
  assert fake_provider_answered_the_repository_family '[ "$(jq -s "[.[] | select(.family == \"repository\" and .answered == true)] | length" "$S/logs/fake-openrouter.jsonl")" -ge 1 ]' "provider calls: $(jq -sc "map(.family)" "$S/logs/fake-openrouter.jsonl")"
  assert completed_analysis_is_stored_by_knowledge_with_the_fake_providers_summary '[ "$(q ratatoskr "select count(*) from knowledge.analysis_outputs where result ->> '"'"'summary'"'"' like '"'"'Scripted repository summary%'"'"'")" -ge 1 ]' "Knowledge stores the analysis in knowledge.analysis_outputs; the search document of a repository carries its full name, description and README, not the model summary"
  untilt '[ "$(curl -s "127.0.0.1:8091/internal/search?tenant=user:$U1&q=synthetic" | jq ".results | length")" -ge 1 ]' 60
  assert completed_repository_is_searchable_through_knowledges_read_api '[ "$(curl -s "127.0.0.1:8091/internal/search?tenant=user:$U1&q=synthetic" | jq ".results | length")" -ge 1 ]' "GET /internal/search?q=synthetic (a word of the README the fake GitHub serves): $(curl -s "127.0.0.1:8091/internal/search?tenant=user:$U1&q=synthetic" | jq -c "[.results[]|{title}]" | cut -c1-200)"

  info "the observer queues a second request only after a change"
  local requests_before
  requests_before=$(q ratatoskr "select count(*) from github_catalog.repository_analysis_requests")
  sleep 25
  assert unchanged_poll_queues_none '[ "$(q ratatoskr "select count(*) from github_catalog.repository_analysis_requests")" = "$requests_before" ]'
  : >"$S/run/fake-fail"
  printf 'The description changed after the first analysis\n' >"$S/run/github-description"
  untilt '[ "$(q ratatoskr "select count(*) from github_catalog.repository_analysis_requests")" -gt "$requests_before" ]' 60
  q ratatoskr "select request_id, status, coalesce(failure_code, ''), created_at from github_catalog.repository_analysis_requests order by created_at" >"$EV/requests-after-change.txt" 2>&1
  q ratatoskr "select watch_id, owner_ref, enabled, last_evaluated_content_hash is not null from github_catalog.repository_watches" >"$EV/watches-after-change.txt" 2>&1
  q ratatoskr "select content_hash from github_catalog.repository_metadata" >>"$EV/watches-after-change.txt" 2>&1
  assert changed_description_queues_a_second_request '[ "$(q ratatoskr "select count(*) from github_catalog.repository_analysis_requests")" -gt "$requests_before" ]' "requests: $(tr "\n" ";" <"$EV/requests-after-change.txt" | cut -c1-300)"
  info "the failed closure: the fake provider answers 401, so the second request must end failed, never stay pending"
  untilt '[ "$(q ratatoskr "select status from github_catalog.repository_analysis_requests order by created_at desc limit 1")" = failed ]' 240
  assert second_request_closes_failed_when_the_provider_refuses '[ "$(q ratatoskr "select status from github_catalog.repository_analysis_requests order by created_at desc limit 1")" = failed ] && [ -n "$(q ratatoskr "select failure_code from github_catalog.repository_analysis_requests order by created_at desc limit 1")" ]' "status=$(q ratatoskr "select status || '/' || coalesce(failure_code, '') from github_catalog.repository_analysis_requests order by created_at desc limit 1")"
  rm -f "$S/run/fake-fail"

  info "PAT registration (R4-09): an account row, reconnect-pat with the PAT on standard input, the provider is the loopback fake"
  local account pat_status
  account=$("$PY" -I -c 'import uuid; print(uuid.uuid4())')
  q ratatoskr "insert into github_catalog.github_accounts (account_id, owner_ref, status) values ('$account', 'user:$U1', 'reauthorization_required')" >/dev/null
  pat_status=0
  printf 'ghp_%s\n' "$(printf "%s%s" "$(secret pat)" "$(secret pat2)" | cut -c1-36)" | "$PY" -I "$NATIVE_ROOT/lib/envrun.py" "$S/conf/github.env" "$S/bin/ratatoskr-github-catalog" reconnect-pat "$account" >"$EV/reconnect-pat.out" 2>&1 || pat_status=$?
  assert reconnect_pat_exits_zero '[ "$pat_status" = 0 ]' "exit $pat_status: $(head -c 200 "$EV/reconnect-pat.out")"
  assert provider_saw_get_user_with_a_bearer '[ "$(jq -s "[.[] | select(.path == \"/user\" and .auth == \"present\")] | length" "$S/logs/fake-github.jsonl")" -ge 1 ]' "requests to the fake: $(jq -sc "map(.path)" "$S/logs/fake-github.jsonl")"
  assert pat_never_appears_in_the_command_output '[ "$(grep -c "ghp_" "$EV/reconnect-pat.out")" = 0 ]'
  info "NOT RUN: the account-erasure transport of GitHub stays excluded (R4-13)"

  info "a stalled provider does not hang the catalog"
  svc_stop github
  conf_github 3600 1000 || return
  svc_start github
  svc_wait_ready github 60
  : >"$S/run/github-stall"
  local t0 t1
  t0=$(date +%s)
  status=$(call track-stalled POST "$EDGE/v1/gh/repositories/actions" "$T2" "$(track_body "f7-track-2" 8026505 owner/stalled)" f7-track-2)
  t1=$(date +%s)
  rm -f "$S/run/github-stall"
  # owner/stalled is new to the catalog, so its metadata has to come from the stalled provider; the action reports a provider failure as a per-part result in a 200 body, not as an HTTP error. The first harness tracked the repository the catalog already held, and the fake's stall control was an empty file the fake read as unset, so no call was ever stalled.
  assert stalled_provider_answers_within_a_bound '[ $((t1 - t0)) -lt 15 ]' "answered http=$status after $((t1 - t0)) s with a 1 s provider timeout"
  assert stalled_provider_answer_reports_the_failure_in_the_action_result '[ "$(jq -r .aggregate "$EV/track-stalled.resp.body")" = failed ] && [ "$(jq -r .metadata.reason "$EV/track-stalled.resp.body")" = provider_unavailable ]' "the action answers http=$status with a per-part result: $(jq -c . "$EV/track-stalled.resp.body" | cut -c1-200)"
  assert github_still_ready_after_the_stall '[ "$(code 127.0.0.1:9095/ready)" = 200 ]'
}
