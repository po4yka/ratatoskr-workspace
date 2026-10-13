# Spec Delta

This delta requires `add-notes-write-back` (OBS-024) to be archived first.

## MODIFIED Requirements

### Requirement: There is one database and each service has its own role

The fleet SHALL use one PostgreSQL database, `ratatoskr`, created by `ratatoskr-platform`'s `deploy/postgres/01-database-and-roles.sql` with an explicitly stated ICU collation, and every service SHALL connect to it as its own role. The role names are `ratatoskr_<service>` for `chatgpt`, `claude`, `knowledge`, `channel_digests`, `telegram` (the webhook and the dispatcher share it), `x`, `instagram`, `threads`, `vault`, `github`, `extractor`, `notes` and `sites`, in addition to Platform's `ratatoskr_edge`, `ratatoskr_ingest` and `ratatoskr_scheduler`. Every schema SHALL be namespaced by its service. The database URL of every `deploy/systemd/*.conf.example` SHALL be `postgres://ratatoskr_<service>:CHANGE-ME@127.0.0.1:5432/ratatoskr` (or `postgresql://` where the repository already spells it so). The development compose files of the repositories keep their own databases, as a development convenience stated in their READMEs.

#### Scenario: An example names a role or database nothing creates

- **WHEN** a deploy example holds a database URL whose host is not `127.0.0.1`, whose port is not 5432, whose database is not `ratatoskr`, or whose role no checked-in `deploy/postgres/role.sql` or Platform's `01-database-and-roles.sql` creates
- **THEN** `every_database_url_in_a_deploy_example_names_a_role_a_checked_in_file_creates` in `ratatoskr-workspace` fails and names the repository, the example and what is wrong

#### Scenario: The notes role is provisioned

- **WHEN** `every_database_url_in_a_deploy_example_names_a_role_a_checked_in_file_creates` reads the pinned `ratatoskr-notes` example
- **THEN** its database URL names `ratatoskr_notes`, and the role is created by `deploy/postgres/role.sql` of `ratatoskr-notes`

#### Scenario: The sites role is provisioned

- **WHEN** `every_database_url_in_a_deploy_example_names_a_role_a_checked_in_file_creates` reads the pinned `ratatoskr-sites` example
- **THEN** its database URL names `ratatoskr_sites`, and the role is created by `deploy/postgres/role.sql` of `ratatoskr-sites`
