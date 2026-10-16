#!/usr/bin/env bash
# Run the real services on a private network; only device/Sync and Knowledge input are fixtures.
set -euo pipefail
umask 077
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
namespace=${RATATOSKR_TASK_NAMESPACE:?set a unique task namespace}
[[ "$namespace" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]] || { printf 'Invalid namespace\n' >&2; exit 2; }
project="ratatoskr-$namespace"
profile="$root/integration/compose/site-owner-editing.yaml"
existing=$(docker ps --all --filter "label=com.docker.compose.project=$project" --quiet)
[[ -z "$existing" ]] || { printf "Project already exists; choose another namespace\n" >&2; exit 2; }
for repo in PLATFORM SITES NOTES KNOWLEDGE; do
  context_var=RATATOSKR_${repo}_CONTEXT
  revision_var=RATATOSKR_${repo}_REVISION
  context=${!context_var:?set checkout context}
  revision=${!revision_var:?set exact revision}
  [[ $(git -C "$context" rev-parse HEAD) == "$revision" ]] || { printf '%s revision mismatch\n' "$repo" >&2; exit 2; }
  git -C "$context" merge-base --is-ancestor "$revision" refs/remotes/origin/main || { printf "%s revision is not in origin/main\n" "$repo" >&2; exit 2; }
  [[ -z $(git -C "$context" status --porcelain --untracked-files=no) ]] || { printf '%s source is dirty\n' "$repo" >&2; exit 2; }
done
compose() { docker compose --project-name "$project" --file "$profile" "$@"; }
runtime=$(mktemp -d "${TMPDIR:-/tmp}/ratatoskr-$namespace.XXXXXX")
export RATATOSKR_SITE027_RUNTIME_DIR=$runtime
export RATATOSKR_EVIDENCE_DIR=${RATATOSKR_EVIDENCE_DIR:-"$root/evidence/$namespace"}
mkdir -p "$RATATOSKR_EVIDENCE_DIR"
# A failed rerun must not retain an earlier success or a build deviation from another run.
rm -f -- "$RATATOSKR_EVIDENCE_DIR/result.json" "$RATATOSKR_EVIDENCE_DIR/.scenario-result.json" "$RATATOSKR_EVIDENCE_DIR/build-deviations.txt"
# shellcheck source=lib/nats-conf.sh
source "$root/integration/lib/nats-conf.sh"
render_nats_conf "$RATATOSKR_PLATFORM_CONTEXT/deploy/nats/ratatoskr.conf" "$runtime/nats" EDGE NOTES SITES
# Some developer networks refuse Debian's HTTP mirror. Use HTTPS without weakening validation.
# The default builds the child's exact Dockerfile. The explicit override changes only package
# transport; the runtime trust bundle comes from the builder's verified Debian CA package.
if [[ ${RATATOSKR_SITE027_APT_HTTPS:-0} == 1 ]]; then
  for repo in PLATFORM SITES KNOWLEDGE; do
    context_var=RATATOSKR_${repo}_CONTEXT
    dockerfile_var=RATATOSKR_SITE027_${repo}_DOCKERFILE
    python3 - "${!context_var}/Dockerfile" "$runtime/$repo.Dockerfile" <<'PYTHON'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
source = source.replace('RUN apt-get update', 'RUN sed -i s,http://deb.debian.org,https://deb.debian.org,g /etc/apt/sources.list.d/debian.sources && apt-get update')
source = source.replace('cargo build --release', 'RUSTUP_TOOLCHAIN=1.97.0 cargo build --release')
lines = source.splitlines()
result = []
for line in lines:
    result.append(line)
    if line.startswith('FROM debian:'):
        result.append('COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt')
Path(sys.argv[2]).write_text('\n'.join(result)+'\n')
PYTHON
    export "$dockerfile_var=$runtime/$repo.Dockerfile"
  done
  printf 'Build deviation: HTTPS Debian mirror; runtime CA trust copied from builder; installed Rust1.97.0 selected without optional rustup components.\n' > "$RATATOSKR_EVIDENCE_DIR/build-deviations.txt"
fi
compose config --quiet
[[ -z $(compose ps --all --quiet) ]] || { printf 'Project already exists; choose another namespace\n' >&2; rm -rf -- "$runtime"; exit 2; }
cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  compose logs --no-color > "$RATATOSKR_EVIDENCE_DIR/compose.log" 2>&1
  compose ps --all > "$RATATOSKR_EVIDENCE_DIR/compose-ps.txt" 2>&1
  compose down --volumes --remove-orphans > "$RATATOSKR_EVIDENCE_DIR/teardown.log" 2>&1
  teardown_status=$?
  if ((teardown_status != 0)); then status=1; fi
  rm -rf -- "$runtime"
  if ((status == 0)) && [[ -f "$RATATOSKR_EVIDENCE_DIR/.scenario-result.json" ]]; then
    mv -- "$RATATOSKR_EVIDENCE_DIR/.scenario-result.json" "$RATATOSKR_EVIDENCE_DIR/result.json" || status=1
  fi
  if ((status != 0)); then
    rm -f -- "$RATATOSKR_EVIDENCE_DIR/result.json" "$RATATOSKR_EVIDENCE_DIR/.scenario-result.json"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ ${1:-} == --validate ]]; then printf 'site owner editing Compose validation: PASS\n'; exit 0; fi
for service in notes platform sites knowledge; do
  if [[ ${RATATOSKR_SITE027_APT_HTTPS:-0} == 1 && "$service" != notes ]]; then
    upper=$(printf '%s' "$service" | tr '[:lower:]' '[:upper:]')
    dockerfile_var=RATATOSKR_SITE027_${upper}_DOCKERFILE
    context_var=RATATOSKR_${upper}_CONTEXT
    revision_var=RATATOSKR_${upper}_REVISION
    docker buildx build --load --file "${!dockerfile_var}" --tag "$project-$service" \
      --build-arg "RATATOSKR_GIT_SHA=${!revision_var}" "${!context_var}"
  else
    docker compose --progress plain --project-name "$project" --file "$profile" build "$service"
  fi
done
compose up --detach
port=$(compose port network 8080 | tail -1 | awk -F: '{print $NF}')
export RATATOSKR_SITE027_URL="http://127.0.0.1:$port"
# The fixture asserts consent_sign_in, edit_conflicted, edit_completed,
# manual_release_retains_old_text, release_published_public_sse, and
# knowledge_search_holds_only_owner_documents. It also checks notes-write-back acknowledgements.
python3 "$root/integration/fixtures/site-owner-editing.py" "$project" "$profile"
for repo in PLATFORM SITES NOTES KNOWLEDGE; do
  context_var=RATATOSKR_${repo}_CONTEXT
  revision_var=RATATOSKR_${repo}_REVISION
  [[ $(git -C "${!context_var}" rev-parse HEAD) == "${!revision_var}" ]] || { printf '%s changed during the run\n' "$repo" >&2; exit 2; }
  [[ -z $(git -C "${!context_var}" status --porcelain --untracked-files=no) ]] || { printf '%s source changed during the run\n' "$repo" >&2; exit 2; }
done
printf 'site owner editing and notes write-back runtime: PASS\n'
