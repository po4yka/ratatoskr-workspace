//! Materialized baseline safety contract tests.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

mod support;

use support::{GitWorkspace, complete_manifest};
use workspace_core::{inspect_baseline, inspect_git_topology, validate_manifest};

#[test]
fn head_drift_is_reported() {
    let workspace = GitWorkspace::new();
    let pinned = workspace.commit("x").to_owned();
    workspace.advance_head("x");
    let current = workspace.observe_child("x").head;
    let topology = topology(&workspace);

    let report = inspect_baseline(workspace.root(), &topology);

    assert!(
        report.diagnostics.iter().any(|diagnostic| {
            diagnostic.code == "baseline.head-drift"
                && diagnostic.message.contains("`x`")
                && diagnostic.message.contains(&format!("`{pinned}`"))
                && diagnostic.message.contains(&format!("`{current}`"))
        }),
        "HEAD drift diagnostics were incomplete: {:?}",
        report.diagnostics
    );
}

#[test]
fn tracked_and_untracked_changes_are_reported() {
    let workspace = GitWorkspace::new();
    workspace.dirty_child("x");
    let topology = topology(&workspace);

    let report = inspect_baseline(workspace.root(), &topology);

    assert!(report.diagnostics.iter().any(|diagnostic| {
        diagnostic.code == "baseline.tracked-changes"
            && diagnostic.message.contains("`x`")
            && diagnostic.message.contains("README.md")
    }));
    assert!(report.diagnostics.iter().any(|diagnostic| {
        diagnostic.code == "baseline.untracked-changes"
            && diagnostic.message.contains("`x`")
            && diagnostic.message.contains("UNTRACKED.md")
    }));
}

#[test]
fn inspection_never_mutates_a_dirty_child() {
    let workspace = GitWorkspace::new();
    workspace.dirty_child("x");
    let topology = topology(&workspace);
    let before = workspace.observe_child("x");

    let report = inspect_baseline(workspace.root(), &topology);
    let after = workspace.observe_child("x");

    assert!(report.diagnostics.iter().any(|diagnostic| {
        diagnostic.code == "baseline.tracked-changes"
            || diagnostic.code == "baseline.untracked-changes"
    }));
    assert_eq!(after, before, "baseline inspection mutated the child");
}

fn topology(workspace: &GitWorkspace) -> workspace_core::GitTopologyReport {
    let manifest = validate_manifest(&complete_manifest()).expect("valid fleet fixture");
    inspect_git_topology(workspace.root(), &manifest)
}
