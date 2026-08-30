#!/usr/bin/env bash
set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
platform=${1:?usage: run-instagram-event-delivery.sh PLATFORM_WORKTREE INSTAGRAM_WORKTREE}
instagram=${2:?usage: run-instagram-event-delivery.sh PLATFORM_WORKTREE INSTAGRAM_WORKTREE}

platform_config="$platform/deploy/nats/ratatoskr.conf"
instagram_manifest="$instagram/Cargo.toml"
[[ -f "$platform_config" ]] || { printf 'missing %s\n' "$platform_config" >&2; exit 2; }
[[ -f "$instagram_manifest" ]] || { printf 'missing %s\n' "$instagram_manifest" >&2; exit 2; }

runtime_dir=$(mktemp -d "$workspace_root/.ig014-runtime.XXXXXX")
mkdir "$runtime_dir/docker-config"
printf '{}\n' >"$runtime_dir/docker-config/config.json"
export DOCKER_CONFIG="$runtime_dir/docker-config"
suffix=$(basename "$runtime_dir" | tr -cd 'a-zA-Z0-9')
nats_container="ratatoskr-ig014-nats-$suffix"
postgres_container="ratatoskr-ig014-postgres-$suffix"
nats_image='nats:2-alpine@sha256:d4ac35882ac65aff236cd65b9d3fa4d24332c681e1a85f94eedccd3cdd65b1da'
nats_box='natsio/nats-box@sha256:9d5f35d286c3dcfca18bb2339b51345f9f89b580b237ab16ddfe609bdca9c72d'

cleanup() {
  local result=$?
  trap - EXIT INT TERM
  docker rm --force "$nats_container" "$postgres_container" >/dev/null 2>&1 || true
  if [[ "$runtime_dir" == "$workspace_root"/.ig014-runtime.* ]]; then
    rm -rf -- "$runtime_dir"
  fi
  exit "$result"
}
trap cleanup EXIT INT TERM

generate_nkey() {
  local name=$1 pair seed public
  pair=$(docker run --rm "$nats_box" nk -gen user -pubout)
  seed=$(printf '%s\n' "$pair" | sed -n '1p')
  public=$(printf '%s\n' "$pair" | sed -n '2p')
  [[ "$seed" == SU* && "$public" == U* ]] || {
    printf 'could not generate the %s NKey pair\n' "$name" >&2
    exit 1
  }
  printf '%s\n' "$seed" >"$runtime_dir/$name.seed"
  chmod 0600 "$runtime_dir/$name.seed"
  printf '%s\n' "$public"
}

edge_public=$(generate_nkey edge)
telegram_public=$(generate_nkey telegram)
x_public=$(generate_nkey x)
instagram_public=$(generate_nkey instagram)
threads_public=$(generate_nkey threads)

sed \
  -e "s/UREPLACE_ME_WITH_THE_PUBLIC_NKEY_OF_RATATOSKR_EDGE_XXXXXXXXXX/$edge_public/g" \
  -e "s/UREPLACE_ME_WITH_THE_PUBLIC_NKEY_OF_RATATOSKR_TELEGRAM_XXXX/$telegram_public/g" \
  -e "s/UREPLACE_ME_WITH_THE_PUBLIC_NKEY_OF_RATATOSKR_X_XXXXXXXXXXXXX/$x_public/g" \
  -e "s/UREPLACE_ME_WITH_THE_PUBLIC_NKEY_OF_RATATOSKR_INSTAGRAM_XXXXX/$instagram_public/g" \
  -e "s/UREPLACE_ME_WITH_THE_PUBLIC_NKEY_OF_RATATOSKR_THREADS_XXXXXXX/$threads_public/g" \
  -e 's/host: 127\.0\.0\.1/host: 0.0.0.0/' \
  -e 's/http: 127\.0\.0\.1:8222/http: 0.0.0.0:8222/' \
  -e 's#store_dir: /mnt/nvme/ratatoskr/nats#store_dir: /data#' \
  "$platform_config" >"$runtime_dir/nats.conf"
chmod 0600 "$runtime_dir/nats.conf"

docker run --detach --name "$nats_container" \
  --publish 127.0.0.1::4222 \
  --volume "$runtime_dir:/run/ig014:ro" \
  "$nats_image" -c /run/ig014/nats.conf >/dev/null
docker run --detach --name "$postgres_container" \
  --env POSTGRES_USER=instagram \
  --env POSTGRES_PASSWORD=instagram \
  --env POSTGRES_DB=instagram \
  --publish 127.0.0.1::5432 \
  postgres:17 >/dev/null

nats_ready=false
for _ in $(seq 1 100); do
  if docker logs "$nats_container" 2>&1 | rg --quiet 'Server is ready'; then
    nats_ready=true
    break
  fi
  sleep 0.1
done
[[ "$nats_ready" == true ]] || {
  printf 'actual Platform NATS policy fixture did not become ready\n' >&2
  exit 1
}
postgres_ready=false
for _ in $(seq 1 100); do
  if docker exec "$postgres_container" pg_isready -U instagram -d instagram >/dev/null 2>&1; then
    postgres_ready=true
    break
  fi
  sleep 0.1
done
[[ "$postgres_ready" == true ]] || {
  printf 'PostgreSQL fixture did not become ready\n' >&2
  exit 1
}

nats_port=$(docker port "$nats_container" 4222/tcp | sed -n '1s/.*://p')
postgres_port=$(docker port "$postgres_container" 5432/tcp | sed -n '1s/.*://p')
[[ "$nats_port" =~ ^[0-9]+$ && "$postgres_port" =~ ^[0-9]+$ ]] || {
  printf 'fixture port discovery failed\n' >&2
  exit 1
}

export INSTAGRAM_ARCHIVE_TEST_DATABASE_URL="postgres://instagram:instagram@127.0.0.1:$postgres_port/instagram"
export INSTAGRAM_ARCHIVE_TEST_NATS_URL="nats://127.0.0.1:$nats_port"
export INSTAGRAM_ARCHIVE_TEST_NATS_NKEY_SEED_PATH="$runtime_dir/instagram.seed"
export INSTAGRAM_ARCHIVE_TEST_NATS_ADMIN_NKEY_SEED_PATH="$runtime_dir/edge.seed"

(
  cd "$instagram"
  build-gate -- cargo test --locked \
    -p ratatoskr-instagram-archive-service --test nats_outbox_delivery \
    all_three_fact_types_use_exact_subjects -- --exact --nocapture
  build-gate -- cargo test --locked \
    -p ratatoskr-instagram-archive-service --test nats_outbox_delivery \
    actual_platform_policy_denies_foreign_publish_and_direct_subscription \
    -- --ignored --exact --nocapture
)

printf 'Producer-to-stream acknowledgement ordering: verified\n'
printf 'Foreign publish and direct subscription denial: verified\n'
printf 'Knowledge consumption: unverified\n'
printf 'Provider behavior: unverified\n'
printf 'Live deployment: unverified\n'
printf 'Human alert receipt: unverified\n'
