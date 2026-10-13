# postgres-provisioning Specification

## Purpose
TBD - created by archiving change xr-021-fleet-round-3. Update Purpose after archive.

## Requirements

### Requirement: There is one database and each service has its own role

The fleet SHALL use one PostgreSQL database, `ratatoskr`, created by `ratatoskr-platform`'s `deploy/postgres/01-database-and-roles.sql` with an explicitly stated ICU collation, and every service SHALL connect to it as its own role. The role names are `ratatoskr_<service>` for `chatgpt`, `claude`, `knowledge`, `channel_digests`, `telegram` (the webhook and the dispatcher share it), `x`, `instagram`, `threads`, `vault`, `github` and `extractor`, in addition to Platform's `ratatoskr_edge`, `ratatoskr_ingest` and `ratatoskr_scheduler`. Every schema SHALL be namespaced by its service. The database URL of every `deploy/systemd/*.conf.example` SHALL be `postgres://ratatoskr_<service>:CHANGE-ME@127.0.0.1:5432/ratatoskr` (or `postgresql://` where the repository already spells it so). The development compose files of the repositories keep their own databases, as a development convenience stated in their READMEs.

#### Scenario: An example names a role or database nothing creates

- **WHEN** a deploy example holds a database URL whose host is not `127.0.0.1`, whose port is not 5432, whose database is not `ratatoskr`, or whose role no checked-in `deploy/postgres/role.sql` or Platform's `01-database-and-roles.sql` creates
- **THEN** `every_database_url_in_a_deploy_example_names_a_role_a_checked_in_file_creates` in `ratatoskr-workspace` fails and names the repository, the example and what is wrong

### Requirement: Each role is provisioned by a checked-in file, in a fixed order

Each of those repositories SHALL ship `deploy/postgres/role.sql`: it creates the role if absent without a password (the password is set separately with `\password`), applies `nosuperuser nocreatedb nocreaterole noreplication nobypassrls`, grants `connect` and `create` on the database to the role, connects to `ratatoskr` and revokes all rights on schema `public` from it. Knowledge's file SHALL additionally run `create extension if not exists vector`, and grant `usage` on schema `public` because the `vector` type lives there, because pgvector is not a trusted extension and only a PostgreSQL administrator may install it; Knowledge's README, its `deploy/README.md` and its example SHALL state that prerequisite. Platform's `deploy/README.md` SHALL give the order: `01-database-and-roles.sql`, the first start of Edge (it applies `schema.sql`), `02-grants.sql`, and then each service's `role.sql` before that service's first start. A role file that does not run as written is a defect of the owning repository and is not patched by whoever provisions.

#### Scenario: Knowledge's role file is missing the extension

- **WHEN** Knowledge's `role.sql` does not create the `vector` extension
- **THEN** `the_knowledge_role_file_creates_the_vector_extension` in `ratatoskr-workspace` fails, because the unprivileged service role cannot create it at startup

#### Scenario: Every role file is run as written

- **WHEN** the files are run in the documented order on a fresh cluster
- **THEN** each role connects, is not a superuser and has none of the other privileges, verified by flow F0 of the native smoke when it is run
