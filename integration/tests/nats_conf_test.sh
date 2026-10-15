#!/usr/bin/env bash
# Contract test for integration/lib/nats-conf.sh: every profile runs under the NATS authorization
# that Platform deploys (XR-021 CONTRACTS R2-12), so the library must key that file and change
# nothing else. Needs nats-server, go (with the nkeys module reachable once) and the pinned
# Platform checkout; it does not need Docker.
set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
library="$workspace_root/integration/lib/nats-conf.sh"
deployed="$workspace_root/repos/platform/deploy/nats/ratatoskr.conf"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
[[ -f "$library" ]] || fail "missing $library"
[[ -f "$deployed" ]] || fail "the pinned Platform checkout has no deploy/nats/ratatoskr.conf"
for command in nats-server go; do
  command -v "$command" >/dev/null || fail "required command is unavailable: $command"
done

# shellcheck source=../lib/nats-conf.sh disable=SC1091
source "$library"

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT

mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

# The ACL as a reviewer reads it: no comments, no blank lines, no indentation, the nkey token and
# the one documented override neutralised.
normalise() {
  sed -E \
    -e 's/#.*$//' \
    -e 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    -e 's/(nkey:[[:space:]]*)[A-Z0-9_]+/\1NKEY/' \
    -e '/^store_dir:/d; /^[[:space:]]*store_dir:/d' \
    -e '/^host:/d' \
    "$1" | sed -E '/^$/d'
}

out="$scratch/three"
render_nats_conf "$deployed" "$out" EDGE CHATGPT CLAUDE

conf="$out/ratatoskr.conf"
[[ -f "$conf" ]] || fail "render_nats_conf did not write ratatoskr.conf"
if rg --quiet 'UREPLACE_ME' "$conf"; then fail "a placeholder remains in the rendered file"; fi
nats-server -t -c "$conf" >"$scratch/validate.txt" 2>&1 || {
  cat "$scratch/validate.txt" >&2
  fail "nats-server -t rejects the rendered file"
}

for name in edge chatgpt claude; do
  [[ -f "$out/$name.nkey" ]] || fail "missing seed for $name"
  [[ "$(mode_of "$out/$name.nkey")" == 600 ]] || fail "seed for $name is not mode 0600"
  public=$(tr -d '\r\n' <"$out/$name.public")
  [[ "$public" == U* ]] || fail "public key for $name is not a user nkey"
  [[ "$(rg --count --fixed-strings "nkey: $public" "$conf")" == 1 ]] ||
    fail "the public key of $name is not in exactly one stanza"
done

for name in telegram x instagram threads extractor extractor_browser_worker knowledge github vault channel_digests notes sites; do
  [[ ! -e "$out/$name.nkey" ]] || fail "a throwaway identity ($name) left a seed behind"
done

tokens=$(rg --only-matching --no-filename '^[[:space:]]*nkey:[[:space:]]*U[A-Z0-9]+' "$conf" | sort -u | wc -l | tr -d ' ')
[[ "$tokens" == 15 ]] || fail "expected 15 distinct nkeys, found $tokens"

# Only the store_dir override differs from the deployed file. Everything else, every allow list
# included, is unchanged.
diff <(normalise "$deployed") <(normalise "$conf") >"$scratch/acl.diff" ||
  { cat "$scratch/acl.diff" >&2; fail "the rendered ACL differs from the deployed one"; }

[[ "$(rg --count '^[[:space:]]*store_dir:[[:space:]]*/data$' "$conf")" == 1 ]] ||
  fail "the default store_dir override is not /data"

# The documented overrides are the only edits outside the stanzas.
NATS_CONF_STORE_DIR=/var/lib/nats NATS_CONF_HOST=127.0.0.1 \
  render_nats_conf "$deployed" "$scratch/overrides" EDGE
rg --quiet '^[[:space:]]*store_dir:[[:space:]]*/var/lib/nats$' "$scratch/overrides/ratatoskr.conf" ||
  fail "NATS_CONF_STORE_DIR is ignored"
rg --quiet '^host:[[:space:]]*127\.0\.0\.1$' "$scratch/overrides/ratatoskr.conf" ||
  fail "NATS_CONF_HOST is ignored"
rg --quiet '^[[:space:]]+max_file_store:[[:space:]]*8GB$' "$scratch/overrides/ratatoskr.conf" ||
  fail "max_file_store must stay at the deployed value: a smaller ceiling than the two stream reservations stops Edge at startup"
rg --quiet '^max_payload:[[:space:]]*8MB$' "$scratch/overrides/ratatoskr.conf" ||
  fail "the deployed max_payload of 8MB did not survive rendering"
diff <(normalise "$deployed") <(normalise "$scratch/overrides/ratatoskr.conf") >"$scratch/overrides.diff" ||
  { cat "$scratch/overrides.diff" >&2; fail "an override changed more than host and store_dir"; }

# An unknown identity is an error, not a silent no-op.
if render_nats_conf "$deployed" "$scratch/unknown" NOSUCH >/dev/null 2>&1; then
  fail "an unknown identity was accepted"
fi

# A test-only publisher is appended as a new stanza and never edits a service identity.
cp "$conf" "$scratch/before-append.conf"
append_nats_test_user "$out" driver "evt.platform.operation.reported.v1" "evt.platform.notification.raised.v1"
nats-server -t -c "$conf" >"$scratch/validate-appended.txt" 2>&1 || {
  cat "$scratch/validate-appended.txt" >&2
  fail "nats-server -t rejects the file after the driver stanza was appended"
}
[[ -f "$out/driver.nkey" && "$(mode_of "$out/driver.nkey")" == 600 ]] || fail "driver seed missing or not 0600"
driver_public=$(tr -d '\r\n' <"$out/driver.public")
[[ "$(rg --count --fixed-strings "nkey: $driver_public" "$conf")" == 1 ]] || fail "driver stanza missing"
rg --quiet --fixed-strings '"evt.platform.notification.raised.v1"' "$conf" || fail "driver subject missing"
if diff "$scratch/before-append.conf" "$conf" | rg --quiet '^<'; then
  fail "appending the driver stanza removed or changed a line of a service identity"
fi

printf 'NATS configuration rendering contract: PASS\n'
