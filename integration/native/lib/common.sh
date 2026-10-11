#!/usr/bin/env bash
# shellcheck disable=SC2034
# Shared settings and helpers of the native smoke. Source this file; it runs nothing. Every path the smoke writes is under $RATATOSKR_SMOKE_DIR (state, binaries, data, keys, rendered configs, logs) or under the gitignored evidence/ directory of the workspace; nothing is written inside a repository. A process is only ever stopped through a pid file that lib/services.sh or lib/nats.sh wrote itself.

export PYTHONDONTWRITEBYTECODE=1
NATIVE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORKSPACE_ROOT=$(cd "$NATIVE_ROOT/../.." && pwd)
R=$WORKSPACE_ROOT/repos
S=${RATATOSKR_SMOKE_DIR:-$HOME/.cache/ratatoskr-smoke/XR-021-r3}
EVIDENCE_ROOT=$WORKSPACE_ROOT/evidence/XR-021-r3
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

# Path of a repository checkout by the identity workspace.toml gives it.
repo_dir() {
  local path
  path=$(awk -v id="$1" '
    /^\[\[repositories\]\]/ { current = ""; next }
    /^id = / { gsub(/"/, "", $3); current = $3 }
    /^path = / && current == id { gsub(/"/, "", $3); print $3; exit }
  ' "$WORKSPACE_ROOT/workspace.toml")
  [[ -n "$path" ]] || smoke_die "repository $1 is not in workspace.toml"
  printf '%s/%s' "$WORKSPACE_ROOT" "$path"
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
    (umask 077 && head -c 24 /dev/urandom | base64 | tr -d '/+=\n' >"$file")
  fi
  cat "$file"
}

# sha256 of a string, hex.
sha256_text() { printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1; }
sha256_file() { shasum -a 256 "$1" | cut -d' ' -f1; }
