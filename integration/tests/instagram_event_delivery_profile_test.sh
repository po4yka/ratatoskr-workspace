#!/usr/bin/env bash
set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
platform=${1:?usage: instagram_event_delivery_profile_test.sh PLATFORM_WORKTREE INSTAGRAM_WORKTREE}
instagram=${2:?usage: instagram_event_delivery_profile_test.sh PLATFORM_WORKTREE INSTAGRAM_WORKTREE}
runner="$workspace_root/integration/run-instagram-event-delivery.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -d "$platform/.git" || -f "$platform/.git" ]] || fail "Platform path is not a Git worktree"
[[ -d "$instagram/.git" || -f "$instagram/.git" ]] || fail "Instagram path is not a Git worktree"
[[ -x "$runner" ]] || fail "missing executable IG-014 runner"

for token in \
  deploy/nats/ratatoskr.conf \
  INSTAGRAM_ARCHIVE_TEST_NATS_NKEY_SEED_PATH \
  INSTAGRAM_ARCHIVE_TEST_NATS_ADMIN_NKEY_SEED_PATH \
  all_three_fact_types_use_exact_subjects \
  actual_platform_policy_denies_foreign_publish_and_direct_subscription \
  'Knowledge consumption: unverified' \
  'Live deployment: unverified'
do
  rg --quiet --fixed-strings -- "$token" "$runner" || fail "runner omits $token"
done

"$runner" "$platform" "$instagram"
printf 'Instagram event-delivery profile: PASS\n'
