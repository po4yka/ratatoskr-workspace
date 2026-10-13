//! Cross-service base URLs (XR-021 CONTRACTS R5-14 rule 6, the coverage gap of the R4 verdict).
//!
//! `port_allocation.rs` checks the ports a service BINDS and `edge_upstreams.rs` checks the upstreams in Edge's route table. A third kind of key points one fleet service at another: the base URL Knowledge uses to read GitHub's README, the address channel-digests uses to reach Knowledge, the Platform address Telegram targets, and the listeners Platform's examples name for the channel-digests API and the two archive receivers. A wrong port there is a 502 at runtime that no build sees. This test reads each such key from the shipped example and asserts that its port is the one `docs/DEPLOYMENT_TARGET.md` gives the service the key points at.
//!
//! Limitation, stated plainly. The list of keys is written down here (`REFERENCES`); a new key that points at another service is not found by a scan, it has to be added. A value is read as the text after `KEY=` on the first line that carries the key (a commented-out line counts, because it documents the value an operator uncomments), with the scheme, the path and the quotes removed. The target is the first column of the port table: the row whose owner text starts with the stated fragment; the test fails when no row or more than one row matches, so a renamed row is reported. Keys whose target is outside the fleet (`RATATOSKR__BOT_API__BASE_URL`, the provider API origins, the NATS URL) are out of scope.
//!
//! Sanity run on the real samples (the round 4 pins): `knowledge/deploy/systemd/knowledge.conf.example` `RATATOSKR__INGEST__GITHUB_README_BASE_URL=http://127.0.0.1:8092/` reads port 8092 and `RATATOSKR__CHANNEL_RECAP__DIGEST_SOURCE_BASE_URL=http://127.0.0.1:8098/` reads 8098; `channel-digests/deploy/systemd/api.conf.example` `RATATOSKR__KNOWLEDGE__BASE_URL=http://127.0.0.1:8091` reads 8091; the Telegram examples read 8080; Platform's `edge.conf.example` reads 8091 to 8098 for the route and channel-digests listeners. The mutation test changes one port in a copy of an example and expects exactly that key to be reported.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

#[path = "support/checkout.rs"]
mod checkout;

use checkout::{committed_manifest, require_checkout, workspace_root};
use std::fs;

/// One key that points at another fleet service.
struct Reference {
    repository: &'static str,
    file: &'static str,
    key: &'static str,
    /// The start of the owner text of the port table row for the service the key points at.
    target: &'static str,
}

const KNOWLEDGE_API: &str = "`ratatoskr-knowledge` domain API";
const GITHUB_API: &str = "`ratatoskr-github` domain API";
const VAULT_API: &str = "`ratatoskr-vault` domain API";
const SOCIAL_API: &str = "`ratatoskr-social` domain API";
const AI_API: &str = "`ratatoskr-ai-archive` domain API";
const CHATGPT_RECEIPT: &str = "`ratatoskr-chatgpt` archive receipt";
const CLAUDE_RECEIPT: &str = "`ratatoskr-claude` archive receipt";
const DIGESTS_API: &str = "`ratatoskr-channel-digests` API (";
const EDGE_API: &str = "`ratatoskr-edge` public API";

const fn reference(
    repository: &'static str,
    file: &'static str,
    key: &'static str,
    target: &'static str,
) -> Reference {
    Reference {
        repository,
        file,
        key,
        target,
    }
}

const REFERENCES: [Reference; 20] = [
    reference(
        "knowledge",
        "deploy/systemd/knowledge.conf.example",
        "RATATOSKR__INGEST__GITHUB_README_BASE_URL",
        GITHUB_API,
    ),
    reference(
        "knowledge",
        "deploy/systemd/knowledge.conf.example",
        "RATATOSKR__CHANNEL_RECAP__DIGEST_SOURCE_BASE_URL",
        DIGESTS_API,
    ),
    reference(
        "channel-digests",
        "deploy/systemd/api.conf.example",
        "RATATOSKR__KNOWLEDGE__BASE_URL",
        KNOWLEDGE_API,
    ),
    reference(
        "telegram",
        "deploy/systemd/webhook.conf.example",
        "RATATOSKR__PLATFORM__BASE_URL",
        EDGE_API,
    ),
    reference(
        "telegram",
        "deploy/systemd/dispatcher.conf.example",
        "RATATOSKR__PLATFORM__BASE_URL",
        EDGE_API,
    ),
    reference(
        "telegram",
        ".env.example",
        "RATATOSKR__PLATFORM__BASE_URL",
        EDGE_API,
    ),
    reference(
        "platform",
        "deploy/systemd/edge.conf.example",
        "RATATOSKR__CHANNEL_DIGESTS__LISTENER",
        DIGESTS_API,
    ),
    reference(
        "platform",
        ".env.example",
        "RATATOSKR__CHANNEL_DIGESTS__LISTENER",
        DIGESTS_API,
    ),
    reference(
        "platform",
        "deploy/systemd/edge.conf.example",
        "RATATOSKR__GATEWAY__ROUTES__KNOWLEDGE__LISTENER",
        KNOWLEDGE_API,
    ),
    reference(
        "platform",
        "deploy/systemd/edge.conf.example",
        "RATATOSKR__GATEWAY__ROUTES__GITHUB__LISTENER",
        GITHUB_API,
    ),
    reference(
        "platform",
        "deploy/systemd/edge.conf.example",
        "RATATOSKR__GATEWAY__ROUTES__VAULT__LISTENER",
        VAULT_API,
    ),
    reference(
        "platform",
        "deploy/systemd/edge.conf.example",
        "RATATOSKR__GATEWAY__ROUTES__SOCIAL__LISTENER",
        SOCIAL_API,
    ),
    reference(
        "platform",
        "deploy/systemd/edge.conf.example",
        "RATATOSKR__GATEWAY__ROUTES__AI__LISTENER",
        AI_API,
    ),
    reference(
        "platform",
        "deploy/systemd/edge.conf.example",
        "RATATOSKR__GATEWAY__ROUTES__CHATGPT__LISTENER",
        CHATGPT_RECEIPT,
    ),
    reference(
        "platform",
        "deploy/systemd/edge.conf.example",
        "RATATOSKR__GATEWAY__ROUTES__CLAUDE__LISTENER",
        CLAUDE_RECEIPT,
    ),
    reference(
        "chatgpt",
        "deploy/systemd/chatgpt.conf.example",
        "RATATOSKR__RECEIPT__LISTEN_ADDRESS",
        CHATGPT_RECEIPT,
    ),
    reference(
        "claude",
        "deploy/systemd/claude.conf.example",
        "RATATOSKR__RECEIPT__LISTEN_ADDRESS",
        CLAUDE_RECEIPT,
    ),
    reference(
        "knowledge",
        "deploy/systemd/knowledge.conf.example",
        "RATATOSKR__API__LISTEN_ADDRESS",
        KNOWLEDGE_API,
    ),
    reference(
        "channel-digests",
        "deploy/systemd/api.conf.example",
        "RATATOSKR__API__LISTEN_ADDRESS",
        DIGESTS_API,
    ),
    reference(
        "platform",
        "deploy/systemd/edge.conf.example",
        "RATATOSKR__PUBLIC__BIND",
        EDGE_API,
    ),
];

/// The port in the value of the first line that carries `key=`, commented out or not.
fn port_of(example: &str, key: &str) -> Option<u16> {
    let value = example.lines().find_map(|line| {
        let statement = line.trim().trim_start_matches('#').trim_start();
        let (name, value) = statement.split_once('=')?;
        (name.trim() == key).then(|| value.trim().trim_matches('"').to_owned())
    })?;
    let authority = value
        .split_once("://")
        .map_or(value.as_str(), |(_, rest)| rest)
        .split('/')
        .next()?;
    authority.rsplit_once(':')?.1.trim().parse().ok()
}

/// The ports of the rows of the port table whose owner text starts with `fragment`.
fn table_ports(table: &str, fragment: &str) -> Vec<u16> {
    table
        .lines()
        .filter_map(|line| {
            let mut cells = line.trim().strip_prefix('|')?.split('|');
            let port = cells.next()?.trim().parse::<u16>().ok()?;
            let owner = cells.next()?.trim();
            owner.starts_with(fragment).then_some(port)
        })
        .collect()
}

/// Disagreements for one reference, one line each.
fn problems(reference: &Reference, example: &str, table: &str) -> Vec<String> {
    let Reference {
        repository,
        file,
        key,
        target,
    } = reference;
    let Some(stated) = port_of(example, key) else {
        return vec![format!("{repository} {file} has no readable `{key}`")];
    };
    match table_ports(table, target).as_slice() {
        [expected] if *expected == stated => Vec::new(),
        [expected] => vec![format!(
            "{repository} {file}: `{key}` points at port {stated}, DEPLOYMENT_TARGET.md gives {target} port {expected}"
        )],
        other => vec![format!(
            "DEPLOYMENT_TARGET.md has {} rows starting with `{target}`, expected exactly one (key `{key}` of {repository})",
            other.len()
        )],
    }
}

fn port_table() -> String {
    fs::read_to_string(workspace_root().join("docs/DEPLOYMENT_TARGET.md"))
        .expect("docs/DEPLOYMENT_TARGET.md exists")
}

fn example_text(reference: &Reference) -> String {
    let manifest = committed_manifest();
    let root = require_checkout(&manifest, reference.repository);
    fs::read_to_string(root.join(reference.file)).unwrap_or_else(|error| {
        panic!(
            "cannot read {} of {}: {error}",
            reference.file, reference.repository
        )
    })
}

#[test]
fn every_cross_service_base_url_and_listener_names_the_port_of_its_target() {
    let table = port_table();
    let mut all = Vec::new();
    for reference in &REFERENCES {
        all.extend(problems(reference, &example_text(reference), &table));
    }
    assert!(all.is_empty(), "{}", all.join("\n"));
}

#[test]
fn a_port_changed_in_a_copy_of_an_example_is_reported() {
    let table = port_table();
    let reference = &REFERENCES[1];
    let example = example_text(reference);
    assert!(
        problems(reference, &example, &table).is_empty(),
        "the unmodified example must pass before the mutation means anything"
    );
    let mutated = example.replace(
        "RATATOSKR__CHANNEL_RECAP__DIGEST_SOURCE_BASE_URL=http://127.0.0.1:8098/",
        "RATATOSKR__CHANNEL_RECAP__DIGEST_SOURCE_BASE_URL=http://127.0.0.1:8099/",
    );
    assert_ne!(mutated, example, "the mutation did not change the example");
    let found = problems(reference, &mutated, &table);
    assert_eq!(found.len(), 1, "{found:?}");
    assert!(
        found
            .first()
            .is_some_and(|line| line.contains("DIGEST_SOURCE_BASE_URL") && line.contains("8099"))
    );
}

#[test]
fn a_renamed_table_row_and_a_missing_key_are_reported() {
    let table = port_table();
    let renamed = table.replace(
        "`ratatoskr-github` domain API",
        "`ratatoskr-github` catalog API",
    );
    assert_ne!(renamed, table, "the mutation did not change the table");
    let github = REFERENCES
        .iter()
        .find(|reference| reference.target == GITHUB_API)
        .expect("a reference to the github API");
    let found = problems(github, &example_text(github), &renamed);
    assert!(
        found
            .iter()
            .any(|line| line.contains("expected exactly one")),
        "{found:?}"
    );
    assert_eq!(
        problems(github, "# nothing here\n", &table).len(),
        1,
        "a missing key must be reported"
    );
}

#[test]
fn the_value_reader_handles_a_scheme_a_path_a_quote_and_a_comment() {
    assert_eq!(port_of("K=http://127.0.0.1:8092/", "K"), Some(8092));
    assert_eq!(port_of("#K=\"127.0.0.1:8098\"", "K"), Some(8098));
    assert_eq!(port_of("  # K = http://h:80/a/b", "K"), Some(80));
    assert_eq!(port_of("OTHER=1:2", "K"), None);
    assert_eq!(port_of("K=http://example.org/", "K"), None);
}
