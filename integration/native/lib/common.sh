#!/usr/bin/env bash
# shellcheck disable=SC2034
# Shared settings and helpers of the native smoke. Source this file; it runs nothing. Every path the smoke writes is under $RATATOSKR_SMOKE_DIR (state, binaries, data, keys, rendered configs, logs) or under the gitignored evidence/ directory of the workspace; nothing is written inside a repository. A process is only ever stopped through a pid file that lib/services.sh or lib/nats.sh wrote itself.

export PYTHONDONTWRITEBYTECODE=1
NATIVE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORKSPACE_ROOT=$(cd "$NATIVE_ROOT/../.." && pwd)
R=$WORKSPACE_ROOT/repos
S=${RATATOSKR_SMOKE_DIR:-$HOME/.cache/ratatoskr-smoke/XR-021-r6}
EVIDENCE_ROOT=$WORKSPACE_ROOT/evidence/XR-021-r6
# Which source the flows build and read: empty means the commits the workspace pins (the submodule checkouts under repos/, which are never touched). A git ref such as origin/main exports that ref of every repository a flow uses into $S/src with git archive (src_prepare), so a flow can run against the heads the children publish before the workspace pins them; the submodules stay at their pins and clean.
SMOKE_REF=${RATATOSKR_SMOKE_REF:-}
if [[ -n "$SMOKE_REF" ]]; then R=$S/src; else R=$WORKSPACE_ROOT/repos; fi
SMOKE_MARKER=.ratatoskr-smoke-dir

# PostgreSQL is the one port that is not a production port (R3-17): a private port whose URL is configuration.
PG_PORT=54329
export PGHOST=$S/pgrun PGPORT=$PG_PORT PGUSER=postgres

# Production loopback ports of docs/DEPLOYMENT_TARGET.md that more than one flow uses, and the private ports of the fakes.
EDGE=http://127.0.0.1:8080
EDGE_ADMIN=http://127.0.0.1:9464
NATS_MON=http://127.0.0.1:8222
FAKE_OPENROUTER_PORT=18791
FAKE_BOT_PORT=18792
FAKE_X_PORT=18793
FAKE_GITHUB_PORT=18794
FAKE_TAP_PORT=18796
INFRA_PORTS="4222 8222 8080 9464 $PG_PORT"

U1=01980000-0000-7000-8000-000000000001
U2=01980000-0000-7000-8000-000000000002

smoke_die() {
  printf 'smoke: %s\n' "$*" >&2
  exit 2
}

# The state directory must be a bounded absolute path that is not a home directory or a repository, because --prune deletes inside it.
smoke_dir_guard() {
  case "$S" in
    /*) ;;
    *) smoke_die "RATATOSKR_SMOKE_DIR must be absolute: $S" ;;
  esac
  [[ "$S" != "/" && "$S" != "$HOME" && "$S" != "$HOME/" ]] || smoke_die "RATATOSKR_SMOKE_DIR must not be / or the home directory"
  local depth
  depth=$(awk -F/ '{print NF-1}' <<<"$S")
  ((depth >= 3)) || smoke_die "RATATOSKR_SMOKE_DIR is too shallow to be a scratch directory: $S"
  case "$S" in
    "$WORKSPACE_ROOT"|"$WORKSPACE_ROOT"/*) smoke_die "RATATOSKR_SMOKE_DIR must be outside the workspace checkout: $S" ;;
  esac
}

smoke_init_dirs() {
  smoke_dir_guard
  (umask 077 && mkdir -p "$S" "$S/bin" "$S/conf" "$S/nk" "$S/run" "$S/logs" "$S/pgrun" "$S/nats-js" "$S/staging" "$S/blobs" "$S/fx" "$S/keys" "$S/render")
  : >"$S/$SMOKE_MARKER"
}

# The path workspace.toml gives a repository, relative to the workspace root (repos/<group>/<name>).
repo_path() {
  local path
  path=$(awk -v id="$1" '
    /^\[\[repositories\]\]/ { current = ""; next }
    /^id = / { gsub(/"/, "", $3); current = $3 }
    /^path = / && current == id { gsub(/"/, "", $3); print $3; exit }
  ' "$WORKSPACE_ROOT/workspace.toml")
  [[ -n "$path" ]] || smoke_die "repository $1 is not in workspace.toml"
  printf '%s' "$path"
}

# The pinned submodule checkout of a repository: the baseline, read only, and the directory the clean check inspects.
baseline_dir() { printf '%s/%s' "$WORKSPACE_ROOT" "$(repo_path "$1")"; }

# The directory a flow builds from and reads deploy files from: the pinned checkout, or the export of $SMOKE_REF.
repo_dir() {
  if [[ -n "$SMOKE_REF" ]]; then
    printf '%s/%s' "$S/src" "$(repo_path "$1" | sed 's#^repos/##')"
  else
    baseline_dir "$1"
  fi
}

# The commit a flow runs: the exported ref's commit, or the pinned HEAD.
repo_commit() {
  if [[ -n "$SMOKE_REF" ]]; then
    cat "$(repo_dir "$1")/.smoke-commit"
  else
    git -C "$(baseline_dir "$1")" rev-parse HEAD
  fi
}

# One line for result.txt: which commit of each repository of the flow ran, and whether that is the workspace pin or an exported ref.
source_note() {
  local repo origin='the commits the workspace pins'
  [[ -n "$SMOKE_REF" ]] && origin="ref $SMOKE_REF"
  printf 'source (%s):' "$origin"
  # shellcheck disable=SC2086
  for repo in $FLOW_REPOS; do printf ' %s@%s' "$repo" "$(repo_commit "$repo" | cut -c1-7)"; done
  printf '\n'
}

# src_prepare REPO_ID...: exports $SMOKE_REF of each repository into $S/src (a no-op without a ref). The export is made from the submodule's object store with git archive, so neither the working tree nor any ref of the submodule changes.
src_prepare() {
  [[ -n "$SMOKE_REF" ]] || return 0
  local repo dir commit
  for repo in "$@"; do
    dir=$(repo_dir "$repo")
    commit=$(git -C "$(baseline_dir "$repo")" rev-parse --verify "$SMOKE_REF^{commit}") || smoke_die "repository $repo has no $SMOKE_REF; fetch it first"
    if [[ "$(cat "$dir/.smoke-commit" 2>/dev/null)" == "$commit" ]]; then
      continue
    fi
    rm -rf -- "${dir:?}"
    mkdir -p "$dir"
    git -C "$(baseline_dir "$repo")" archive "$commit" | tar -x -C "$dir" || smoke_die "cannot export $SMOKE_REF of $repo"
    printf '%s' "$commit" >"$dir/.smoke-commit"
    note "source: $repo at $SMOKE_REF ${commit:0:7}"
  done
}

note() { printf '%s\n' "$*"; }

# "pid N command" of the process that listens on a TCP port, or nothing. Never kills.
port_holder() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN -Fpc 2>/dev/null | awk '
    /^p/ { pid = substr($0, 2) }
    /^c/ { command = substr($0, 2); print "pid " pid " " command; exit }
  '
}

# Prints one BUSY line per port in the arguments that something listens on; returns 1 if there was one.
ports_busy() {
  local busy=0 port holder
  for port in "$@"; do
    holder=$(port_holder "$port")
    if [[ -n "$holder" ]]; then
      printf 'BUSY port %s is held by %s\n' "$port" "$holder"
      busy=1
    fi
  done
  return "$busy"
}

# Whole GiB free on the volume that holds a path (the nearest existing ancestor when the path does not exist yet).
free_gib() {
  local dir=$1
  while [[ ! -d "$dir" && "$dir" != "/" ]]; do dir=$(dirname "$dir"); done
  df -Pk "$dir" | awk 'NR == 2 { print int($4 / 1048576) }'
}

# One run at a time on this machine: an atomic mkdir.
lock_acquire() {
  mkdir -p "$S" 2>/dev/null
  if ! mkdir "$S/lock" 2>/dev/null; then
    smoke_die "another smoke run holds $S/lock; remove it only if no run is active"
  fi
}
lock_release() { rmdir "$S/lock" 2>/dev/null || true; }

secret_file() { printf '%s/conf/secret.%s' "$S" "$1"; }

# A random secret that is created once per run directory and printed.
secret() {
  local file
  file=$(secret_file "$1")
  if [[ ! -f "$file" ]]; then
    # Hex, so the length is fixed: base64 with its '/', '+' and '=' removed was sometimes shorter than the 32 characters conf_github demands.
    (umask 077 && head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' >"$file")
  fi
  cat "$file"
}

# sha256 of a string, hex.
sha256_text() { printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1; }
sha256_file() { shasum -a 256 "$1" | cut -d' ' -f1; }

# --- the Python interpreter -----------------------------------------------------------------------------------------
# The smoke needs ONE interpreter that can serve HTTP (the loopback fakes and the tap) and import cryptography (nkey and PKI fixtures, the encrypted provider session). Which python3 comes first on PATH differs per machine, and a broken one fails late and confusingly (Homebrew's 3.15 accepts a TCP connection and never answers), so it is chosen once, by a probe, from a fixed list. PY is empty until py_select runs.
PY=${PY:-}

# The probe: an HTTP server on an ephemeral loopback port that the same interpreter must answer with urllib within 3 seconds, and the cryptography module.
PY_PROBE_CODE='
import http.server, os, threading, urllib.request
import cryptography
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"ok"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
with urllib.request.urlopen("http://127.0.0.1:%d/" % server.server_address[1], timeout=3) as response:
    assert response.read() == b"ok"
os._exit(0)
'

# The candidates, in order: RATATOSKR_SMOKE_PYTHON_CANDIDATES (whitespace separated, replaces the list; the contract test uses it), else RATATOSKR_SMOKE_PYTHON, the interpreters mise installs (newest first), /usr/bin/python3, /opt/homebrew/bin/python3 and python3 on PATH.
py_candidates() {
  if [[ -n "${RATATOSKR_SMOKE_PYTHON_CANDIDATES:-}" ]]; then
    printf '%s\n' $RATATOSKR_SMOKE_PYTHON_CANDIDATES
    return
  fi
  [[ -n "${RATATOSKR_SMOKE_PYTHON:-}" ]] && printf '%s\n' "$RATATOSKR_SMOKE_PYTHON"
  local mise_python
  local -a mise_pythons=("$HOME"/.local/share/mise/installs/python/[0-9]*.[0-9]*.[0-9]*/bin/python3)
  if [[ -e "${mise_pythons[0]}" ]]; then
    while IFS= read -r mise_python; do
      printf '%s\n' "$mise_python"
    done < <(printf '%s\n' "${mise_pythons[@]}" | sort -V -r)
  fi
  printf '%s\n' /usr/bin/python3 /opt/homebrew/bin/python3
  command -v python3 || true
}

# py_probe PYTHON: exit 0 when the interpreter passes the probe within PY_PROBE_TIMEOUT seconds (default 8; a perl watchdog ends a hung probe child it started itself, never anything by name).
py_probe() {
  [[ -x "$1" ]] || return 1
  perl -e 'my $limit = shift; my $child = fork(); if (!$child) { exec @ARGV; exit 127 } $SIG{ALRM} = sub { kill("KILL", $child); exit 124 }; alarm $limit; waitpid($child, 0); exit(($? & 127) ? 128 + ($? & 127) : ($? >> 8))' "${PY_PROBE_TIMEOUT:-8}" "$1" -I -c "$PY_PROBE_CODE" >/dev/null 2>&1
}

# py_select: sets PY to the first candidate that passes the probe; returns 1 (PY empty) when none does. Idempotent.
py_select() {
  [[ -n "$PY" ]] && return 0
  local candidate
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if py_probe "$candidate"; then
      PY=$candidate
      export PY
      return 0
    fi
  done < <(py_candidates)
  return 1
}
