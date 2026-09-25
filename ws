#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$script_dir/harness"
RATATOSKR_WORKSPACE_ROOT="$script_dir" exec cargo run --quiet -p workspace-cli -- "$@"
