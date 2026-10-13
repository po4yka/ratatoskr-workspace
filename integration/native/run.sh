#!/usr/bin/env bash
# shellcheck disable=SC2034
# Native multi-service smoke (XR-021 round 3): drives each cross-repository flow through Platform Edge's HTTP API on one machine, with the deployed NATS ACL, the checked-in PostgreSQL provisioning and services built natively from the pinned submodules. No Docker.
#
#   run.sh --list                 the flows F0 to F7 with their binaries, ports and evidence status
#   run.sh --dry-run FLOW         check the prerequisites of a flow; exit 0, or exit 3 with one MISSING line per missing prerequisite
#   run.sh --prune                remove what earlier runs left under $RATATOSKR_SMOKE_DIR (nothing else)
#   run.sh FLOW [FLOW...]         run flows one at a time, in the order given
#
# This is a manual, machine-dependent run, not a CI gate. State lives in $RATATOSKR_SMOKE_DIR (default $HOME/.cache/ratatoskr-smoke/XR-021-r6); evidence summaries go to the gitignored evidence/XR-021-r6/<flow>/. See README.md.
# RATATOSKR_SMOKE_REF=origin/main runs the flows against that ref of every repository a flow uses (exported with git archive into the state directory) instead of the commits the workspace pins; the pinned submodules are never touched.

set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=lib/assert.sh
source "$HERE/lib/assert.sh"
# shellcheck source=lib/build.sh
source "$HERE/lib/build.sh"
# shellcheck source=lib/postgres.sh
source "$HERE/lib/postgres.sh"
# shellcheck source=lib/nats.sh
source "$HERE/lib/nats.sh"
# shellcheck source=lib/services.sh
source "$HERE/lib/services.sh"

FLOW_FILES=("$HERE"/flows/f?-*.sh)
MIN_FREE_GIB=12

flow_file() {
  local file
  for file in "${FLOW_FILES[@]}"; do
    [[ "$(basename "$file")" == "$1"-* ]] && { printf '%s' "$file"; return 0; }
  done
  return 1
}

# Loads a flow definition into the current shell (a flow file only defines variables and functions).
load_flow() {
  local file
  file=$(flow_file "$1") || { printf 'unknown flow %s; try --list\n' "$1" >&2; return 2; }
  FLOW_BINARIES=() FLOW_HONESTY=() FLOW_KEEP_DATA=0 FLOW_NEEDS_KEPT='' FLOW_NEEDS='' EDGE_SWEEP_SECONDS=''
  # shellcheck disable=SC1090
  source "$file"
}

list_flows() {
  local file id
  printf 'Native smoke flows (a manual run; state under %s)\n' "$S"
  printf 'Common prerequisites: nats-server 2.10 or later, initdb, pg_ctl, psql and pg_config with the pgvector files, cargo, a python that serves HTTP and imports cryptography (chosen by lib/common.sh::py_select), jq, curl, lsof, rg, git, at least %s GiB free, and every port a flow lists free (run.sh --dry-run FLOW checks all of it).\n' "$MIN_FREE_GIB"
  for file in "${FLOW_FILES[@]}"; do
    id=$(basename "$file" | cut -d- -f1)
    (
      load_flow "$id" || exit 1
      printf '\n%s  %s\n' "$(tr '[:lower:]' '[:upper:]' <<<"$FLOW_ID")" "$FLOW_TITLE"
      printf '  binaries:      %s\n' "${FLOW_BINARIES[*]:-none beyond the shared Edge build}"
      printf '  ports free:    %s\n' "$FLOW_PORTS"
      printf '  needs:         %s\n' "${FLOW_NEEDS:-nothing beyond the common prerequisites}"
      printf '  evidence:      %s\n' "$FLOW_EVIDENCE"
    )
  done
}

# Prints one MISSING line per missing prerequisite and returns 3 when there is one.
check_prerequisites() {
  local absent=0 tool version extension_dir lib_dir
  for tool in nats-server initdb pg_ctl psql pg_config cargo perl jq curl lsof rg shasum git; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'MISSING: command %s is not on PATH\n' "$tool"; absent=1; }
  done
  if command -v nats-server >/dev/null 2>&1; then
    version=$(nats-server --version 2>/dev/null | sed -E 's/.*v([0-9]+\.[0-9]+).*/\1/')
    awk -v v="$version" 'BEGIN { split(v, p, "."); exit !(p[1] > 2 || (p[1] == 2 && p[2] >= 10)) }' \
      || { printf 'MISSING: nats-server 2.10 or later (found %s)\n' "${version:-unknown}"; absent=1; }
  fi
  py_select || { printf 'MISSING: python with HTTP serving and cryptography (candidates tried: %s)\n' "$(py_candidates | tr '\n' ' ')"; absent=1; }
  if command -v pg_config >/dev/null 2>&1; then
    extension_dir=$(pg_config --sharedir)/extension
    lib_dir=$(pg_config --pkglibdir)
    [[ -f "$extension_dir/vector.control" ]] || { printf 'MISSING: pgvector control file %s/vector.control\n' "$extension_dir"; absent=1; }
    compgen -G "$lib_dir/vector.*" >/dev/null || { printf 'MISSING: pgvector library %s/vector.dylib or vector.so\n' "$lib_dir"; absent=1; }
  fi
  local free
  free=$(free_gib "$S")
  ((free >= MIN_FREE_GIB)) || { printf 'MISSING: %s GiB free on the volume of %s, need at least %s\n' "$free" "$S" "$MIN_FREE_GIB"; absent=1; }
  local busy
  busy=$(ports_busy $FLOW_PORTS) || { sed 's/^BUSY /MISSING: /' <<<"$busy"; absent=1; }
  ((absent == 0)) || return 3
  return 0
}

dry_run() {
  load_flow "$1" || return 2
  smoke_dir_guard
  if check_prerequisites; then
    printf 'dry-run ok: %s (%s)\n' "$FLOW_ID" "$FLOW_TITLE"
    return 0
  fi
  return 3
}

# Removes what earlier runs left in the state directory, and nothing else: only a directory that carries the marker this smoke writes.
prune() {
  smoke_dir_guard
  if [[ ! -d "$S" ]]; then
    printf 'nothing to prune: %s does not exist\n' "$S"
    return 0
  fi
  if [[ ! -f "$S/$SMOKE_MARKER" ]]; then
    printf 'refusing to prune %s: it does not carry the %s marker of this smoke\n' "$S" "$SMOKE_MARKER" >&2
    return 2
  fi
  stop_all
  pg_down
  find "$S" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  printf 'pruned %s\n' "$S"
}

# Data, keys, rendered configs and staging hold secrets and are removed at the end of a flow; logs and redacted evidence stay.
cleanup_flow() {
  stop_all
  pg_down
  if ((FLOW_KEEP_DATA == 0)); then
    local name
    for name in pg pgrun nats-js blobs staging nk keys conf render fx pki nats.conf legb; do
      [[ -f "$S/$SMOKE_MARKER" ]] && rm -rf -- "${S:?}/$name"
    done
  else
    printf 'kept the databases, blobs and keys of %s for the next flow\n' "$FLOW_ID"
  fi
}

run_flow() {
  local repo
  load_flow "$1" || return 2
  smoke_dir_guard
  if [[ -n "${FLOW_NEEDS_KEPT:-}" && ! -d "$S/pg" ]]; then
    printf 'flow %s needs the state that %s keeps; run %s first\n' "$FLOW_ID" "$FLOW_NEEDS_KEPT" "$FLOW_NEEDS_KEPT" >&2
    return 3
  fi
  check_prerequisites || return 3
  lock_acquire
  trap 'cleanup_flow; lock_release' EXIT
  smoke_init_dirs
  # Logs belong to one flow: a leg that counts lines in a service log must not see the lines of an earlier flow (build logs stay).
  find "$S/logs" -maxdepth 1 -type f ! -name 'build-*' ! -name 'built-commits.txt' -delete
  # Control files (fake-fail, fake-status, github-description, deleted.list, probe markers) belong to one flow as well: a file an earlier flow left behind would change a fake's first answer. No process is running here (the lock is held and every flow stops its own), so no pid file is lost.
  find "$S/run" -maxdepth 1 -type f -delete
  ev_init "$FLOW_ID"
  : >"$S/conf/deviations.txt"
  # shellcheck disable=SC2086
  src_prepare $FLOW_REPOS
  printf 'python: %s (%s)\n' "$PY" "$("$PY" -V 2>&1)" >>"$S/conf/deviations.txt"
  source_note >>"$S/conf/deviations.txt"
  PASS_COUNT=0 FAIL_COUNT=0
  printf '== %s  %s\n' "$FLOW_ID" "$FLOW_TITLE"
  build_flow_binaries "${FLOW_BINARIES[@]}" || { info "build failed: the flow did not run"; FLOW_HONESTY+=("NOT RUN: a build failed"); FAIL_COUNT=1; }
  if ((FAIL_COUNT == 0)); then
    flow_run
    # After EVERY flow: no ACL violation in the NATS log. The deliberate probes of F0 are the only whitelisted hits (lib/assert.sh::nats_violation_count excludes their window).
    assert nats_log_has_no_acl_violations '[ "$(nats_violation_count)" = 0 ]' "violations: $(nats_violation_count); $(rg 'Publish Violation|Subscription Violation|Authorization Violation' "$S/logs/nats.log" 2>/dev/null | head -3 | cut -c1-200 | tr '\n' '|')"
  fi
  for repo in $FLOW_REPOS; do assert_repo_clean "$repo"; done
  result_write "$FLOW_ID"
  cp "$S/logs/build-notes.txt" "$S/logs/built-commits.txt" "$EV/" 2>/dev/null
  cleanup_flow
  trap - EXIT
  lock_release
  ((FAIL_COUNT == 0))
}

main() {
  case "${1:-}" in
    --list) list_flows ;;
    --dry-run) [[ -n "${2:-}" ]] || { echo "usage: run.sh --dry-run FLOW" >&2; return 2; }; dry_run "$2" ;;
    --prune) prune ;;
    -h|--help|"") sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
    *)
      local flow status=0
      for flow in "$@"; do
        run_flow "$flow" || status=$?
      done
      return "$status"
      ;;
  esac
}

main "$@"
