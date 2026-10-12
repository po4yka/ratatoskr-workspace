#!/usr/bin/env bash
# shellcheck disable=SC2034
# F1 AI-archive upload (Edge, ChatGPT, Claude; R3-03, R3-04, R3-05, R3-07). Sourced by run.sh; defines the flow, runs nothing.
#
# Provenance: the driver fixtures/f1_scenario.py is the by-hand scenario of the Round 3 AI-archive smoke (.workspaces/XR-021/smoke/ai), plus section s13 (the cumulative series F6 needs). The Round 3 result recorded in the changeset, 62 of 63 assertions passed and one failed (a Claude archive that carries a knowledge file cannot reach succeeded), came from that by-hand run. Run through run.sh as committed in Round 5: see README.md for the verdict.

FLOW_ID=f1
FLOW_TITLE="AI-archive upload (Edge, ChatGPT, Claude): sessions, ceilings, restart, unmapped user, cumulative series"
FLOW_BINARIES=("platform:ratatoskr-edge render-nats-config" "chatgpt:ratatoskr-chatgpt-archive" "claude:ratatoskr-claude-archive")
FLOW_PORTS="$INFRA_PORTS 8096 9085 8097 9086"
FLOW_REPOS="platform chatgpt claude"
FLOW_EVIDENCE="by-hand run of the same scenario in Round 3: ran, passed=false (62 of 63 assertions; one defect in Claude)"
FLOW_KEEP_DATA=1
FLOW_HONESTY=(
  "seeded: two users, their browser sessions, a Mini App session and a device (fixtures/platform-seed.sql); devices are paired through the real pairing API"
  "faked: all archives are invented synthetic ZIPs built by fixtures/archives.py; no provider was involved and no Edge, gateway, NATS or PostgreSQL hop is stubbed"
  "not exercised: Knowledge and extractor consumers of the ai_archive facts (F2, F6), the Export Agent's Swift client and keychain, Telegram, TLS through cloudflared, per-flow privacy deletion (F6)"
  "user 2 is unmapped on both receivers until section s13, then mapped (a documented configuration change)"
  "deviation (R5-04): Edge runs with RATATOSKR__ARCHIVE_STAGING__SWEEP_INTERVAL_SECONDS=30 (rule V23 allows 30 to 3600; the example's 300 would make the reaper legs wait minutes)"
  "seeded (R5-04): the reaper legs rewind one transfer session's opened_at and expires_at by SQL and delete another session's row by SQL; an orphan rst_ directory is made by hand and aged with touch -t"
  "faked (R3-03): section s17 stops the Claude receiver and puts a loopback stand-in (fixtures/stand_in_receipt.py) on 8097 that answers 401, then starts the receiver again; the stand-in is not the Claude receiver"
  "best-effort (R5-04 d): section s15 uploads one 256 MiB synthetic ChatGPT archive through the real Edge and records the wall time; it is NOT the Raspberry Pi measurement"
  "NOT RUN: the Export Agent's Swift client (AgentCore) against the live Edge, and the macOS keychain pairing; see README.md"
)

flow_run() {
  EDGE_SWEEP_SECONDS=30
  infra_fresh || { assert infra_up 'false' "PostgreSQL or NATS did not start"; return; }
  edge_up || { assert edge_started 'false' "Edge did not become ready"; return; }
  seed_principals
  pg_role chatgpt ratatoskr_chatgpt || { assert chatgpt_role 'false' "role.sql failed"; return; }
  pg_role claude ratatoskr_claude || { assert claude_role 'false' "role.sql failed"; return; }
  conf_chatgpt && conf_claude || return
  svc_start chatgpt
  svc_start claude
  svc_wait_ready chatgpt 60
  svc_wait_ready claude 60
  "$PY" -I "$NATIVE_ROOT/fixtures/archives.py" "$S/fx" >"$EV/fixtures.txt"
  env RATATOSKR_SMOKE_DIR="$S" NATIVE_ROOT="$NATIVE_ROOT" EV="$EV" "$PY" -I "$NATIVE_ROOT/fixtures/f1_scenario.py" | tee "$EV/scenario.out"
  ingest_assert_lines "$EV/scenario.out"
}
