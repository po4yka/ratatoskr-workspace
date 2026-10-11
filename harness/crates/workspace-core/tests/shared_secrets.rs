//! Shared secrets (XR-021 CONTRACTS R3-18 rule 3): four pairs of keys must carry one value, and a pair that is spelled differently on its two sides is a service that answers 401 forever.
//!
//! - Edge `RATATOSKR__CHANNEL_DIGESTS__SERVICE_SECRET` and the channel-digests API `RATATOSKR__AUTH__SERVICE_SECRET`.
//! - Knowledge `RATATOSKR__CHANNEL_RECAP__DIGEST_SOURCE_SERVICE_SECRET` and the same API key.
//! - The channel-digests API `RATATOSKR__KNOWLEDGE__RESULT_READER_SERVICE_SECRET` and Knowledge `RATATOSKR__CHANNEL_RECAP__RESULT_READER_SERVICE_SECRET`.
//! - Knowledge `RATATOSKR__INGEST__GITHUB_README_SERVICE_SECRET` and GitHub `RATATOSKR__INTERNAL__READER_SERVICE_SECRET`.
//!
//! What this check can and cannot see. It requires that each key of every pair is set on an active line of the owning repository's deploy example, so a key renamed on one side only fails here. It CANNOT compare values: every example holds the placeholder `CHANGE-ME`, and a real value never enters a repository. Whether the two sides of a deployment hold the same secret is checked only at run time (a 401 between the services) and by the manual native smoke, which renders one random value into both sides of each pair.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

#[path = "support/checkout.rs"]
mod checkout;

use checkout::{committed_manifest, require_checkout};
use std::fs;

/// One side of a pair: the repository, the example file inside it and the key.
type Side = (&'static str, &'static str, &'static str);

const EDGE_TO_DIGESTS: (Side, Side) = (
    (
        "platform",
        "deploy/systemd/edge.conf.example",
        "RATATOSKR__CHANNEL_DIGESTS__SERVICE_SECRET",
    ),
    (
        "channel-digests",
        "deploy/systemd/api.conf.example",
        "RATATOSKR__AUTH__SERVICE_SECRET",
    ),
);
const KNOWLEDGE_TO_DIGESTS: (Side, Side) = (
    (
        "knowledge",
        "deploy/systemd/knowledge.conf.example",
        "RATATOSKR__CHANNEL_RECAP__DIGEST_SOURCE_SERVICE_SECRET",
    ),
    (
        "channel-digests",
        "deploy/systemd/api.conf.example",
        "RATATOSKR__AUTH__SERVICE_SECRET",
    ),
);
const DIGESTS_TO_KNOWLEDGE: (Side, Side) = (
    (
        "channel-digests",
        "deploy/systemd/api.conf.example",
        "RATATOSKR__KNOWLEDGE__RESULT_READER_SERVICE_SECRET",
    ),
    (
        "knowledge",
        "deploy/systemd/knowledge.conf.example",
        "RATATOSKR__CHANNEL_RECAP__RESULT_READER_SERVICE_SECRET",
    ),
);
const KNOWLEDGE_TO_GITHUB: (Side, Side) = (
    (
        "knowledge",
        "deploy/systemd/knowledge.conf.example",
        "RATATOSKR__INGEST__GITHUB_README_SERVICE_SECRET",
    ),
    (
        "github",
        "deploy/systemd/github.conf.example",
        "RATATOSKR__INTERNAL__READER_SERVICE_SECRET",
    ),
);
const PAIRS: [(Side, Side); 4] = [
    EDGE_TO_DIGESTS,
    KNOWLEDGE_TO_DIGESTS,
    DIGESTS_TO_KNOWLEDGE,
    KNOWLEDGE_TO_GITHUB,
];

/// Whether an active (not commented) line of the example assigns the key.
fn sets_key(example: &str, key: &str) -> bool {
    example
        .lines()
        .map(str::trim)
        .filter(|line| !line.starts_with('#'))
        .any(|line| {
            line.split_once('=')
                .is_some_and(|(name, value)| name.trim() == key && !value.trim().is_empty())
        })
}

fn read_example(repository: &str, relative: &str) -> String {
    let manifest = committed_manifest();
    let path = require_checkout(&manifest, repository).join(relative);
    fs::read_to_string(&path).unwrap_or_else(|error| panic!("read {}: {error}", path.display()))
}

/// The sides of the pairs whose key is not set in the example, one line each.
fn missing_keys(read: &dyn Fn(&str, &str) -> String, pairs: &[(Side, Side)]) -> Vec<String> {
    let mut problems = Vec::new();
    for (left, right) in pairs {
        for (repository, relative, key) in [left, right] {
            if !sets_key(&read(repository, relative), key) {
                problems.push(format!(
                    "{repository}: {relative} does not set {key}, which pairs with {} and {}",
                    left.2, right.2
                ));
            }
        }
    }
    problems
}

#[test]
fn paired_secret_keys_exist_on_both_sides() {
    let problems = missing_keys(&read_example, &PAIRS);
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn the_scan_reports_a_renamed_key_and_ignores_a_commented_one() {
    let real = read_example("knowledge", "deploy/systemd/knowledge.conf.example");
    assert!(
        sets_key(&real, "RATATOSKR__INGEST__GITHUB_README_SERVICE_SECRET"),
        "the unmodified example must pass before a mutation means anything"
    );

    let renamed = real.replace(
        "RATATOSKR__INGEST__GITHUB_README_SERVICE_SECRET=",
        "RATATOSKR__INGEST__GITHUB_README_SECRET=",
    );
    assert_ne!(renamed, real, "the mutation did not change the example");
    assert!(!sets_key(
        &renamed,
        "RATATOSKR__INGEST__GITHUB_README_SERVICE_SECRET"
    ));

    let commented = real.replace(
        "RATATOSKR__INGEST__GITHUB_README_SERVICE_SECRET=",
        "# RATATOSKR__INGEST__GITHUB_README_SERVICE_SECRET=",
    );
    assert!(!sets_key(
        &commented,
        "RATATOSKR__INGEST__GITHUB_README_SERVICE_SECRET"
    ));

    let mutated = |repository: &str, relative: &str| {
        let text = read_example(repository, relative);
        if repository == "github" {
            text.replace(
                "RATATOSKR__INTERNAL__READER_SERVICE_SECRET=",
                "RATATOSKR__INTERNAL__READER_SECRET=",
            )
        } else {
            text
        }
    };
    let problems = missing_keys(&mutated, &PAIRS);
    assert_eq!(problems.len(), 1, "{problems:?}");
    assert!(
        problems
            .first()
            .is_some_and(|line| line.starts_with("github:")),
        "{problems:?}"
    );
}
