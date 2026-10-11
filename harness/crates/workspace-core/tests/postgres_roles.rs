//! `PostgreSQL` provisioning agreement (XR-021 CONTRACTS R3-11): one database, `ratatoskr`, on port 5432, and one role per service that a checked-in file creates.
//!
//! Before this check a deployment that followed the examples could not start most services: the examples named roles and databases that nothing created, and some named the development compose port. The check reads every `deploy/systemd/*.conf.example` of every pinned repository, takes each active line that holds a `postgres://` or `postgresql://` URL, and requires that
//!
//! - the host is `127.0.0.1`, the port is 5432 and the database is `ratatoskr`, and
//! - the role in the URL is created by the repository's own `deploy/postgres/role.sql` or by Platform's `deploy/postgres/01-database-and-roles.sql` (a `create role <role>` statement).
//!
//! Limitation, stated plainly. This is a text scan. A role counts as created when the file holds the words `create role <name>` (any case, any spacing) outside a `--` comment. The scan cannot run the SQL, cannot see a password (the examples hold `CHANGE-ME` or `REPLACE_ME`), and cannot see a URL assembled from separate keys, such as a host, port and database spelled in three variables. Whether the files really provision a working role is what the native smoke proves (`integration/native`, flow F0), and it is a manual run.
//!
//! Real sample at the round 3 pins: `RATATOSKR__STORAGE__DATABASE_URL=postgres://ratatoskr_knowledge:CHANGE-ME@127.0.0.1:5432/ratatoskr` in `knowledge/deploy/systemd/knowledge.conf.example`, role created by `knowledge/deploy/postgres/role.sql`.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

#[path = "support/checkout.rs"]
mod checkout;

use checkout::{committed_manifest, repository_root, require_checkout, tracked_files};
use std::fs;

const ROLE_FILE: &str = "deploy/postgres/role.sql";
const PLATFORM_ROLE_FILE: &str = "deploy/postgres/01-database-and-roles.sql";

/// One database URL as written in an example.
#[derive(Debug, PartialEq, Eq)]
struct DatabaseUrl {
    role: String,
    host: String,
    port: String,
    database: String,
}

/// Every active (not commented) database URL of an example file.
fn database_urls(example: &str) -> Vec<DatabaseUrl> {
    example
        .lines()
        .map(str::trim)
        .filter(|line| !line.starts_with('#'))
        .filter_map(|line| {
            let (_, value) = line.split_once('=')?;
            let value = value.trim().trim_matches('"');
            let rest = value
                .strip_prefix("postgres://")
                .or_else(|| value.strip_prefix("postgresql://"))?;
            let (credentials, location) = rest.split_once('@')?;
            let (role, _) = credentials.split_once(':').unwrap_or((credentials, ""));
            let (host_port, path) = location.split_once('/')?;
            let (host, port) = host_port.rsplit_once(':').unwrap_or((host_port, ""));
            let database = path.split('?').next().unwrap_or_default();
            Some(DatabaseUrl {
                role: role.to_owned(),
                host: host.to_owned(),
                port: port.to_owned(),
                database: database.to_owned(),
            })
        })
        .collect()
}

/// Whether a SQL file creates `role` outside a `--` comment.
fn creates_role(sql: &str, role: &str) -> bool {
    let wanted = format!("create role {}", role.to_ascii_lowercase());
    sql.lines()
        .map(|line| line.split("--").next().unwrap_or_default())
        .map(|line| {
            line.split_whitespace()
                .collect::<Vec<_>>()
                .join(" ")
                .to_ascii_lowercase()
        })
        .any(|line| {
            line.match_indices(&wanted).any(|(at, _)| {
                let end = at + wanted.len();
                line.get(end..).is_none_or(|rest| {
                    !rest.starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_')
                })
            })
        })
}

/// Disagreements of one repository's examples with its provisioning files, one line each.
fn url_problems(
    repository: &str,
    example: &str,
    urls: &[DatabaseUrl],
    role_sql: &[(String, String)],
) -> Vec<String> {
    let mut problems = Vec::new();
    for url in urls {
        if url.host != "127.0.0.1" {
            problems.push(format!(
                "{repository}: {example} names host `{}`, expected 127.0.0.1",
                url.host
            ));
        }
        if url.port != "5432" {
            problems.push(format!(
                "{repository}: {example} names port `{}`, expected 5432",
                url.port
            ));
        }
        if url.database != "ratatoskr" {
            problems.push(format!(
                "{repository}: {example} names database `{}`, expected `ratatoskr`",
                url.database
            ));
        }
        if !role_sql.iter().any(|(_, sql)| creates_role(sql, &url.role)) {
            let files = role_sql
                .iter()
                .map(|(path, _)| path.as_str())
                .collect::<Vec<_>>()
                .join(", ");
            problems.push(format!(
                "{repository}: {example} connects as `{}`, which no checked-in file creates (looked in: {files})",
                url.role
            ));
        }
    }
    problems
}

/// The provisioning files that may create a service role of `repository`.
fn provisioning_files(repository: &str, root: &std::path::Path) -> Vec<(String, String)> {
    let mut files = Vec::new();
    if let Ok(sql) = fs::read_to_string(root.join(ROLE_FILE)) {
        files.push((format!("{repository}/{ROLE_FILE}"), sql));
    }
    let manifest = committed_manifest();
    let platform = require_checkout(&manifest, "platform");
    if let Ok(sql) = fs::read_to_string(platform.join(PLATFORM_ROLE_FILE)) {
        files.push((format!("platform/{PLATFORM_ROLE_FILE}"), sql));
    }
    files
}

#[test]
fn every_database_url_in_a_deploy_example_names_a_role_a_checked_in_file_creates() {
    let manifest = committed_manifest();
    let mut problems = Vec::new();
    let mut examined = 0_usize;

    for repository in manifest.repositories() {
        let root = repository_root(repository);
        assert!(
            root.join(".git").exists(),
            "repository `{}` is not checked out at {}",
            repository.id,
            root.display()
        );
        let role_sql = provisioning_files(&repository.id, &root);
        for (path, text) in tracked_files(&root, "deploy/systemd/*.conf.example") {
            let urls = database_urls(&text);
            examined += urls.len();
            problems.extend(url_problems(&repository.id, &path, &urls, &role_sql));
        }
    }

    assert!(
        examined >= 10,
        "expected at least ten database URLs across the deploy examples, found {examined}"
    );
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn the_knowledge_role_file_creates_the_vector_extension() {
    let manifest = committed_manifest();
    let root = require_checkout(&manifest, "knowledge");
    let path = root.join(ROLE_FILE);
    let sql = fs::read_to_string(&path).unwrap_or_default();
    let creates = sql
        .lines()
        .map(|line| {
            line.split("--")
                .next()
                .unwrap_or_default()
                .to_ascii_lowercase()
        })
        .any(|line| line.contains("create extension if not exists vector"));

    assert!(
        creates,
        "{} is missing or does not create the vector extension, which pgvector's untrusted status keeps a service role from doing",
        path.display()
    );
}

#[test]
fn the_scan_reads_urls_and_reports_a_role_nothing_creates() {
    let example = "# RATATOSKR__DATABASE__URL=postgres://ghost:x@127.0.0.1:5432/ratatoskr\n\
                   RATATOSKR__DATABASE__URL=postgres://ratatoskr_a:CHANGE-ME@127.0.0.1:5432/ratatoskr\n\
                   OTHER=postgresql://ratatoskr_b:y@db.example:5435/other?sslmode=disable\n";
    let urls = database_urls(example);
    assert_eq!(urls.len(), 2, "{urls:?}");
    assert_eq!(
        urls.first().map(|url| url.role.as_str()),
        Some("ratatoskr_a")
    );

    let sql = vec![(
        "a/role.sql".to_owned(),
        "-- create role ratatoskr_b login;\ncreate role  ratatoskr_a login;\n".to_owned(),
    )];
    let problems = url_problems("a", "example", &urls, &sql);
    assert!(
        problems
            .iter()
            .any(|line| line.contains("ratatoskr_b") && line.contains("no checked-in file")),
        "a role created only in a comment must be reported: {problems:?}"
    );
    assert!(
        problems.iter().any(|line| line.contains("db.example")),
        "{problems:?}"
    );
    assert!(
        problems.iter().any(|line| line.contains("5435")),
        "{problems:?}"
    );
    assert!(
        problems.iter().any(|line| line.contains("`other`")),
        "{problems:?}"
    );
    assert!(
        !problems.iter().any(|line| line.contains("`ratatoskr_a`")),
        "the role that is created must not be reported: {problems:?}"
    );

    assert!(!creates_role(
        "create role ratatoskr_ab login;",
        "ratatoskr_a"
    ));
}
