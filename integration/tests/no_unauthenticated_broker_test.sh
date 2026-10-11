#!/usr/bin/env bash
# Contract test (XR-021 CONTRACTS R3-18): no integration profile starts a NATS broker without the configuration rendered from Platform's deployed ACL. A broker started with command-line flags only accepts any client, so a profile that does it proves nothing about the production ACL.
#
# The scan reads every integration/compose/*.yaml. A service whose image is a NATS image must start from a configuration file (`command: [-c, <path>.conf]`, never `--jetstream` flags), and the runner of the profile (integration/run-<name>.sh for compose/<name>.yaml) must call render_nats_conf, which is the only thing that writes that file. A NATS image that runs `sleep` (the shared network namespace holder) is not a broker. The mount of each profile is asserted by its own contract test. It does not start Docker. Limitation: it is a text scan, so a broker that a compose file builds from a Dockerfile of another name, or that an override file adds, is not seen.
set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Prints one line per problem of a compose file and its runner; nothing when the file is clean.
broker_problems() {
  local compose_file=$1 runner=$2
  local services service
  # Names of the services whose image is a NATS image.
  services=$(awk '
    /^services:/ { in_services = 1; next }
    /^[^ #]/ { in_services = 0 }
    in_services && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { name = $1; sub(/:$/, "", name) }
    in_services && /^    image:[[:space:]]*nats[:@]/ { print name }
  ' "$compose_file")
  [[ -z "$services" ]] && return 0
  for service in $services; do
    local block
    block=$(awk -v wanted="$service" '
      /^services:/ { in_services = 1; next }
      /^[^ #]/ { in_services = 0 }
      in_services && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { name = $1; sub(/:$/, "", name) }
      in_services && name == wanted { print }
    ' "$compose_file")
    # The pause container of a shared network namespace is also a NATS image; it runs `sleep`.
    if rg --quiet --fixed-strings 'sleep' <<<"$block"; then
      continue
    fi
    rg --quiet -e 'command: \[(-c|--config), [^]]+\.conf\]' <<<"$block" \
      || printf '%s: service %s does not start from a rendered configuration file\n' "$compose_file" "$service"
    if rg --quiet -e '--jetstream|--store_dir|--http_port' <<<"$block"; then
      printf '%s: service %s starts with command-line flags and no authorization\n' "$compose_file" "$service"
    fi
  done
  [[ -f "$runner" ]] || { printf '%s: no runner %s\n' "$compose_file" "$runner"; return 0; }
  rg --quiet --fixed-strings 'render_nats_conf' "$runner" \
    || printf '%s: runner %s does not call render_nats_conf\n' "$compose_file" "$runner"
}

profiles=0
problems=
for compose_file in "$workspace_root"/integration/compose/*.yaml; do
  name=$(basename "$compose_file" .yaml)
  profiles=$((profiles + 1))
  found=$(broker_problems "$compose_file" "$workspace_root/integration/run-$name.sh")
  problems+=$found
  [[ -n "$found" ]] && problems+=$'\n'
done
((profiles >= 4)) || fail "expected at least four compose profiles, found $profiles"
[[ -z "${problems//$'\n'/}" ]] || { printf '%s' "$problems" >&2; fail "a profile starts an unauthenticated broker"; }

# The scan must be able to fail: a broker started with flags only is reported.
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
cat >"$scratch/broken.yaml" <<'YAML'
services:
  nats:
    image: nats:2-alpine
    command: [--jetstream, --store_dir=/data, --http_port=8222]
    volumes:
      - nats-data:/data
YAML
printf '#!/usr/bin/env bash\ntrue\n' >"$scratch/run-broken.sh"
broken=$(broker_problems "$scratch/broken.yaml" "$scratch/run-broken.sh")
for expected in 'does not start from a rendered configuration file' \
  'command-line flags and no authorization' 'does not call render_nats_conf'; do
  rg --quiet --fixed-strings "$expected" <<<"$broken" || fail "the scan did not report: $expected"
done

printf 'no unauthenticated broker contract: PASS (%s profiles)\n' "$profiles"
