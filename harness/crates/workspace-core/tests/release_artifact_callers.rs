//! Every pinned repository that ships a systemd unit publishes its artifact through the one
//! reusable workflow (openspec `release-artifacts`): exactly one job calls
//! `po4yka/ratatoskr-workspace/.github/workflows/reusable-release-artifact.yml@<40-hex SHA>`.
//!
//! A repository that copies the steps instead, calls the workflow twice, or follows a moving ref
//! such as `@main` fails here, by name. A repository without a unit, or with template units
//! (`*@.service`) only, is not asked to publish.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

#[path = "support/checkout.rs"]
mod checkout;

use checkout::{committed_manifest, is_checked_out, repository_root, tracked_files};

const CALLEE: &str = "po4yka/ratatoskr-workspace/.github/workflows/reusable-release-artifact.yml@";

#[derive(Debug, PartialEq, Eq)]
struct Calls {
    pinned: usize,
    unpinned: Vec<String>,
}

/// The `uses:` lines of the given workflow files that name the reusable workflow.
fn release_calls(workflows: &[(String, String)]) -> Calls {
    let mut calls = Calls {
        pinned: 0,
        unpinned: Vec::new(),
    };
    for (path, text) in workflows {
        for line in text.lines() {
            let trimmed = line.trim_start().trim_start_matches("- ").trim_start();
            let Some(target) = trimmed.strip_prefix("uses:") else {
                continue;
            };
            let target = target.split_whitespace().next().unwrap_or_default();
            let Some(reference) = target.strip_prefix(CALLEE) else {
                continue;
            };
            if reference.len() == 40 && reference.bytes().all(|b| b.is_ascii_hexdigit()) {
                calls.pinned += 1;
            } else {
                calls.unpinned.push(format!("{path}: @{reference}"));
            }
        }
    }
    calls
}

/// Whether the units a repository ships (paths under `deploy/systemd/`) oblige it to publish. A
/// template unit (`*@.service`) does not: the playbook copies it from the pinned repository, and
/// it starts no binary that the repository builds.
fn publishes(units: &[&str]) -> bool {
    units.iter().any(|unit| !unit.ends_with("@.service"))
}

#[test]
fn every_repository_that_ships_a_unit_publishes_through_the_reusable_workflow() {
    let manifest = committed_manifest();
    let mut failures = Vec::new();
    let mut publishers = 0;
    for repository in manifest.repositories() {
        let root = repository_root(repository);
        assert!(
            is_checked_out(&root),
            "repository `{}` is not checked out at {}; run `git submodule update --init {}`",
            repository.id,
            root.display(),
            repository.path
        );
        let units = tracked_files(&root, "deploy/systemd/*.service");
        if !publishes(
            &units
                .iter()
                .map(|(path, _)| path.as_str())
                .collect::<Vec<_>>(),
        ) {
            continue;
        }
        publishers += 1;
        let calls = release_calls(&tracked_files(&root, ".github/workflows/*.yml"));
        if calls.pinned != 1 || !calls.unpinned.is_empty() {
            failures.push(format!(
                "{}: {} pinned call(s) to the reusable release-artifact workflow, expected exactly 1{}",
                repository.id,
                calls.pinned,
                if calls.unpinned.is_empty() {
                    String::new()
                } else {
                    format!("; not pinned to a commit: {}", calls.unpinned.join(", "))
                }
            ));
        }
    }
    assert!(publishers > 0, "no pinned repository ships a systemd unit");
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn a_repository_that_ships_only_template_units_is_not_asked_to_publish() {
    let template = "deploy/systemd/ratatoskr-notes-cleanup@.service";
    let service = "deploy/systemd/ratatoskr-notes.service";
    assert!(!publishes(&[]));
    assert!(!publishes(&[template]));
    assert!(publishes(&[service]));
    assert!(publishes(&[template, service]));
}

#[test]
fn a_moving_ref_and_a_second_call_are_both_caught() {
    let pinned = format!("{CALLEE}{}", "a".repeat(40));
    let one = vec![(
        "ci.yml".to_owned(),
        format!("jobs:\n  release-artifact:\n    uses: {pinned} # main\n"),
    )];
    assert_eq!(
        release_calls(&one),
        Calls {
            pinned: 1,
            unpinned: Vec::new()
        }
    );

    let moving = vec![(
        "ci.yml".to_owned(),
        format!("jobs:\n  release-artifact:\n    uses: {CALLEE}main\n"),
    )];
    assert_eq!(release_calls(&moving).pinned, 0);
    assert_eq!(release_calls(&moving).unpinned, vec!["ci.yml: @main"]);

    let twice = vec![
        ("ci.yml".to_owned(), format!("    uses: {pinned}\n")),
        (
            "release.yml".to_owned(),
            format!("      - uses: {pinned}\n"),
        ),
    ];
    assert_eq!(release_calls(&twice).pinned, 2);
}
