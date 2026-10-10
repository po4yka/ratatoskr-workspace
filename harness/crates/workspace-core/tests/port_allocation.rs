//! Port allocation contract: `docs/DEPLOYMENT_TARGET.md` is the one table of listeners, and the
//! deploy examples of the pinned child repositories may only bind ports that table allocates.
//!
//! Regex sanity check (run against the real files before the matcher was trusted). A line is a
//! bind when, after dropping leading `#` and whitespace, it is `RATATOSKR__<...>__BIND`,
//! `__LISTEN_ADDRESS` or `__LISTENER` `=` `host:port`. The real matches at the XR-021 pins:
//!
//! - platform `.env.example`: `ADMIN__BIND` 9464, `PUBLIC__BIND` 8080, `CHANNEL_DIGESTS__LISTENER` 8098
//!   (the last is an upstream address, not a bind).
//! - platform `deploy/systemd/edge.conf.example`: `ADMIN__BIND` 9464, `PUBLIC__BIND` 8080, eight
//!   `GATEWAY__ROUTES__*__LISTENER` upstream addresses (8091 to 8097) and `CHANNEL_DIGESTS__LISTENER`.
//! - platform `ingest.conf.example`: 9465 and 8181; `scheduler.conf.example`: 9466.
//! - extractor `extractor.conf.example`: `ADMIN__BIND` 9088 (it was 9467 before XR-021, which the
//!   Telegram webhook also bound).
//! - vault `.env.example`: `ADMIN__BIND` 9570.
//! - telegram `.env.example`: `ADMIN__BIND` 9467, `WEBHOOK__BIND` 8182; `webhook.conf.example` 9467
//!   and 8182; `dispatcher.conf.example` 9468.
//!
//! Repositories that document no bind in an example (knowledge, github, channel-digests, x,
//! instagram, threads, chatgpt, claude, the clients) contribute nothing; their ports are covered
//! by the table test, not by this scan.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

#[path = "support/checkout.rs"]
mod checkout;

use checkout::{committed_manifest, is_checked_out, repository_root, workspace_root};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

/// Every listener the table must name: the XR-021 allocation of S05.
const REQUIRED_PORTS: &[u16] = &[
    4222, 5432, 8080, 8091, 8092, 8093, 8094, 8095, 8096, 8097, 8098, 8181, 8182, 8222, 9081, 9082,
    9083, 9084, 9085, 9086, 9087, 9088, 9095, 9464, 9465, 9466, 9467, 9468, 9469, 9470, 9570,
];

/// Bind keys end in one of these.
const BIND_SUFFIXES: [&str; 3] = ["__BIND", "__LISTEN_ADDRESS", "__LISTENER"];

/// Keys that name the address of another service's listener. They must be allocated but they do
/// not claim a port: the owning service binds it.
const UPSTREAM_ADDRESS_KEY_PREFIXES: [&str; 2] = [
    "RATATOSKR__GATEWAY__ROUTES__",
    "RATATOSKR__CHANNEL_DIGESTS__LISTENER",
];

#[derive(Debug)]
struct Claim {
    repository: String,
    key: String,
    role: Option<String>,
    port: u16,
    file: PathBuf,
}

/// The ports of the `## Ports` table, one `(port, owner cell)` per port token.
fn table_ports() -> Vec<(u16, String)> {
    let path = workspace_root().join("docs/DEPLOYMENT_TARGET.md");
    let source = fs::read_to_string(&path).expect("docs/DEPLOYMENT_TARGET.md exists");
    let mut in_ports = false;
    let mut rows = Vec::new();
    for line in source.lines() {
        if line.starts_with("## ") {
            in_ports = line.trim() == "## Ports";
            continue;
        }
        if !in_ports || !line.trim_start().starts_with('|') {
            continue;
        }
        let cells = line
            .trim()
            .trim_matches('|')
            .split('|')
            .map(str::trim)
            .collect::<Vec<_>>();
        let (Some(port_cell), Some(owner)) = (cells.first(), cells.get(1)) else {
            continue;
        };
        if *port_cell == "Port" || port_cell.chars().all(|c| c == '-' || c == ' ' || c == ':') {
            continue;
        }
        for token in port_cell.split('/') {
            let port = token.trim().parse::<u16>().unwrap_or_else(|_| {
                panic!("Ports table row has a cell that is not a port number: `{port_cell}`")
            });
            rows.push((port, (*owner).to_owned()));
        }
    }
    rows
}

fn example_files(root: &Path) -> Vec<PathBuf> {
    let mut files = Vec::new();
    let env_example = root.join(".env.example");
    if env_example.is_file() {
        files.push(env_example);
    }
    let mut pending = vec![root.join("deploy")];
    while let Some(directory) = pending.pop() {
        let Ok(entries) = fs::read_dir(&directory) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            if path.is_dir() {
                if name != "target" && name != "node_modules" && name != ".git" {
                    pending.push(path);
                }
            } else if name.ends_with(".example") {
                files.push(path);
            }
        }
    }
    files.sort();
    files
}

/// `Some((key, port))` when the line is a bind, documented or commented out.
fn bind_of(line: &str) -> Option<(String, u16)> {
    let statement = line.trim().trim_start_matches('#').trim_start();
    if !statement.starts_with("RATATOSKR__") {
        return None;
    }
    let (key, value) = statement.split_once('=')?;
    let key = key.trim();
    if !BIND_SUFFIXES.iter().any(|suffix| key.ends_with(suffix)) {
        return None;
    }
    let value = value.trim().trim_matches('"');
    let (host, port) = value.rsplit_once(':')?;
    if host.is_empty() {
        return None;
    }
    Some((key.to_owned(), port.trim().parse::<u16>().ok()?))
}

fn role_of(file: &Path) -> Option<String> {
    let name = file.file_name()?.to_string_lossy().into_owned();
    name.strip_suffix(".conf.example").map(str::to_owned)
}

fn is_upstream_address(key: &str) -> bool {
    UPSTREAM_ADDRESS_KEY_PREFIXES
        .iter()
        .any(|prefix| key.starts_with(prefix))
}

fn conflicts(first: &Claim, second: &Claim) -> bool {
    first.repository != second.repository
        || first.key != second.key
        || (first.role.is_some() && second.role.is_some() && first.role != second.role)
}

#[test]
fn the_ports_table_is_unique_and_covers_every_documented_listener() {
    let rows = table_ports();
    let mut seen = BTreeMap::<u16, usize>::new();
    for (port, _) in &rows {
        *seen.entry(*port).or_default() += 1;
    }
    let duplicated = seen
        .iter()
        .filter(|(_, count)| **count > 1)
        .map(|(port, _)| *port)
        .collect::<Vec<_>>();
    let missing = REQUIRED_PORTS
        .iter()
        .filter(|port| !seen.contains_key(port))
        .collect::<Vec<_>>();

    assert!(!rows.is_empty(), "the `## Ports` table has no rows");
    assert!(
        duplicated.is_empty(),
        "ports appear more than once in the Ports table: {duplicated:?}"
    );
    assert!(
        missing.is_empty(),
        "the Ports table does not allocate these documented listeners: {missing:?}"
    );
}

#[test]
fn no_two_deploy_examples_bind_the_same_port_and_every_bind_is_allocated() {
    let manifest = committed_manifest();
    let allocated = table_ports()
        .into_iter()
        .map(|(port, _)| port)
        .collect::<BTreeSet<_>>();
    let mut claims = Vec::new();
    let mut references = Vec::new();

    for repository in manifest.repositories() {
        let root = repository_root(repository);
        if !is_checked_out(&root) {
            eprintln!(
                "skipping `{}`: not checked out at {}",
                repository.id,
                root.display()
            );
            continue;
        }
        for file in example_files(&root) {
            let text = fs::read_to_string(&file).unwrap_or_default();
            for line in text.lines() {
                let Some((key, port)) = bind_of(line) else {
                    continue;
                };
                let claim = Claim {
                    repository: repository.id.clone(),
                    key: key.clone(),
                    role: role_of(&file),
                    port,
                    file: file.clone(),
                };
                if is_upstream_address(&key) {
                    references.push(claim);
                } else {
                    claims.push(claim);
                }
            }
        }
    }

    assert!(
        !claims.is_empty(),
        "the matcher found no bind in any checked-out repository; it is broken or nothing is checked out"
    );

    let mut problems = Vec::new();
    for claim in claims.iter().chain(&references) {
        if !allocated.contains(&claim.port) {
            problems.push(format!(
                "{} `{}` names port {} which `docs/DEPLOYMENT_TARGET.md` does not allocate ({})",
                claim.repository,
                claim.key,
                claim.port,
                claim.file.display()
            ));
        }
    }
    for (index, first) in claims.iter().enumerate() {
        for second in claims.iter().skip(index + 1) {
            if first.port == second.port && conflicts(first, second) {
                problems.push(format!(
                    "port {} is claimed by {} `{}` ({}) and by {} `{}` ({})",
                    first.port,
                    first.repository,
                    first.key,
                    first.file.display(),
                    second.repository,
                    second.key,
                    second.file.display()
                ));
            }
        }
    }

    assert!(problems.is_empty(), "{}", problems.join("\n"));
}
