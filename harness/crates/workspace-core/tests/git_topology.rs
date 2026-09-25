//! Superproject Git topology contract tests.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

mod support;

use support::{GitWorkspace, complete_manifest};
use workspace_core::{inspect_git_topology, validate_manifest};

#[test]
fn manifest_gitmodules_and_gitlinks_agree() {
    let workspace = GitWorkspace::new();
    let manifest = validate_manifest(&complete_manifest()).expect("valid fleet fixture");

    let report = inspect_git_topology(workspace.root(), &manifest);

    assert!(
        report.diagnostics.is_empty(),
        "matching topology was rejected: {:?}",
        report.diagnostics
    );
    assert_eq!(report.pins.len(), 16);
    assert!(report.pins.iter().all(|pin| {
        pin.commit.len() == 40
            && pin.initialized
            && pin.reachable
            && pin.commit == workspace.commit(&pin.id)
    }));
}

#[test]
fn path_remote_and_mode_mismatches_are_reported() {
    let workspace = GitWorkspace::new();
    workspace.set_gitmodule(
        "x",
        "repos/wrong-x",
        "ssh://git@github.com/po4yka/ratatoskr-x.git",
    );
    workspace.replace_gitlink_with_regular_mode("x");
    let manifest = validate_manifest(&complete_manifest()).expect("valid fleet fixture");

    let report = inspect_git_topology(workspace.root(), &manifest);

    assert!(report.diagnostics.iter().any(|diagnostic| {
        diagnostic.code == "topology.path-mismatch"
            && diagnostic.message.contains("`repos/x`")
            && diagnostic.message.contains("`repos/wrong-x`")
    }));
    assert!(report.diagnostics.iter().any(|diagnostic| {
        diagnostic.code == "topology.remote-mismatch"
            && diagnostic
                .message
                .contains("`https://github.com/po4yka/ratatoskr-x.git`")
            && diagnostic
                .message
                .contains("`ssh://git@github.com/po4yka/ratatoskr-x.git`")
    }));
    assert!(report.diagnostics.iter().any(|diagnostic| {
        diagnostic.code == "topology.mode-mismatch"
            && diagnostic.message.contains("`100644`")
            && diagnostic.message.contains("`160000`")
    }));
}

#[test]
fn uninitialized_submodule_reports_bootstrap_command() {
    let workspace = GitWorkspace::new();
    workspace.make_uninitialized("x");
    let manifest = validate_manifest(&complete_manifest()).expect("valid fleet fixture");

    let report = inspect_git_topology(workspace.root(), &manifest);

    assert!(report.diagnostics.iter().any(|diagnostic| {
        diagnostic.code == "topology.submodule-uninitialized"
            && diagnostic.message.contains("`x`")
            && diagnostic
                .message
                .contains("git submodule update --init --recursive")
    }));
}
