#!/usr/bin/env bash
# shellcheck disable=SC2034
# F7 GitHub analysis loop (Edge, GitHub, Knowledge; R2-08). Sourced by run.sh; defines the flow, runs nothing.
#
# Provenance: written new for this harness. The GitHub service, its originating `track` action and the Knowledge side of the loop were never run in a native smoke before (Round 2 recorded F7 as never run). The track body is the shape of services/catalog/tests/action_support (mode, target, confirmation_evidence_ref, idempotency_key). Run through run.sh as committed: NO.

FLOW_ID=f7
FLOW_TITLE="GitHub analysis loop: track action, request on the bus, README fetch, completed or failed fact, observer, bounded provider calls"
FLOW_BINARIES=("platform:ratatoskr-edge render-nats-config" "knowledge:ratatoskr-knowledge-service" "github:ratatoskr-github-catalog")
FLOW_PORTS="$INFRA_PORTS 8091 9081 8092 9095 $FAKE_GITHUB_PORT $FAKE_OPENROUTER_PORT"
FLOW_REPOS="platform knowledge github"
FLOW_EVIDENCE="not run before this harness"
FLOW_HONESTY=(
  "faked: the GitHub API is a loopback fake (fixtures/fake_github.py, RATATOSKR__PROVIDER__BASE_URL, a key the example does not state but DEVELOPMENT.md documents); OpenRouter is a loopback fake that does not answer the repository family"
  "labelled: because the fake OpenRouter answers 400 for a repository-analysis prompt, the loop is expected to close with a FAILED fact consumed by GitHub (the plan accepts a failed fact from a fixture provider as evidence); a completed fact would need a provider that answers that family"
  "seeded: two users and their browser sessions (fixtures/platform-seed.sql)"
  "deviation: RATATOSKR__WATCH__OBSERVE_INTERVAL_SECONDS=10 (the example states 3600), and RATATOSKR__PROVIDER__TIMEOUT_MS=1000 for the stalled-provider leg"
  "not exercised: a real GitHub token, OAuth, star and revoke against GitHub"
)

track_body() {
  jq -nc --arg key "$1" '{mode:"track",target:{github_repository_numeric_id:42,repository_full_name:"owner/repository",canonical_url:"https://github.com/owner/repository"},confirmation_evidence_ref:"telegram-confirmation:018f0000-0000-7000-8000-000000000613",idempotency_key:$key}'
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
  untilt '[ "$(python3 -I "$NATIVE_ROOT/fixtures/natsprobe.py" messages "$S/nk/edge.nkey" ratatoskr_events evt.knowledge.repository_analysis.requested.v1 | wc -l | tr -d " ")" -ge 1 ]' 60
  assert request_event_is_on_the_stream '[ "$(python3 -I "$NATIVE_ROOT/fixtures/natsprobe.py" messages "$S/nk/edge.nkey" ratatoskr_events evt.knowledge.repository_analysis.requested.v1 | wc -l | tr -d " ")" -ge 1 ]'
  untilt '[ "$(q ratatoskr "select status from github_catalog.repository_analysis_requests limit 1")" != queued ] && [ "$(q ratatoskr "select status from github_catalog.repository_analysis_requests limit 1")" != published ]' 120
  assert knowledge_fetched_the_readme_with_the_shared_secret '[ "$(jq -s "[.[] | select(.path | endswith(\"/readme\"))] | length" "$S/logs/fake-github.jsonl")" -ge 1 ]' "README requests seen by the fake provider"
  assert loop_closed_with_a_terminal_fact_consumed_by_github '[ -n "$(q ratatoskr "select terminal_at from github_catalog.repository_analysis_requests limit 1")" ]' "status=$(q ratatoskr "select status || '/' || coalesce(failure_code, '') from github_catalog.repository_analysis_requests limit 1"); a failed fact from the fixture provider is acceptable evidence and is labelled"

  info "the observer queues a second request only after a change"
  local requests_before
  requests_before=$(q ratatoskr "select count(*) from github_catalog.repository_analysis_requests")
  sleep 25
  assert unchanged_poll_queues_none '[ "$(q ratatoskr "select count(*) from github_catalog.repository_analysis_requests")" = "$requests_before" ]'
  printf 'The description changed after the first analysis\n' >"$S/run/github-description"
  untilt '[ "$(q ratatoskr "select count(*) from github_catalog.repository_analysis_requests")" -gt "$requests_before" ]' 60
  assert changed_description_queues_a_second_request '[ "$(q ratatoskr "select count(*) from github_catalog.repository_analysis_requests")" -gt "$requests_before" ]'

  info "a stalled provider does not hang the catalog"
  svc_stop github
  conf_github 3600 1000 || return
  svc_start github
  svc_wait_ready github 60
  : >"$S/run/github-stall"
  local t0 t1
  t0=$(date +%s)
  status=$(call track-stalled POST "$EDGE/v1/gh/repositories/actions" "$T2" "$(track_body "f7-track-2")" f7-track-2)
  t1=$(date +%s)
  rm -f "$S/run/github-stall"
  assert stalled_provider_answers_within_a_bound '[ $((t1 - t0)) -lt 15 ]' "answered http=$status after $((t1 - t0)) s with a 1 s provider timeout"
  assert stalled_provider_answer_is_an_error_not_a_success '[ "$status" != 200 ]' "http=$status"
  assert github_still_ready_after_the_stall '[ "$(code 127.0.0.1:9095/ready)" = 200 ]'
}
