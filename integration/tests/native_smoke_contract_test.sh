#!/usr/bin/env bash
# Contract test of the native smoke harness (integration/native, XR-021 round 3 task 4, extended in round 4 task 3 and round 5 task 3). It checks the scripts themselves and starts no service, builds nothing and needs no Docker: the flow list, the prerequisite check and its exit codes, the busy-port report, --prune, the safety rules (no pkill, no kill of an unrecorded pid, no write outside the state directory), shellcheck when installed, the Python fixtures and fakes, the configuration renderer, and that every binary a flow builds exists in the pinned checkout. It does NOT prove that a flow passes against real services; that is the manual run, and the README states per flow whether it was ever run through run.sh as committed.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
native="$workspace_root/integration/native"
run="$native/run.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

scratch=$(mktemp -d)
background=()
cleanup() {
  local pid
  for pid in "${background[@]:-}"; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
  rm -rf -- "$scratch"
}
trap cleanup EXIT

[[ -x "$run" ]] || fail "missing or not executable: $run"

# One interpreter for the whole test and the harness: the first candidate that serves HTTP and imports cryptography (lib/common.sh::py_select).
# shellcheck source=../native/lib/common.sh
source "$native/lib/common.sh"
py_select || fail "no python on this machine serves HTTP and imports cryptography; set RATATOSKR_SMOKE_PYTHON"

# --- the flow list --------------------------------------------------------------------------------------------
listing=$("$run" --list)
for flow in F0 F1 F2 F3 F4 F5 F6 F7; do
  rg --quiet "^$flow  " <<<"$listing" || fail "--list does not print flow $flow"
done
[[ "$(rg -c '^  binaries: ' <<<"$listing")" == 8 ]] || fail "--list does not print the binaries of every flow"
[[ "$(rg -c '^  ports free: ' <<<"$listing")" == 8 ]] || fail "--list does not print the ports of every flow"
rg --quiet 'Common prerequisites: nats-server 2.10' <<<"$listing" || fail "--list does not print the prerequisites"
for flow in f0 f1 f2 f3 f4 f5 f6 f7; do
  rg --quiet --fixed-strings "$flow" "$native/README.md" || fail "README does not mention $flow"
done

# --- --dry-run: exit 0 when satisfied, exit 3 with one explicit line per missing prerequisite --------------------
for flow in f0 f1 f2 f3 f4 f5 f6 f7; do
  status=0
  output=$(RATATOSKR_SMOKE_DIR="$scratch/state" "$run" --dry-run "$flow" 2>&1) || status=$?
  case $status in
    0) rg --quiet '^dry-run ok: ' <<<"$output" || fail "dry-run $flow exited 0 without saying so" ;;
    3) rg --quiet '^MISSING: ' <<<"$output" || fail "dry-run $flow exited 3 without a MISSING line" ;;
    *) fail "dry-run $flow exited $status: $output" ;;
  esac
  if [[ $status == 3 ]]; then
    ! rg --quiet --invert-match '^MISSING: ' <<<"$output" || fail "dry-run $flow printed a line that is not a MISSING line: $output"
  fi
done
status=0
output=$(PATH=/usr/bin:/bin RATATOSKR_SMOKE_DIR="$scratch/state" "$run" --dry-run f0 2>&1) || status=$?
[[ $status == 3 ]] || fail "dry-run with a bare PATH must exit 3, got $status"
for tool in nats-server initdb pg_ctl psql cargo; do
  rg --quiet --fixed-strings "MISSING: command $tool " <<<"$output" || fail "a bare PATH did not report $tool"
done
status=0
RATATOSKR_SMOKE_DIR="$scratch/state" "$run" --dry-run f9 >/dev/null 2>&1 || status=$?
[[ $status == 2 ]] || fail "an unknown flow must exit 2, got $status"

# --- a busy port is reported with its holder and is never killed ---------------------------------------------------
port=$("$PY" -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')
"$PY" -c 'import socket,sys,time
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(1); time.sleep(120)' "$port" &
holder=$!
background+=("$holder")
sleep 1
busy=$(RATATOSKR_SMOKE_DIR="$scratch/state" bash -c "source '$native/lib/common.sh'; ports_busy $port" || true)
rg --quiet --fixed-strings "BUSY port $port is held by pid $holder " <<<"$busy" || fail "ports_busy did not name the holder (pid $holder): $busy"
kill -0 "$holder" 2>/dev/null || fail "the port check killed the process that held the port"
none=$(RATATOSKR_SMOKE_DIR="$scratch/state" bash -c "source '$native/lib/common.sh'; ports_busy 1" || true)
[[ -z "$none" ]] || fail "a free port was reported busy: $none"

# --- --prune removes only paths under the state directory ---------------------------------------------------------
state="$scratch/prune/ratatoskr-smoke-state"
mkdir -p "$state/target" "$state/bin" "$scratch/decoy"
: >"$state/.ratatoskr-smoke-dir"
: >"$state/target/leftover"
: >"$state/bin/leftover"
: >"$scratch/decoy/keep"
RATATOSKR_SMOKE_DIR="$state" "$run" --prune >/dev/null
[[ -d "$state" && -z "$(ls -A "$state")" ]] || fail "--prune left something under the state directory"
[[ -f "$scratch/decoy/keep" ]] || fail "--prune removed a file outside the state directory"
unmarked="$scratch/prune/unmarked-dir"
mkdir -p "$unmarked"
: >"$unmarked/keep"
status=0
RATATOSKR_SMOKE_DIR="$unmarked" "$run" --prune >/dev/null 2>&1 || status=$?
[[ $status == 2 && -f "$unmarked/keep" ]] || fail "--prune must refuse a directory without the marker (exit $status)"
for bad in "$HOME" / "$workspace_root" "$workspace_root/evidence" relative/path; do
  status=0
  RATATOSKR_SMOKE_DIR="$bad" "$run" --prune >/dev/null 2>&1 || status=$?
  [[ $status == 2 ]] || fail "--prune must refuse $bad (exit $status)"
done
[[ -d "$workspace_root/integration" ]] || fail "the workspace was damaged"

# --- safety rules over every script of the harness ---------------------------------------------------------------
scripts=("$run" "$native"/lib/*.sh "$native"/flows/*.sh)
code_lines() { awk '!/^[[:space:]]*#/' "$1"; }
# Matches are counted with awk on whole lines: some environments wrap rg and cut long lines.
matches() { code_lines "$1" | awk -v pattern="$2" '$0 ~ pattern { n++ } END { print n + 0 }'; }
for script in "${scripts[@]}"; do
  [[ "$(matches "$script" '(^|[^A-Za-z_])(pkill|killall)([^A-Za-z_]|$)')" == 0 ]] || fail "$script uses pkill or killall"
  [[ "$(matches "$script" '(^|[^A-Za-z_./-])/tmp/')" == 0 ]] || fail "$script writes under /tmp"
  [[ -z "$(code_lines "$script" | awk '/(^|[ \t0-9&])>>?[ \t]*\// && !/\/dev\/(null|stderr)/')" ]] || fail "$script redirects to an absolute path outside the state directory"
  case "$script" in
    */lib/services.sh) ;;
    *) [[ "$(matches "$script" '(^|[;&|({ \t])kill[ \t]')" == 0 ]] || fail "$script calls kill; only lib/services.sh may, and only on a recorded pid" ;;
  esac
done
while IFS= read -r line; do
  [[ "$line" == *'$pid'* ]] || fail "lib/services.sh calls kill on something other than a recorded pid: $line"
done < <(code_lines "$native/lib/services.sh" | awk '/(^|[;&|({ \t])kill[ \t]/')
rg --quiet --fixed-strings 'kill -KILL "$pid"' "$native/lib/services.sh" || fail "lib/services.sh lost its SIGKILL of the recorded pid"
rg --quiet --fixed-strings 'kill -TERM "$pid"' "$native/lib/services.sh" || fail "lib/services.sh lost its SIGTERM of the recorded pid"
rg --quiet --fixed-strings 'smoke_dir_guard' "$native/lib/common.sh" || fail "the state directory guard is gone"
(cd "$workspace_root" && git check-ignore --quiet evidence/XR-021-r6/f0/result.txt) || fail "evidence/XR-021-r6 is not gitignored"

# --- Round 4 fixes (R4-12): each is a defect the first honest read of the harness found --------------------------
# The state directory and the evidence root name the round; none of the harness may still name the previous one.
previous_round="XR-021-r$((6 - 1))"
stale=$(rg --files-with-matches --fixed-strings "$previous_round" "$native" "$workspace_root/integration/tests" || true)
[[ -z "$stale" ]] || fail "a file still names $previous_round: $stale"
rg --quiet --fixed-strings 'XR-021-r6' "$native/lib/common.sh" || fail "lib/common.sh does not default to the round 6 state directory"

# assert evaluates the caller's condition in the caller's scope, so its own locals must not shadow a caller variable.
shadow=$(EV="$scratch/shadow-ev" bash -c 'mkdir -p "$EV"; source "$1"
  name=caller-name cond=caller-cond detail=caller-detail line=caller-line
  assert sees_name '"'"'test "$name" = caller-name'"'"'
  assert sees_cond '"'"'test "$cond" = caller-cond'"'"'
  assert sees_detail '"'"'test "$detail" = caller-detail'"'"'
  assert sees_line '"'"'test "$line" = caller-line'"'"'' _ "$native/lib/assert.sh")
for variable in name cond detail line; do
  rg --quiet "^ASSERT sees_$variable: PASS" <<<"$shadow" || fail "assert shadows the caller variable $variable: $shadow"
done

# assert_s04_durables passes for a broker that holds the whole table (the durable lookup is replaced by the table itself).
durable_run=$(EV="$scratch/durable-ev" NATS_MON=http://127.0.0.1:1 bash -c 'mkdir -p "$EV"; source "$1"; source "$2"
  jsz() { printf "{\"account_details\":[]}"; }
  dur() { local row n f w m; for row in "${S04_DURABLES[@]}"; do IFS="|" read -r n f w m <<<"$row"; [[ "$n" == "$1" ]] && printf "%s %s %s" "$f" "$w" "$m"; done; }
  assert_s04_durables' _ "$native/lib/assert.sh" "$native/lib/nats.sh")
durable_rows=$(bash -c 'source "$1"; printf "%s" "${#S04_DURABLES[@]}"' _ "$native/lib/nats.sh")
[[ "$durable_rows" == 22 ]] || fail "the S04 table of lib/nats.sh has $durable_rows rows, expected the 22 acknowledging durables of CONTRACTS S04 as amended by R5-11 (the 23rd, ratatoskr_extractor_render_awaits, is ack none and asserted separately)"
[[ "$(rg -c '^ASSERT durable_ratatoskr_[a-z_]+: PASS' <<<"$durable_run")" == "$durable_rows" ]] || fail "assert_s04_durables does not pass every row of a broker that holds the table: $(rg '^ASSERT durable_' <<<"$durable_run" | head -3)"

# F3 counts bot calls by method and reads the status of every capture call; a line count is not a message count.
f3="$native/flows/f3-telegram.sh"
[[ "$(matches "$f3" 'bot_replies_after[^|]*[|][^|]*wc -l')" == 0 ]] || fail "f3 counts replies with wc -l, so one two-line message satisfies a two-message assertion"
rg --quiet --fixed-strings 'bot_calls_after' "$f3" || fail "f3 does not count bot calls by method"
rg --quiet --fixed-strings 'capture_statuses' "$f3" || fail "f3 does not read the tap-recorded status of the capture calls"
rg --quiet 'assert forwarded_capture_status_is_202' "$f3" || fail "f3 does not assert the status of the forwarded capture"

# --- Round 5 fixes (R5-14) ---------------------------------------------------------------------------------------
# The interpreter is chosen by a probe, once. Three stub interpreters stand for the three ways a python3 fails or works: one hangs (Homebrew's 3.15 accepted a connection and never answered), one cannot import cryptography, one is good. A stub is a script that behaves as the real probe would end: it exits 0, exits 1, or never returns.
stubs="$scratch/stubs"
mkdir -p "$stubs"
printf '#!/bin/sh\nexec sleep 60\n' >"$stubs/hangs"
printf '#!/bin/sh\nexit 1\n' >"$stubs/no-cryptography"
printf '#!/bin/sh\nexit 0\n' >"$stubs/good"
chmod +x "$stubs"/*
chosen=$(PY= RATATOSKR_SMOKE_PYTHON_CANDIDATES="$stubs/hangs $stubs/no-cryptography $stubs/good" PY_PROBE_TIMEOUT=2 bash -c "source '$native/lib/common.sh'; py_select && printf '%s' \"\$PY\"") || fail "py_select found no interpreter among a hanging, a bad and a good stub"
[[ "$chosen" == "$stubs/good" ]] || fail "py_select chose $chosen instead of the good stub"
chosen=$(PY= RATATOSKR_SMOKE_PYTHON_CANDIDATES="$stubs/good $stubs/hangs" PY_PROBE_TIMEOUT=2 bash -c "source '$native/lib/common.sh'; py_select && printf '%s' \"\$PY\"")
[[ "$chosen" == "$stubs/good" ]] || fail "py_select is not deterministic: with the good stub first it chose $chosen"
status=0
PY= RATATOSKR_SMOKE_PYTHON_CANDIDATES="$stubs/hangs $stubs/no-cryptography" PY_PROBE_TIMEOUT=2 bash -c "source '$native/lib/common.sh'; py_select" || status=$?
[[ $status == 1 ]] || fail "py_select must fail when every candidate is bad (exit $status)"
status=0
output=$(PY= RATATOSKR_SMOKE_PYTHON_CANDIDATES="$stubs/hangs $stubs/no-cryptography" PY_PROBE_TIMEOUT=2 RATATOSKR_SMOKE_DIR="$scratch/state" "$run" --dry-run f3 2>&1) || status=$?
[[ $status == 3 ]] || fail "run.sh --dry-run f3 with only bad interpreters must exit 3, got $status"
rg --quiet --fixed-strings 'MISSING: python with HTTP serving and cryptography' <<<"$output" || fail "run.sh --dry-run f3 did not report the missing interpreter: $output"
# The probe itself works on the interpreter this test selected, and every call site of the harness uses $PY.
"$PY" -I -c "$PY_PROBE_CODE" || fail "the probe fails on the interpreter py_select chose"
for script in "$run" "$native"/lib/*.sh "$native"/flows/*.sh; do
  [[ "$(matches "$script" '(^|[^A-Za-z_"$./-])python3[ \t]+-[BIc]')" == 0 ]] || fail "$script calls python3 instead of the selected \$PY"
done

# q fails loudly: a psql error returns non-zero, is recorded for the running assertion, and an assertion over two empty strings no longer passes. A stub psql stands for a missing table.
mkdir -p "$scratch/psqlbin" "$scratch/q-ev"
printf '#!/bin/sh\necho "ERROR:  relation \\"knowledge.nothing\\" does not exist" >&2\nexit 1\n' >"$scratch/psqlbin/psql"
chmod +x "$scratch/psqlbin/psql"
q_run=$(PATH="$scratch/psqlbin:$PATH" EV="$scratch/q-ev" bash -c 'source "$1"; source "$2"; : >"$EV/asserts.txt"
  q_status=0; q ratatoskr "select count(*) from knowledge.nothing" >/dev/null 2>&1 || q_status=$?
  printf "q_status=%s\n" "$q_status"
  assert vacuous_equality '"'"'[ "$(q ratatoskr "select count(*) from knowledge.nothing")" = "$(q ratatoskr "select count(*) from knowledge.also_nothing")" ]'"'"'
  printf "fail_count=%s\n" "$FAIL_COUNT"' _ "$native/lib/common.sh" "$native/lib/assert.sh" 2>/dev/null)
rg --quiet '^q_status=1$' <<<"$q_run" || fail "q returned zero on a psql error: $q_run"
rg --quiet '^ASSERT vacuous_equality: FAIL .*a query failed' <<<"$q_run" || fail "an assertion over a failed query did not FAIL: $q_run"
rg --quiet '^fail_count=1$' <<<"$q_run" || fail "the failed query was not counted: $q_run"
stale_table=$(rg --files-with-matches 'ingest_failures' "$native/flows" "$native/lib" || true)
[[ -z "$stale_table" ]] || fail "a flow still names the table Knowledge dropped (ingest_failures): $stale_table"

# F6: the foreign-subject probe names a subject the resilience tombstone did not delete, and the search wait is a loop.
f6="$native/flows/f6-privacy-deletion.sh"
rg --quiet --fixed-strings 'limit 1 offset 1' "$f6" || fail "f6 does not select a second subject for the foreign-subject probe"
rg --quiet 'natsprobe.py" tombstone .* "\$archive" "\$source"\)' "$f6" || fail "f6 lost the resilience tombstone"
rg --quiet 'natsprobe.py" tombstone .* "user:\$U2" "\$archive" "\$other_source"\)' "$f6" || fail "f6's foreign-subject probe does not name the second subject"
rg --quiet --fixed-strings 'untilt '"'"'[ "$(q ratatoskr "select count(*) from knowledge.search_documents")" -ge 1 ]'"'"' 120' "$f6" || fail "f6 does not wait for search_documents with untilt before asserting on it"

# F1: the driver waits for fresh capabilities before the first prepare, and every upload records its digest.
rg --quiet --fixed-strings 'deadline = time.time() + 90' "$native/fixtures/f1_scenario.py" || fail "f1_scenario.py does not wait 90 s for fresh capabilities"
rg --quiet --fixed-strings 'fresh(j)' "$native/fixtures/f1_scenario.py" || fail "f1_scenario.py does not check the capabilities for freshness"
rg --quiet --fixed-strings '.sha256' "$native/fixtures/f1_scenario.py" || fail "f1_scenario.py does not record the digest of what it uploads"
rg --quiet --fixed-strings '.sha256' "$native/lib/services.sh" || fail "upload_archive does not record the digest of what it uploads"

# --- Round 6 (R6-04 rules 2 to 4): the F1 reaper assertions assert what their names say -----------------------------
# The scan reads the Python AST, so the assertion is found whatever its layout, and it is proved on a good and a bad scratch scenario before it is trusted on the real file.
cat >"$scratch/scan_f1.py" <<'PYEOF'
import ast, sys

def calls(tree):
    found = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and getattr(node.func, "id", "") == "A" and node.args and isinstance(node.args[0], ast.Constant):
            found[node.args[0].value] = " ".join(ast.unparse(arg) for arg in node.args[1:])  # the condition and the detail, never the name
    return found

source = open(sys.argv[1], encoding="utf-8").read()
found = calls(ast.parse(source))
problems = []
refused = found.get("reaper.digest_mismatch_session_is_refused")
failed = found.get("reaper.mismatch_session_is_failed")
if refused is None:
    problems.append("reaper.digest_mismatch_session_is_refused is not asserted")
else:
    for needle in ("outcome", "digest_mismatch", "declared_sha256_hex", "computed_sha256_hex"):
        if needle not in refused:
            problems.append(f"the refused assertion does not mention {needle}")
    for banned in ("in (400, 409, 422)", "404"):
        if banned in refused:
            problems.append(f"the refused assertion still accepts {banned}")
if failed is None:
    problems.append("reaper.mismatch_session_is_failed is not asserted")
elif "not in states" in failed or "not in" in failed:
    problems.append("the failed assertion still passes when the row is gone (not in ...)")
if "dirs left=" in source:
    problems.append("a PASS detail still prints dirs left=")
print("; ".join(problems))
sys.exit(1 if problems else 0)
PYEOF
cat >"$scratch/f1_bad.py" <<'PYEOF'
A("reaper.digest_mismatch_session_is_refused", fs in (400, 409, 422) or mismatch.status()[0] == 404, f"finalize={fs}")
A("reaper.mismatch_session_is_failed", states.get(mismatch.token) == "failed" or mismatch.token not in states, "x")
A("reaper.abandoned", gone, f"dirs left={[d for d in staging_dirs()]}")
PYEOF
cat >"$scratch/f1_good.py" <<'PYEOF'
A(
    "reaper.digest_mismatch_session_is_refused",
    fs == 200 and fj.get("outcome") == "digest_mismatch" and fj.get("declared_sha256_hex") == declared and fj.get("computed_sha256_hex") == computed and declared != computed,
    "x",
)
A("reaper.mismatch_session_is_failed", row == "failed", "x")
A("reaper.abandoned", gone, "removed=abandoned,mismatch,orphan kept=fresh")
PYEOF
status=0
"$PY" -I "$scratch/scan_f1.py" "$scratch/f1_good.py" >/dev/null || status=$?
[[ $status == 0 ]] || fail "the F1 scan rejects a scenario that asserts exactly what the names say"
status=0
bad=$("$PY" -I "$scratch/scan_f1.py" "$scratch/f1_bad.py") || status=$?
[[ $status == 1 ]] || fail "the F1 scan accepts a scenario with the old assertions"
for symptom in "still accepts in (400, 409, 422)" "still accepts 404" "not in" "dirs left="; do
  rg --quiet --fixed-strings "$symptom" <<<"$bad" || fail "the F1 scan did not name the symptom '$symptom' on the old assertions: $bad"
done
f1_findings=$("$PY" -I "$scratch/scan_f1.py" "$native/fixtures/f1_scenario.py") || fail "f1_scenario.py: $f1_findings"

# --- syntax, and shellcheck when installed -----------------------------------------------------------------------
for script in "${scripts[@]}"; do
  bash -n "$script" || fail "syntax error in $script"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x -S warning "${scripts[@]}" || fail "shellcheck reports warnings"
else
  printf 'shellcheck is not installed; skipped\n'
fi
for python_file in "$native"/lib/*.py "$native"/fixtures/*.py; do
  "$PY" -I -c 'import ast,sys; ast.parse(open(sys.argv[1], encoding="utf-8").read())' "$python_file" || fail "syntax error in $python_file"
done

# --- every binary a flow builds exists in the pinned checkout -----------------------------------------------------
for flow_file in "$native"/flows/f?-*.sh; do
  while read -r spec; do
    [[ -z "$spec" ]] && continue
    repo=${spec%%:*}
    bins=${spec#*:}
    dir=$(bash -c "source '$native/lib/common.sh'; repo_dir $repo") || fail "$flow_file names an unknown repository $repo"
    [[ -e "$dir/.git" ]] || fail "$flow_file needs $repo, which is not checked out"
    for bin in $bins; do
      git -C "$dir" grep -q -E "name[[:space:]]*=[[:space:]]*\"$bin\"" -- '*Cargo.toml' || fail "$flow_file builds $bin, which no Cargo.toml of $repo names"
    done
  done < <(bash -c "source '$native/lib/common.sh'; source '$flow_file'; printf '%s\n' \"\${FLOW_BINARIES[@]}\"")
done

# --- the configuration renderer ----------------------------------------------------------------------------------
cat >"$scratch/example.conf" <<'EOF'
# a comment that mentions RATATOSKR__A=ignored
RATATOSKR__A=1
RATATOSKR__DATABASE__URL=postgres://role:CHANGE-ME@127.0.0.1:5432/ratatoskr
RATATOSKR__SECRET__VALUE=CHANGE-ME
RATATOSKR__B=keep
# RATATOSKR__OPTIONAL=/etc/example.pem
RATATOSKR__ASSERTION_KEY=CHANGE-ME
EOF
"$PY" -I "$native/lib/render_conf.py" "$scratch/example.conf" "$scratch/out.env" "$scratch/deviations.txt" \
  "--set RATATOSKR__A=2" "--set RATATOSKR__DATABASE__URL=postgres://role:s3cr3tvalue@127.0.0.1:54329/ratatoskr" \
  "--set RATATOSKR__SECRET__VALUE=hunter2hunter2" "--uncomment RATATOSKR__OPTIONAL=/tmp/x.pem" \
  "--remove RATATOSKR__ASSERTION_KEY" "--add RATATOSKR__SEAM=http://127.0.0.1:1"
rg --quiet '^RATATOSKR__A=2$' "$scratch/out.env" || fail "render_conf did not set a key"
rg --quiet '^RATATOSKR__B=keep$' "$scratch/out.env" || fail "render_conf changed a key it was not asked to"
rg --quiet '^RATATOSKR__OPTIONAL=/tmp/x.pem$' "$scratch/out.env" || fail "render_conf did not enable a commented key"
! rg --quiet '^RATATOSKR__ASSERTION_KEY=' "$scratch/out.env" || fail "render_conf did not remove a key"
rg --quiet '^RATATOSKR__SEAM=' "$scratch/out.env" || fail "render_conf did not add a key"
[[ "$(wc -l <"$scratch/deviations.txt" | tr -d ' ')" == 6 ]] || fail "render_conf did not record exactly its six changes"
! rg --quiet 'hunter2hunter2|s3cr3tvalue' "$scratch/deviations.txt" || fail "render_conf wrote a secret into the deviation record"
status=0
"$PY" -I "$native/lib/render_conf.py" "$scratch/example.conf" "$scratch/bad.env" "$scratch/deviations.txt" "--set RATATOSKR__NOT_THERE=1" >/dev/null 2>&1 || status=$?
[[ $status != 0 ]] || fail "render_conf must refuse a key the example does not state"
[[ ! -e "$scratch/bad.env" ]] || fail "render_conf wrote a file for a refused rule"

# --- the fixtures and the fakes ----------------------------------------------------------------------------------
"$PY" -I "$native/fixtures/archives.py" "$scratch/fx" >/dev/null
# Two builds of every fixture are byte-equal (fixed member timestamps, order and compression), so a digest recorded at upload time and one recomputed later agree.
"$PY" -I "$native/fixtures/archives.py" "$scratch/fx2" >/dev/null
for built in "$scratch/fx"/*; do
  cmp -s "$built" "$scratch/fx2/$(basename "$built")" || fail "archives.py is not deterministic: $(basename "$built") differs between two builds"
done
for archive in chatgpt-conversations-only chatgpt-full chatgpt-asset-missing chatgpt-multichunk chatgpt-series-1 chatgpt-series-2 chatgpt-series-3 chatgpt-u2 \
  chatgpt-inflight claude-inflight claude-complete claude-nofiles claude-reference-only claude-badkb claude-series-1 claude-series-2 claude-series-3 claude-u2; do
  "$PY" -I -c 'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None and z.namelist()' "$scratch/fx/$archive.zip" || fail "archive $archive.zip is not a valid ZIP"
done
"$PY" -I -c '
import json, sys, zipfile
fx = sys.argv[1]
one = {c["id"] for c in json.loads(zipfile.ZipFile(f"{fx}/chatgpt-series-1.zip").read("conversations.json"))}
three = {c["id"] for c in json.loads(zipfile.ZipFile(f"{fx}/chatgpt-series-3.zip").read("conversations.json"))}
assert one < three and len(three) == 3, (one, three)
assert open(f"{fx}/chatgpt-series-1.zip", "rb").read() != open(f"{fx}/chatgpt-series-3.zip", "rb").read()
' "$scratch/fx" || fail "the cumulative series is not cumulative"
[[ "$(head -c 9 "$scratch/fx/corrupt.zip")" != "PK"* ]] || fail "corrupt.zip is a ZIP"
"$PY" -I "$native/fixtures/make_pki.py" "$scratch/pki"
if command -v openssl >/dev/null 2>&1; then
  openssl verify -CAfile "$scratch/pki/ca.pem" "$scratch/pki/leaf.pem" >/dev/null || fail "the throwaway leaf does not verify against the throwaway CA"
fi
mkdir -p "$scratch/session"
"$PY" -I "$native/fixtures/session_file.py" "$scratch/session"
[[ "$(wc -c <"$scratch/session/session.key" | tr -d ' ')" == 32 && -s "$scratch/session/session.enc" ]] || fail "session_file.py did not write a key and a session"
[[ "$(stat -f %Lp "$scratch/session/session.key" 2>/dev/null || stat -c %a "$scratch/session/session.key")" == 600 ]] || fail "the session key is not mode 0600"

free_port() { "$PY" -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()'; }
wait_port() {
  local i
  for ((i = 0; i < 40; i++)); do
    (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && return 0
    sleep 0.25
  done
  return 1
}
mkdir -p "$scratch/run" "$scratch/botfiles"
printf 'bot file' >"$scratch/botfiles/doc1.pdf"

port=$(free_port)
"$PY" -I "$native/fixtures/fake_openrouter.py" "$port" "$scratch/or.jsonl" "$scratch/run" &
background+=("$!")
wait_port "$port" || fail "fake_openrouter.py did not start"
or_port=$port
post() { curl -s -o "$scratch/body" -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data "$2" "http://127.0.0.1:$1$3"; }
recap=$(jq -nc '{model:"m",messages:[{role:"system",content:"s"},{role:"user",content:"refs channel-post-revision:018f0000-0000-7000-8000-000000000001 and channel-post-revision:018f0000-0000-7000-8000-000000000002"}]}')
[[ "$(post "$port" "$recap" /api/v1/chat/completions)" == 200 ]] || fail "the fake OpenRouter did not answer a recap request"
jq -e '.choices[0].message.content | fromjson | (.topics | length) == 2' "$scratch/body" >/dev/null || fail "the fake recap does not cite both revisions"
[[ "$(post "$port" '{"model":"m","messages":[{"role":"user","content":"nothing known"}]}' /api/v1/chat/completions)" == 400 ]] || fail "the fake OpenRouter answered an unknown family"
repository_prompt=$(jq -nc --rawfile readme /dev/stdin '{model:"m",messages:[{role:"system",content:"s"},{role:"user",content:("family: repository\nrepository_id: 42\nfull_name: owner/repository\ndescription: A fixture\nprimary_language: Rust\nREADME_BEGIN\n" + $readme + "README_END\n")}]}' <<<"# Fixture repository
It indexes synthetic documents.")
[[ "$(post "$port" "$repository_prompt" /api/v1/chat/completions)" == 200 ]] || fail "the fake OpenRouter did not answer a repository-analysis prompt"
jq -e '.choices[0].message.content | fromjson | (keys == ["evidence_excerpt","readme_evidence","summary","topics"]) and (.readme_evidence == "present") and (.summary | length > 0 and length <= 2000) and (.evidence_excerpt | length > 0 and length <= 500) and (.topics | length <= 12)' "$scratch/body" >/dev/null || fail "the fake repository analysis is not schema-valid"
jq -e '.choices[0].message.content | fromjson | .evidence_excerpt | . as $e | "# Fixture repository\nIt indexes synthetic documents.\n" | contains($e)' "$scratch/body" >/dev/null || fail "the fake repository analysis cites text the README does not hold"

: >"$scratch/run/fake-fail"
[[ "$(post "$port" "$recap" /api/v1/chat/completions)" == 401 ]] || fail "the fake OpenRouter ignored its failure switch"
rm -f "$scratch/run/fake-fail"

port=$(free_port)
"$PY" -I "$native/fixtures/fake_github.py" "$port" "$scratch/gh.jsonl" "$scratch/run" &
background+=("$!")
wait_port "$port" || fail "fake_github.py did not start"
[[ "$(curl -s "http://127.0.0.1:$port/repos/owner/repository" | jq .id)" == 42 ]] || fail "the fake GitHub does not serve the numeric id the track body names"
etag=$(curl -s -D- -o /dev/null "http://127.0.0.1:$port/repos/owner/repository" | tr -d '\r' | awk -F': ' 'tolower($1)=="etag"{print $2}')
[[ "$(curl -s -o /dev/null -w '%{http_code}' -H "If-None-Match: $etag" "http://127.0.0.1:$port/repos/owner/repository")" == 304 ]] || fail "the fake GitHub does not answer 304 for an unchanged repository"
printf 'changed description\n' >"$scratch/run/github-description"
curl -s "http://127.0.0.1:$port/repos/owner/repository" | jq -e '.description == "changed description"' >/dev/null || fail "the fake GitHub ignored its description control file"
rm -f "$scratch/run/github-description"

port=$(free_port)
"$PY" -I "$native/fixtures/fake_bot_api.py" "$port" "$scratch/bot.jsonl" "$scratch/botfiles" &
background+=("$!")
wait_port "$port" || fail "fake_bot_api.py did not start"
[[ "$(post "$port" '{"chat_id":900700601,"text":"hello"}' /botTOKEN/SendMessage)" == 200 ]] || fail "the fake Bot API did not answer sendMessage"
[[ "$(post "$port" '{"file_id":"doc1.pdf"}' /botTOKEN/getFile)" == 200 ]] || fail "the fake Bot API did not answer getFile"
[[ "$(curl -s "http://127.0.0.1:$port/file/botTOKEN/doc1.pdf")" == "bot file" ]] || fail "the fake Bot API did not serve the file"
! rg --quiet 'TOKEN' "$scratch/bot.jsonl" || fail "the fake Bot API logged the bot token"
[[ "$(jq -s 'length' "$scratch/bot.jsonl")" == 2 ]] || fail "the fake Bot API did not record the calls in order"
bot_api_fixture="$workspace_root/repos/integrations/telegram/crates/bot-api/tests/fixtures/get_me.json"
[[ -f "$bot_api_fixture" ]] || fail "the bot-api crate's getMe fixture is not in the pinned Telegram checkout: $bot_api_fixture"
curl -s "http://127.0.0.1:$port/botTOKEN/getMe" >"$scratch/getme.json"
missing=$(jq -rn --slurpfile fixture "$bot_api_fixture" --slurpfile fake "$scratch/getme.json" '($fixture[0].result | keys) - ($fake[0].result | keys) | join(",")')
[[ -z "$missing" ]] || fail "the fake Bot API's getMe lacks the keys the bot-api crate requires: $missing"


x_port=$(free_port)
"$PY" -I "$native/fixtures/fake_x_api.py" "$x_port" "$scratch/pki/leaf.pem" "$scratch/pki/leaf.key" "$scratch/x.jsonl" &
background+=("$!")
wait_port "$x_port" || fail "fake_x_api.py did not start"
[[ "$(curl -s --cacert "$scratch/pki/ca.pem" "https://127.0.0.1:$x_port/2/tweets?ids=1700000000000000001" | jq -r '.data[0].id')" == 1700000000000000001 ]] || fail "the fake X API did not serve a post over the throwaway CA"
[[ "$(curl -s --cacert "$scratch/pki/ca.pem" "https://127.0.0.1:$x_port/2/tweets?ids=1404" | jq -r '.errors[0].title')" == "Not Found Error" ]] || fail "the fake X API did not serve a deleted post"
[[ "$(curl -s -o /dev/null -w '%{http_code}' --cacert "$scratch/pki/ca.pem" "https://127.0.0.1:$x_port/2/tweets?ids=1401")" == 401 ]] || fail "the fake X API did not serve an unauthorized post"

tap_port=$(free_port)
"$PY" -I "$native/fixtures/tap_proxy.py" "$tap_port" "$port" "$scratch/tap.jsonl" &
background+=("$!")
wait_port "$tap_port" || fail "tap_proxy.py did not start"
curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -H 'Authorization: Bearer secret-credential' --data '{"assertion":"secret-assertion","origin":{"forwarded":true}}' "http://127.0.0.1:$tap_port/botTOKEN/SendMessage"
jq -e '.method == "POST" and .request.origin.forwarded == true and .request.assertion == "[redacted]"' "$scratch/tap.jsonl" >/dev/null || fail "the tap did not record the request with the assertion redacted"
! rg --quiet 'secret-credential|secret-assertion' "$scratch/tap.jsonl" || fail "the tap recorded a credential"

# --- Round 5 fixtures: the status schedule of the OpenRouter fake, the large archives, the 401 stand-in, the streaming tap ---
printf '402 2\n' >"$scratch/run/fake-status"
[[ "$(post "$or_port" "$recap" /api/v1/chat/completions)" == 402 ]] || fail "the fake OpenRouter ignored its status schedule"
sleep 3
[[ "$(post "$or_port" "$recap" /api/v1/chat/completions)" == 200 ]] || fail "the fake OpenRouter did not recover when its status schedule ended"
rm -f "$scratch/run/fake-status"

"$PY" -I "$native/fixtures/big_archives.py" "$scratch/big" >/dev/null
"$PY" -I "$native/fixtures/big_archives.py" "$scratch/big2" >/dev/null
for archive in chatgpt-large-2mib chatgpt-large-7p9mb claude-large-2mib claude-large-7p9mb; do
  cmp -s "$scratch/big/$archive.zip" "$scratch/big2/$archive.zip" || fail "big_archives.py is not deterministic: $archive"
  "$PY" -I -c 'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None and len(z.namelist()) == 1' "$scratch/big/$archive.zip" || fail "$archive.zip is not a valid one-member ZIP"
done
[[ "$(wc -c <"$scratch/big/chatgpt-large-7p9mb.zip" | tr -d ' ')" -lt 8000000 ]] || fail "the large ChatGPT conversation does not stay below RATATOSKR__RECEIPT__MAX_EVENT_BYTES (8000000)"
[[ "$(wc -c <"$scratch/big/claude-large-2mib.zip" | tr -d ' ')" -gt 2097152 ]] || fail "the 2 MiB conversation is smaller than 2 MiB"

stand_port=$(free_port)
"$PY" -I "$native/fixtures/stand_in_receipt.py" "$stand_port" &
background+=("$!")
wait_port "$stand_port" || fail "stand_in_receipt.py did not start"
[[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST --data x "http://127.0.0.1:$stand_port/v1/claude/receipt")" == 401 ]] || fail "the receipt stand-in did not answer 401"

# The tap passes a text/event-stream response through as it arrives (the dispatcher's progress stream must not be held back or timed out by the harness).
sse_port=$(free_port)
"$PY" -I -c '
import http.server, sys, time
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.send_header("Connection", "close"); self.end_headers()
        self.wfile.write(b"data: first\n\n"); self.wfile.flush(); time.sleep(6); self.wfile.write(b"data: second\n\n")
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()' "$sse_port" &
background+=("$!")
wait_port "$sse_port" || fail "the SSE test upstream did not start"
tap2_port=$(free_port)
"$PY" -I "$native/fixtures/tap_proxy.py" "$tap2_port" "$sse_port" "$scratch/tap2.jsonl" &
background+=("$!")
wait_port "$tap2_port" || fail "tap_proxy.py (stream test) did not start"
first_frame=$(curl -sN --max-time 2 "http://127.0.0.1:$tap2_port/v1/operations/x/events" || true)
[[ "$first_frame" == *"data: first"* ]] || fail "the tap held back a text/event-stream response until it ended: '$first_frame'"
jq -e 'select(.path == "/v1/operations/x/events" and .streamed == true and .status == 200)' "$scratch/tap2.jsonl" >/dev/null || fail "the tap did not record the stream when it started"

# --- the PDF generator -------------------------------------------------------------------------------------------
"$PY" -I "$native/fixtures/pdfs.py" "$scratch/pdfs"
[[ "$(head -c 8 "$scratch/pdfs/text-small.pdf")" == "%PDF-1.4" ]] || fail "pdfs.py did not write a PDF"
[[ "$(wc -c <"$scratch/pdfs/big-over.pdf" | tr -d ' ')" -gt 8000000 && "$(wc -c <"$scratch/pdfs/big-under.pdf" | tr -d ' ')" -lt 8000000 ]] || fail "the big PDFs are not on either side of the event limit"
if command -v pdftotext >/dev/null 2>&1; then
  pdftotext "$scratch/pdfs/text-small.pdf" - | rg --quiet 'Chartreuse' || fail "the small PDF has no extractable text"
fi

# --- the NATS probe module decodes a seed written in the nkeys format and derives a well-formed public key ---------
"$PY" -B -I -c '
import base64, os, sys
sys.path.insert(0, sys.argv[1])
import natsprobe
def crc16(data):
    crc = 0
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc
raw32 = os.urandom(32)
body = bytes([(18 << 3) | ((20 << 3) >> 5), ((20 << 3) & 31) << 3]) + raw32
text = base64.b32encode(body + crc16(body).to_bytes(2, "little")).decode().rstrip("=")
assert text.startswith("SU") and len(text) == 58, text
assert natsprobe._seed_bytes(text) == raw32
public = natsprobe._pub(raw32)
assert public.startswith("U") and len(public) == 56, public
decoded = base64.b32decode(public)
assert crc16(decoded[:-2]) == int.from_bytes(decoded[-2:], "little")
' "$native/fixtures" || fail "natsprobe.py does not round-trip an nkey seed"

printf 'native smoke contract: PASS\n'
