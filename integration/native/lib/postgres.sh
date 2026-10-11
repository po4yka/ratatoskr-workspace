#!/usr/bin/env bash
# shellcheck disable=SC2034
# PostgreSQL for the native smoke: a private cluster under $S on 127.0.0.1:54329, provisioned only with the checked-in files of the repositories, in the order Platform's deploy/README.md documents (R3-11). Source after lib/common.sh.
#
# 1. 01-database-and-roles.sql  2. the first Edge start (it applies schema.sql)  3. 02-grants.sql  4. each service's deploy/postgres/role.sql before that service's first start. A role file that does not run as written is a defect to report, never something to patch here.

pg_up() {
  if [[ ! -d "$S/pg" ]]; then
    initdb -D "$S/pg" --auth-local=trust --auth-host=scram-sha-256 -U postgres --locale-provider=icu --icu-locale=und-x-icu -E UTF8 >"$S/logs/initdb.log" 2>&1 || return 1
  fi
  pg_ctl -D "$S/pg" -l "$S/logs/pg.log" -o "-p $PG_PORT -k $S/pgrun -c listen_addresses=127.0.0.1" -w start >/dev/null || return 1
  psql -X -v ON_ERROR_STOP=1 -q -d postgres -f "$(repo_dir platform)/deploy/postgres/01-database-and-roles.sql" >"$EV/provision-01.txt" 2>&1
  note "postgres: 01-database-and-roles.sql rc=$?"
}

# Starts the private cluster again (flow F6 stops it on purpose for 20 seconds, and resumes a kept state).
pg_start() {
  pg_ctl -D "$S/pg" -l "$S/logs/pg.log" -o "-p $PG_PORT -k $S/pgrun -c listen_addresses=127.0.0.1" -w start >/dev/null
}

pg_down() {
  [[ -d "$S/pg" ]] && pg_ctl -D "$S/pg" -m fast -w stop >/dev/null 2>&1
  return 0
}

# Runs the grants file after Edge applied schema.sql.
pg_grants() {
  psql -X -v ON_ERROR_STOP=1 -q -d ratatoskr -f "$(repo_dir platform)/deploy/postgres/02-grants.sql" >"$EV/provision-02.txt" 2>&1
  note "postgres: 02-grants.sql rc=$?"
}

# The random password a role connects with, created once and printed.
pg_password() {
  local role=$1 file=$S/conf/pw.$1
  if [[ ! -f "$file" ]]; then
    (umask 077 && head -c 24 /dev/urandom | base64 | tr -d '/+=\n' >"$file")
  fi
  cat "$file"
}

# Sets the role's password to the value rendered into its URL (through stdin, so it never reaches a process list).
pg_set_password() {
  printf "alter role %s password '%s';\n" "$1" "$(pg_password "$1")" | psql -X -v ON_ERROR_STOP=1 -q -d postgres
}

# pg_role REPO_ID ROLE: runs the repository's own role file as written, then sets the password. Platform's roles come from 01-database-and-roles.sql and only get a password.
pg_role() {
  local repo=$1 role=$2 rc
  if [[ "$repo" != platform ]]; then
    psql -X -v ON_ERROR_STOP=1 -q -d postgres -f "$(repo_dir "$repo")/deploy/postgres/role.sql" >"$EV/provision-role-$role.txt" 2>&1
    rc=$?
    note "postgres: $repo role.sql rc=$rc"
    ((rc == 0)) || return "$rc"
  fi
  pg_set_password "$role"
  psql -X -At -d postgres -c "select rolname, rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls from pg_roles where rolname='$role'" >>"$EV/roles.txt"
}

db_url() { printf 'postgres://%s:%s@127.0.0.1:%s/ratatoskr' "$1" "$(pg_password "$1")" "$PG_PORT"; }

# Applies the seed of the principals: two users, a browser session each, a Mini App session and a device with its device session for U1. Everything it inserts is SEEDED and labelled so in result.txt. The credentials are random per run; only their sha256 reaches the database.
seed_principals() {
  local tok1 tok2 tokm tokd dsecret
  tok1=$(secret browser1); tok2=$(secret browser2); tokm=$(secret miniapp); tokd=$(secret device)
  dsecret=$(sha256_text "device-secret-$U1")
  psql -X -v ON_ERROR_STOP=1 -q -d ratatoskr \
    -v h1="$(sha256_text "$tok1")" -v h2="$(sha256_text "$tok2")" -v hm="$(sha256_text "$tokm")" \
    -v hd="$(sha256_text "$tokd")" -v ds="$dsecret" -f "$NATIVE_ROOT/fixtures/platform-seed.sql" >"$EV/seed.txt" 2>&1
  note "postgres: seeded principals rc=$?"
}
