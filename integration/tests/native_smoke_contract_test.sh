#!/usr/bin/env bash
# Contract test of the native smoke harness (integration/native, XR-021 round 3 task 4). It checks the scripts themselves and starts no service, builds nothing and needs no Docker: the flow list, the prerequisite check and its exit codes, the busy-port report, --prune, the safety rules (no pkill, no kill of an unrecorded pid, no write outside the state directory), shellcheck when installed, the Python fixtures and fakes, the configuration renderer, and that every binary a flow builds exists in the pinned checkout. It does NOT prove that a flow passes against real services; that is the manual run, and none of the flows has been run through run.sh as committed.
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
port=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')
python3 -c 'import socket,sys,time
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
(cd "$workspace_root" && git check-ignore --quiet evidence/XR-021-r3/f0/result.txt) || fail "evidence/XR-021-r3 is not gitignored"

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
  python3 -I -c 'import ast,sys; ast.parse(open(sys.argv[1], encoding="utf-8").read())' "$python_file" || fail "syntax error in $python_file"
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
python3 -I "$native/lib/render_conf.py" "$scratch/example.conf" "$scratch/out.env" "$scratch/deviations.txt" \
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
python3 -I "$native/lib/render_conf.py" "$scratch/example.conf" "$scratch/bad.env" "$scratch/deviations.txt" "--set RATATOSKR__NOT_THERE=1" >/dev/null 2>&1 || status=$?
[[ $status != 0 ]] || fail "render_conf must refuse a key the example does not state"
[[ ! -e "$scratch/bad.env" ]] || fail "render_conf wrote a file for a refused rule"

# --- the fixtures and the fakes ----------------------------------------------------------------------------------
python3 -I "$native/fixtures/archives.py" "$scratch/fx" >/dev/null
for archive in chatgpt-conversations-only chatgpt-full chatgpt-asset-missing chatgpt-multichunk chatgpt-series-1 chatgpt-series-2 chatgpt-series-3 chatgpt-u2 \
  claude-complete claude-nofiles claude-reference-only claude-series-1 claude-series-2 claude-series-3 claude-u2; do
  python3 -I -c 'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None and z.namelist()' "$scratch/fx/$archive.zip" || fail "archive $archive.zip is not a valid ZIP"
done
python3 -I -c '
import json, sys, zipfile
fx = sys.argv[1]
one = {c["id"] for c in json.loads(zipfile.ZipFile(f"{fx}/chatgpt-series-1.zip").read("conversations.json"))}
three = {c["id"] for c in json.loads(zipfile.ZipFile(f"{fx}/chatgpt-series-3.zip").read("conversations.json"))}
assert one < three and len(three) == 3, (one, three)
assert open(f"{fx}/chatgpt-series-1.zip", "rb").read() != open(f"{fx}/chatgpt-series-3.zip", "rb").read()
' "$scratch/fx" || fail "the cumulative series is not cumulative"
[[ "$(head -c 9 "$scratch/fx/corrupt.zip")" != "PK"* ]] || fail "corrupt.zip is a ZIP"
python3 -I "$native/fixtures/make_pki.py" "$scratch/pki"
if command -v openssl >/dev/null 2>&1; then
  openssl verify -CAfile "$scratch/pki/ca.pem" "$scratch/pki/leaf.pem" >/dev/null || fail "the throwaway leaf does not verify against the throwaway CA"
fi
mkdir -p "$scratch/session"
python3 -I "$native/fixtures/session_file.py" "$scratch/session"
[[ "$(wc -c <"$scratch/session/session.key" | tr -d ' ')" == 32 && -s "$scratch/session/session.enc" ]] || fail "session_file.py did not write a key and a session"
[[ "$(stat -f %Lp "$scratch/session/session.key" 2>/dev/null || stat -c %a "$scratch/session/session.key")" == 600 ]] || fail "the session key is not mode 0600"

free_port() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()'; }
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
python3 -I "$native/fixtures/fake_openrouter.py" "$port" "$scratch/or.jsonl" "$scratch/run" &
background+=("$!")
wait_port "$port" || fail "fake_openrouter.py did not start"
post() { curl -s -o "$scratch/body" -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data "$2" "http://127.0.0.1:$1$3"; }
recap=$(jq -nc '{model:"m",messages:[{role:"system",content:"s"},{role:"user",content:"refs channel-post-revision:018f0000-0000-7000-8000-000000000001 and channel-post-revision:018f0000-0000-7000-8000-000000000002"}]}')
[[ "$(post "$port" "$recap" /api/v1/chat/completions)" == 200 ]] || fail "the fake OpenRouter did not answer a recap request"
jq -e '.choices[0].message.content | fromjson | (.topics | length) == 2' "$scratch/body" >/dev/null || fail "the fake recap does not cite both revisions"
[[ "$(post "$port" '{"model":"m","messages":[{"role":"user","content":"nothing known"}]}' /api/v1/chat/completions)" == 400 ]] || fail "the fake OpenRouter answered an unknown family"
: >"$scratch/run/fake-fail"
[[ "$(post "$port" "$recap" /api/v1/chat/completions)" == 401 ]] || fail "the fake OpenRouter ignored its failure switch"
rm -f "$scratch/run/fake-fail"

port=$(free_port)
python3 -I "$native/fixtures/fake_github.py" "$port" "$scratch/gh.jsonl" "$scratch/run" &
background+=("$!")
wait_port "$port" || fail "fake_github.py did not start"
[[ "$(curl -s "http://127.0.0.1:$port/repos/owner/repository" | jq .id)" == 42 ]] || fail "the fake GitHub does not serve the numeric id the track body names"
etag=$(curl -s -D- -o /dev/null "http://127.0.0.1:$port/repos/owner/repository" | tr -d '\r' | awk -F': ' 'tolower($1)=="etag"{print $2}')
[[ "$(curl -s -o /dev/null -w '%{http_code}' -H "If-None-Match: $etag" "http://127.0.0.1:$port/repos/owner/repository")" == 304 ]] || fail "the fake GitHub does not answer 304 for an unchanged repository"
printf 'changed description\n' >"$scratch/run/github-description"
curl -s "http://127.0.0.1:$port/repos/owner/repository" | jq -e '.description == "changed description"' >/dev/null || fail "the fake GitHub ignored its description control file"
rm -f "$scratch/run/github-description"

port=$(free_port)
python3 -I "$native/fixtures/fake_bot_api.py" "$port" "$scratch/bot.jsonl" "$scratch/botfiles" &
background+=("$!")
wait_port "$port" || fail "fake_bot_api.py did not start"
[[ "$(post "$port" '{"chat_id":900700601,"text":"hello"}' /botTOKEN/SendMessage)" == 200 ]] || fail "the fake Bot API did not answer sendMessage"
[[ "$(post "$port" '{"file_id":"doc1.pdf"}' /botTOKEN/getFile)" == 200 ]] || fail "the fake Bot API did not answer getFile"
[[ "$(curl -s "http://127.0.0.1:$port/file/botTOKEN/doc1.pdf")" == "bot file" ]] || fail "the fake Bot API did not serve the file"
! rg --quiet 'TOKEN' "$scratch/bot.jsonl" || fail "the fake Bot API logged the bot token"
[[ "$(jq -s 'length' "$scratch/bot.jsonl")" == 2 ]] || fail "the fake Bot API did not record the calls in order"

x_port=$(free_port)
python3 -I "$native/fixtures/fake_x_api.py" "$x_port" "$scratch/pki/leaf.pem" "$scratch/pki/leaf.key" "$scratch/x.jsonl" &
background+=("$!")
wait_port "$x_port" || fail "fake_x_api.py did not start"
[[ "$(curl -s --cacert "$scratch/pki/ca.pem" "https://127.0.0.1:$x_port/2/tweets?ids=1700000000000000001" | jq -r '.data[0].id')" == 1700000000000000001 ]] || fail "the fake X API did not serve a post over the throwaway CA"
[[ "$(curl -s --cacert "$scratch/pki/ca.pem" "https://127.0.0.1:$x_port/2/tweets?ids=1404" | jq -r '.errors[0].title')" == "Not Found Error" ]] || fail "the fake X API did not serve a deleted post"
[[ "$(curl -s -o /dev/null -w '%{http_code}' --cacert "$scratch/pki/ca.pem" "https://127.0.0.1:$x_port/2/tweets?ids=1401")" == 401 ]] || fail "the fake X API did not serve an unauthorized post"

tap_port=$(free_port)
python3 -I "$native/fixtures/tap_proxy.py" "$tap_port" "$port" "$scratch/tap.jsonl" &
background+=("$!")
wait_port "$tap_port" || fail "tap_proxy.py did not start"
curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -H 'Authorization: Bearer secret-credential' --data '{"assertion":"secret-assertion","origin":{"forwarded":true}}' "http://127.0.0.1:$tap_port/botTOKEN/SendMessage"
jq -e '.method == "POST" and .request.origin.forwarded == true and .request.assertion == "[redacted]"' "$scratch/tap.jsonl" >/dev/null || fail "the tap did not record the request with the assertion redacted"
! rg --quiet 'secret-credential|secret-assertion' "$scratch/tap.jsonl" || fail "the tap recorded a credential"

# --- the PDF generator -------------------------------------------------------------------------------------------
python3 -I "$native/fixtures/pdfs.py" "$scratch/pdfs"
[[ "$(head -c 8 "$scratch/pdfs/text-small.pdf")" == "%PDF-1.4" ]] || fail "pdfs.py did not write a PDF"
[[ "$(wc -c <"$scratch/pdfs/big-over.pdf" | tr -d ' ')" -gt 8000000 && "$(wc -c <"$scratch/pdfs/big-under.pdf" | tr -d ' ')" -lt 8000000 ]] || fail "the big PDFs are not on either side of the event limit"
if command -v pdftotext >/dev/null 2>&1; then
  pdftotext "$scratch/pdfs/text-small.pdf" - | rg --quiet 'Chartreuse' || fail "the small PDF has no extractable text"
fi

# --- the NATS probe module decodes a seed written in the nkeys format and derives a well-formed public key ---------
python3 -B -I -c '
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
