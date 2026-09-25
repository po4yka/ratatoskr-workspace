//! Operator command contract tests.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

#[path = "../../workspace-core/tests/support/mod.rs"]
mod support;

#[path = "../../workspace-core/tests/support/fleet.rs"]
mod fleet_support;

use fleet_support::{FleetFixture, SourceLayout, content, write};
use std::fs;
use std::path::Path;
use std::process::{Command, Output};
use support::{GitWorkspace, complete_manifest};
use workspace_core::{
    generate_workspace_lock, inspect_git_topology, render_workspace_lock, validate_manifest,
};

#[test]
fn manifest_check_is_read_only() {
    let workspace = GitWorkspace::new();
    write_manifest(&workspace);
    let before_child = workspace.observe_child("x");
    let before_index = fs::read(workspace.root().join(".git/index")).expect("read fixture index");
    let before_modules = fs::read(workspace.root().join(".gitmodules")).expect("read modules");

    let output = ws(&workspace, &["manifest", "check"]);

    assert_success(&output);
    assert!(String::from_utf8_lossy(&output.stdout).contains("manifest: valid"));
    assert_eq!(workspace.observe_child("x"), before_child);
    assert_eq!(
        fs::read(workspace.root().join(".git/index")).expect("reread fixture index"),
        before_index
    );
    assert_eq!(
        fs::read(workspace.root().join(".gitmodules")).expect("reread modules"),
        before_modules
    );
}

#[test]
fn lock_check_rejects_stale_output() {
    let workspace = GitWorkspace::new();
    write_manifest(&workspace);
    let canonical = canonical_lock(&workspace);
    let stale = canonical.replacen(
        workspace.commit("x"),
        "0000000000000000000000000000000000000000",
        1,
    );
    fs::write(workspace.root().join("workspace.lock"), &stale).expect("write stale lock");

    let output = ws(&workspace, &["lock", "check"]);

    assert_eq!(output.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&output.stderr).contains("lock.repository.commit"));
    assert_eq!(
        fs::read_to_string(workspace.root().join("workspace.lock")).expect("reread stale lock"),
        stale
    );
}

#[test]
fn status_reports_without_repair() {
    let workspace = GitWorkspace::new();
    write_manifest(&workspace);
    workspace.advance_head("x");
    workspace.dirty_child("x");
    let before = workspace.observe_child("x");

    let output = ws(&workspace, &["status"]);

    assert_success(&output);
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("baseline.head-drift"));
    assert!(stdout.contains("baseline.tracked-changes"));
    assert!(stdout.contains("baseline.untracked-changes"));
    assert_eq!(workspace.observe_child("x"), before);
}

#[test]
fn doctor_aggregates_snapshot_failures() {
    let workspace = GitWorkspace::new();
    write_manifest(&workspace);
    let stale = canonical_lock(&workspace).replacen(
        workspace.commit("x"),
        "0000000000000000000000000000000000000000",
        1,
    );
    fs::write(workspace.root().join("workspace.lock"), stale).expect("write stale lock");
    workspace.dirty_child("x");

    let output = ws(&workspace, &["doctor"]);

    assert_eq!(output.status.code(), Some(2));
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("baseline.tracked-changes"));
    assert!(stderr.contains("baseline.untracked-changes"));
    assert!(stderr.contains("lock.repository.commit"));
}

#[test]
fn uninitialized_output_names_exact_bootstrap_command() {
    let workspace = GitWorkspace::new();
    write_manifest(&workspace);
    workspace.make_uninitialized("x");

    let output = ws(&workspace, &["doctor"]);

    assert_eq!(output.status.code(), Some(2));
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("topology.submodule-uninitialized"));
    assert!(stderr.contains("repository `x`"));
    assert!(stderr.contains("git submodule update --init --recursive"));
}

#[test]
fn fleet_init_copies_and_reports_missing_files() {
    let fixture = FleetFixture::new();
    let source = fixture.source(SourceLayout::RustAtRoot);
    let target = fixture.target(true);

    let output = ws_at(&source, &["fleet", "init", path_arg(&target)]);

    assert_success(&output);
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("fleet: Rust target"), "{stdout}");
    assert!(
        stdout.contains("fleet: copied .githooks/pre-commit"),
        "{stdout}"
    );
    assert!(
        stdout
            .contains("fleet: absent from the source: .github/workflows/dependabot-automerge.yml"),
        "{stdout}"
    );
    assert!(
        stdout.contains("fleet: still missing, write by hand: SECURITY.md"),
        "{stdout}"
    );
    assert!(
        stdout.contains("fleet: still missing, write by hand: clippy.toml"),
        "{stdout}"
    );
    assert_eq!(
        fs::read_to_string(target.join(".githooks/pre-commit")).expect("hook was copied"),
        content(".githooks/pre-commit")
    );
}

#[test]
fn fleet_init_conflict_exits_with_validation_status() {
    let fixture = FleetFixture::new();
    let source = fixture.source(SourceLayout::RustAtRoot);
    let target = fixture.target(true);
    write(&target, "LICENSE", "a different licence\n");
    let arguments = [
        "fleet",
        "init",
        path_arg(&target),
        "--from",
        path_arg(&source),
    ];

    let refused = ws_at(&target, &arguments);

    assert_eq!(refused.status.code(), Some(2));
    let stderr = String::from_utf8_lossy(&refused.stderr);
    assert!(stderr.contains("fleet.conflict"), "{stderr}");
    assert!(stderr.contains("`LICENSE`"), "{stderr}");
    assert_eq!(
        fs::read_to_string(target.join("LICENSE")).expect("licence is kept"),
        "a different licence\n"
    );

    let forced = ws_at(&target, &[&arguments[..], &["--force"]].concat());

    assert_success(&forced);
    assert_eq!(
        fs::read_to_string(target.join("LICENSE")).expect("licence is replaced"),
        content("LICENSE")
    );
}

fn path_arg(path: &Path) -> &str {
    path.to_str().expect("fixture path is UTF-8")
}

fn ws_at(root: &Path, arguments: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_workspace-cli"))
        .args(arguments)
        .current_dir(root)
        .env_remove("RATATOSKR_WORKSPACE_ROOT")
        .output()
        .expect("run workspace CLI")
}

fn write_manifest(workspace: &GitWorkspace) {
    fs::write(workspace.root().join("workspace.toml"), complete_manifest())
        .expect("write workspace manifest");
}

fn canonical_lock(workspace: &GitWorkspace) -> String {
    let source = complete_manifest();
    let manifest = validate_manifest(&source).expect("valid fleet fixture");
    let topology = inspect_git_topology(workspace.root(), &manifest);
    let lock = generate_workspace_lock(workspace.root(), &source, &manifest, &topology)
        .expect("generate lock fixture");
    render_workspace_lock(&lock)
}

fn ws(workspace: &GitWorkspace, arguments: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_workspace-cli"))
        .args(arguments)
        .current_dir(workspace.root())
        .output()
        .expect("run workspace CLI")
}

fn assert_success(output: &Output) {
    assert!(
        output.status.success(),
        "command failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
}
