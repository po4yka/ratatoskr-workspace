#!/usr/bin/env bash
# shellcheck disable=SC2034
# Native release builds of the pinned submodules. Source after lib/common.sh.
#
# The shipped release profile is used as it is. CARGO_PROFILE_RELEASE_DEBUG=0 makes the sqlx proc-macro dylib fail to load on macOS 27 (mis-aligned LINKEDIT string pool), so it is never set. When a build prints that error anyway, it is retried ONCE with CARGO_PROFILE_RELEASE_STRIP=none and the retry is recorded in $S/logs/build-notes.txt.

BUILD_FLOOR_GIB=6

# build_bins REPO_ID BIN...: builds the named binaries of one repository, copies them to $S/bin and deletes the target directory. A binary that already exists in $S/bin for the same commit is not rebuilt (--prune removes them).
build_bins() {
  local repo=$1
  shift
  local unbuilt=() bin dir target log rc commit
  commit=$(repo_commit "$repo")
  for bin in "$@"; do
    [[ -x "$S/bin/$bin" && "$(cat "$S/bin/$bin.commit" 2>/dev/null)" == "$commit" ]] || unbuilt+=("$bin")
  done
  ((${#unbuilt[@]} > 0)) || { note "build: $repo already built ($*)"; return 0; }
  local free
  free=$(free_gib "$S")
  if ((free < BUILD_FLOOR_GIB)); then
    note "build: only ${free} GiB free on the volume of $S, below the ${BUILD_FLOOR_GIB} GiB floor; refusing to build $repo"
    return 9
  fi
  dir=$(repo_dir "$repo")
  target=$S/target/$repo
  log=$S/logs/build-$repo.log
  local args=()
  for bin in "${unbuilt[@]}"; do args+=(--bin "$bin"); done
  (cd "$dir" && CARGO_INCREMENTAL=0 CARGO_TARGET_DIR="$target" cargo build --release --locked --workspace "${args[@]}" >"$log" 2>&1)
  rc=$?
  if ((rc != 0)) && rg --quiet 'mis-aligned LINKEDIT string pool' "$log"; then
    printf '%s: retried %s with CARGO_PROFILE_RELEASE_STRIP=none after the LINKEDIT error\n' "$repo" "${unbuilt[*]}" >>"$S/logs/build-notes.txt"
    (cd "$dir" && CARGO_INCREMENTAL=0 CARGO_PROFILE_RELEASE_STRIP=none CARGO_TARGET_DIR="$target" cargo build --release --locked --workspace "${args[@]}" >>"$log" 2>&1)
    rc=$?
  fi
  if ((rc == 0)); then
    for bin in "${unbuilt[@]}"; do
      cp "$target/release/$bin" "$S/bin/$bin" || rc=1
      printf '%s' "$commit" >"$S/bin/$bin.commit"
    done
  fi
  printf '%s %s\n' "$repo" "$(repo_commit "$repo")" >>"$S/logs/built-commits.txt"
  [[ -d "$target" && -f "$S/$SMOKE_MARKER" ]] && rm -rf -- "$target"
  if ((rc == 0)); then note "build: $repo OK (${unbuilt[*]})"; else note "build: $repo FAILED (rc=$rc), see $log"; tail -20 "$log"; fi
  return "$rc"
}

# build_flow_binaries "repo:bin bin" "repo:bin"...: one build per repository.
build_flow_binaries() {
  local spec repo bins
  for spec in "$@"; do
    repo=${spec%%:*}
    bins=${spec#*:}
    # shellcheck disable=SC2086
    build_bins "$repo" $bins || return 1
  done
}

# The helper of flow F4 leg B (a FAULTED HOP, labelled in result.txt): a tiny crate that links the channel-digests library and commits a manifest of two synthetic posts for a run the real worker already accepted from the real bus. It is generated under $S from fixtures/legb/*.txt, never committed as a crate, and built against the library of the pinned checkout. The lock of the library seeds its Cargo.lock, so the build needs no network (--offline) and, because the helper itself is a new package in that lock, cannot use --locked.
build_legb() {
  [[ -x "$S/bin/legb" ]] && return 0
  local dir=$S/legb lib
  lib=$(repo_dir channel-digests)
  mkdir -p "$dir/src"
  sed "s#@CHANNEL_DIGESTS@#$lib#" "$NATIVE_ROOT/fixtures/legb/Cargo.toml.txt" >"$dir/Cargo.toml"
  cp "$NATIVE_ROOT/fixtures/legb/main.rs.txt" "$dir/src/main.rs"
  cp "$lib/rust-toolchain.toml" "$dir/rust-toolchain.toml"
  cp "$lib/Cargo.lock" "$dir/Cargo.lock"
  (cd "$dir" && CARGO_INCREMENTAL=0 CARGO_TARGET_DIR="$S/target/legb" cargo build --release --offline >"$S/logs/build-legb.log" 2>&1) || { tail -20 "$S/logs/build-legb.log"; return 1; }
  cp "$S/target/legb/release/legb" "$S/bin/legb" && rm -rf -- "$S/target/legb"
}
