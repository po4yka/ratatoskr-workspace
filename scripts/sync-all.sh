#!/usr/bin/env bash
# Fetch remote changes and switch to main in the workspace and every repo under repos/.
set -uo pipefail

cd "$(dirname "$0")/.."
failed=()

sync() {
  local repo=$1
  echo "==> $repo"
  if [[ -n "$(git -C "$repo" status --porcelain)" ]]; then
    echo "    skipped: uncommitted changes"
    failed+=("$repo (dirty)")
    return
  fi
  git -C "$repo" fetch --all --prune --tags &&
  git -C "$repo" checkout main &&
  git -C "$repo" pull --ff-only || failed+=("$repo")
}

sync .
while IFS= read -r gitdir; do sync "$(dirname "$gitdir")"; done \
  < <(find repos -maxdepth 3 -name .git | sort)

if ((${#failed[@]})); then
  printf '\nFAILED:\n'; printf '  %s\n' "${failed[@]}"; exit 1
fi
echo -e "\nAll repos on main and up to date."
