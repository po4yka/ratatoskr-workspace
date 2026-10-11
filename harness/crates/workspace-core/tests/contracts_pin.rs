//! One contracts revision: every Rust repository that depends on the contracts repository resolves every `ratatoskr-*` git package to the same commit, and that commit is the one the changeset `XR-021-fleet-cross-repo-fixes` names as `contracts_sha` (XR-021 CONTRACTS R3-16).
//!
//! Cargo treats two revisions of one git repository as two different crates, so a repository that locks a different revision builds against types its neighbours do not share. The check reads the tracked `Cargo.lock` files of the pinned checkouts, which is what `cargo build --locked` uses.
//!
//! Limitation, stated plainly. This is a text scan of `Cargo.lock`. It sees a package whose `source` line names the contracts repository and takes the commit after the `#`; it cannot see a contracts crate vendored by path, a lock that is stale against its manifest (CI's `--locked` build is what catches that), or a repository that depends on the contracts through a mirror URL. The mutation test at the bottom proves that the scan reports a package locked to another commit.
//!
//! Real sample at the round 3 pins: each lock line looks like `source = "git+https://github.com/po4yka/ratatoskr-contracts.git?rev=<sha>#<sha>"` and every contracts package of a repository carries the same `<sha>`.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

#[path = "support/checkout.rs"]
mod checkout;

use checkout::{committed_manifest, repository_root, tracked_files, workspace_root};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;

const CONTRACTS_REMOTE: &str = "git+https://github.com/po4yka/ratatoskr-contracts";
const CHANGESET: &str = "changesets/XR-021-fleet-cross-repo-fixes.yaml";

/// `(package name, commit)` of every `ratatoskr-*` package of a lock that comes from the contracts repository.
fn contracts_packages(lock: &str) -> Vec<(String, String)> {
    let mut found = Vec::new();
    for block in lock.split("[[package]]").skip(1) {
        let mut name = None;
        let mut source = None;
        for line in block.lines() {
            let line = line.trim();
            if let Some(value) = line.strip_prefix("name = ") {
                name = Some(value.trim_matches('"').to_owned());
            } else if let Some(value) = line.strip_prefix("source = ") {
                source = Some(value.trim_matches('"').to_owned());
            }
        }
        let (Some(name), Some(source)) = (name, source) else {
            continue;
        };
        if !name.starts_with("ratatoskr-") || !source.starts_with(CONTRACTS_REMOTE) {
            continue;
        }
        let commit = source
            .rsplit_once('#')
            .map_or_else(String::new, |(_, commit)| commit.to_owned());
        found.push((name, commit));
    }
    found
}

/// The revision the changeset names: the `contracts_sha:` line under `contracts:`.
fn named_revision() -> String {
    let path = workspace_root().join(CHANGESET);
    let text = fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("read {}: {error}", path.display()));
    let line = text
        .lines()
        .find_map(|line| line.trim().strip_prefix("contracts_sha:"))
        .unwrap_or_else(|| panic!("{CHANGESET} has no contracts_sha line"));
    line.trim().to_owned()
}

/// Every contracts commit each repository's locks resolve, keyed by `repository:lockfile`.
fn locked_commits() -> BTreeMap<String, BTreeSet<String>> {
    let manifest = committed_manifest();
    let mut commits = BTreeMap::new();
    for repository in manifest.repositories() {
        if repository.id == "contracts" {
            continue;
        }
        let root = repository_root(repository);
        assert!(
            root.join(".git").exists(),
            "repository `{}` is not checked out at {}",
            repository.id,
            root.display()
        );
        for (path, lock) in tracked_files(&root, "Cargo.lock") {
            let set = contracts_packages(&lock)
                .into_iter()
                .map(|(_, commit)| commit)
                .collect::<BTreeSet<_>>();
            if !set.is_empty() {
                commits.insert(format!("{}:{path}", repository.id), set);
            }
        }
    }
    commits
}

/// Disagreements with the named revision, one line each.
fn pin_problems(commits: &BTreeMap<String, BTreeSet<String>>, named: &str) -> Vec<String> {
    let mut problems = Vec::new();
    for (lock, set) in commits {
        if set.len() != 1 {
            problems.push(format!(
                "{lock} resolves {} contracts revisions: {set:?}",
                set.len()
            ));
        }
        for commit in set {
            if commit != named {
                problems.push(format!(
                    "{lock} locks the contracts at {commit}, the changeset names {named}"
                ));
            }
        }
    }
    problems
}

#[test]
fn every_rust_repository_resolves_one_contracts_revision() {
    let named = named_revision();
    assert_eq!(
        named.len(),
        40,
        "the changeset must name a full 40-character SHA"
    );
    let commits = locked_commits();
    assert!(
        commits.len() >= 10,
        "expected the Rust repositories to carry contracts locks, found {}: {:?}",
        commits.len(),
        commits.keys().collect::<Vec<_>>()
    );
    let problems = pin_problems(&commits, &named);
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn the_scan_reports_a_package_locked_to_another_commit() {
    let named = "a".repeat(40);
    let other = "b".repeat(40);
    let lock = |commit: &str| {
        format!(
            "[[package]]\nname = \"ratatoskr-identifiers\"\nversion = \"0.1.0\"\nsource = \"{CONTRACTS_REMOTE}.git?rev={commit}#{commit}\"\n\n\
             [[package]]\nname = \"serde\"\nversion = \"1.0.0\"\nsource = \"registry+https://github.com/rust-lang/crates.io-index\"\n"
        )
    };
    let clean = BTreeMap::from([(
        "r:Cargo.lock".to_owned(),
        contracts_packages(&lock(&named))
            .into_iter()
            .map(|(_, commit)| commit)
            .collect::<BTreeSet<_>>(),
    )]);
    assert!(pin_problems(&clean, &named).is_empty());

    let drifted = BTreeMap::from([(
        "r:Cargo.lock".to_owned(),
        contracts_packages(&lock(&other))
            .into_iter()
            .map(|(_, commit)| commit)
            .collect::<BTreeSet<_>>(),
    )]);
    let problems = pin_problems(&drifted, &named);
    assert_eq!(problems.len(), 1, "{problems:?}");

    let mixed = format!("{}{}", lock(&named), lock(&other));
    let set = contracts_packages(&mixed)
        .into_iter()
        .map(|(_, commit)| commit)
        .collect::<BTreeSet<_>>();
    assert_eq!(set.len(), 2, "a lock with two revisions must show both");
}
