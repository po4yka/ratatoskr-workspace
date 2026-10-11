#!/usr/bin/env bash
# Renders the NATS configuration every integration profile runs under from the one file Platform
# deploys, `deploy/nats/ratatoskr.conf`, so a profile can never hold a hand-made, looser ACL
# (XR-021 CONTRACTS R2-12). Source this file; it defines functions and runs nothing.
#
#   render_nats_conf <platform_conf> <outdir> <IDENTITY>...
#   append_nats_test_user <outdir> <name> <publish_subject>...
#
# render_nats_conf replaces each UREPLACE_ME_WITH_THE_PUBLIC_NKEY_OF_RATATOSKR_<IDENTITY>_X+
# placeholder with a freshly generated public user nkey and writes <outdir>/ratatoskr.conf. For each
# requested IDENTITY the seed is kept as <outdir>/<identity lower case>.nkey (mode 0600) beside
# <identity>.public. An identity that is not requested still gets a key, because the deployed file
# lists all thirteen stanzas, but its seed is discarded: nobody can authenticate as it.
#
# Only two lines of the deployed file are ever edited, both outside the stanzas:
#   NATS_CONF_STORE_DIR  jetstream.store_dir, default /data (the deployed path is a host NVMe mount)
#   NATS_CONF_HOST       host, left as deployed (0.0.0.0, which a container needs) when unset
# max_file_store stays at the deployed 8GB. It is a ceiling, not an allocation, and a smaller one
# stops Edge at startup because the two streams reserve 1 GiB each beside the KV bucket.
#
# append_nats_test_user adds one extra user stanza after rendering, for a test-only publisher such
# as the TG-010 driver. It never edits a service identity.
#
# Needs: go (the nkeys module is fetched once), sed, awk, mktemp.

_nats_conf_fixture_dir() {
  local here
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  printf '%s/../fixtures' "$here"
}

# Writes <name>.nkey and <name>.public for every lower case name into <outdir>.
_nats_conf_generate_keys() {
  local outdir=$1
  shift
  local generator
  generator=$(mktemp -d)
  cp "$(_nats_conf_fixture_dir)/nkeys.go" "$generator/main.go"
  cat >"$generator/go.mod" <<'EOF'
module ratatoskr.local/nkeys

go 1.25

require github.com/nats-io/nkeys v0.4.10
EOF
  (
    cd "$generator"
    GOWORK=off go mod tidy >/dev/null 2>&1
    GOWORK=off go run . "$outdir" "$@"
  ) || {
    rm -rf -- "$generator"
    printf 'could not generate NATS nkeys\n' >&2
    return 1
  }
  rm -rf -- "$generator"
}

render_nats_conf() {
  local platform_conf=${1:?platform_conf} outdir=${2:?outdir}
  shift 2
  local prefix=UREPLACE_ME_WITH_THE_PUBLIC_NKEY_OF_RATATOSKR_
  local names requested name lower found public known
  [[ -f "$platform_conf" ]] || { printf 'missing %s\n' "$platform_conf" >&2; return 1; }
  (($# > 0)) || { printf 'render_nats_conf needs at least one identity\n' >&2; return 1; }

  # Every identity the deployed file declares, from its placeholders.
  names=$(sed -nE "s/^[[:space:]]*nkey:[[:space:]]*${prefix}([A-Z_]+)_X+[[:space:]]*\$/\\1/p" "$platform_conf")
  [[ -n "$names" ]] || { printf 'no nkey placeholder in %s\n' "$platform_conf" >&2; return 1; }

  requested=" $* "
  for name in "$@"; do
    found=0
    while IFS= read -r known; do
      [[ "$known" == "$name" ]] && found=1
    done <<<"$names"
    ((found == 1)) || { printf 'unknown identity %s; the deployed file declares: %s\n' "$name" "$(tr '\n' ' ' <<<"$names")" >&2; return 1; }
  done

  (umask 077 && mkdir -p "$outdir")
  local lowers=()
  while IFS= read -r name; do
    lowers+=("$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')")
  done <<<"$names"
  (umask 077 && _nats_conf_generate_keys "$outdir" "${lowers[@]}") || return 1

  local rendered="$outdir/ratatoskr.conf"
  (umask 077 && cp "$platform_conf" "$rendered")
  while IFS= read -r name; do
    lower=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
    public=$(tr -d '\r\n' <"$outdir/$lower.public")
    sed -E "s/${prefix}${name}_X+/${public}/" "$rendered" >"$rendered.next"
    mv "$rendered.next" "$rendered"
    chmod 0600 "$rendered"
    if [[ "$requested" != *" $name "* ]]; then
      rm -f -- "$outdir/$lower.nkey" "$outdir/$lower.public"
    fi
  done <<<"$names"

  local store_dir=${NATS_CONF_STORE_DIR:-/data}
  sed -E "s|^([[:space:]]*store_dir:).*\$|\\1 ${store_dir}|" "$rendered" >"$rendered.next"
  mv "$rendered.next" "$rendered"
  if [[ -n ${NATS_CONF_HOST:-} ]]; then
    sed -E "s|^(host:).*\$|\\1 ${NATS_CONF_HOST}|" "$rendered" >"$rendered.next"
    mv "$rendered.next" "$rendered"
  fi
  chmod 0600 "$rendered"
}

append_nats_test_user() {
  local outdir=${1:?outdir} name=${2:?name}
  shift 2
  (($# > 0)) || { printf 'append_nats_test_user needs a publish subject\n' >&2; return 1; }
  local rendered="$outdir/ratatoskr.conf" public subjects stanza
  [[ -f "$rendered" ]] || { printf 'render_nats_conf has not run in %s\n' "$outdir" >&2; return 1; }
  (umask 077 && _nats_conf_generate_keys "$outdir" "$name") || return 1
  public=$(tr -d '\r\n' <"$outdir/$name.public")
  subjects=
  for subject in "$@"; do
    subjects+="\"${subject}\", "
  done
  subjects=${subjects%, }
  stanza=$(
    cat <<EOF
        {
            nkey: ${public}
            permissions: {
                publish: { allow: [${subjects}] }
                subscribe: { allow: ["_INBOX.>"] }
            }
        }
EOF
  )
  # Insert before the line that closes the users array: the last line that is only `]`.
  STANZA="$stanza" awk '
    { lines[NR] = $0 }
    $0 ~ /^[[:space:]]*\][[:space:]]*$/ { closing = NR }
    END {
      for (i = 1; i <= NR; i++) {
        if (i == closing) print ENVIRON["STANZA"]
        print lines[i]
      }
    }
  ' "$rendered" >"$rendered.next"
  mv "$rendered.next" "$rendered"
  chmod 0600 "$rendered"
}
