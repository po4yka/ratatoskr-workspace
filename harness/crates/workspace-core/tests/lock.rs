//! Deterministic workspace lock contract tests.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

mod support;

use sha2::{Digest as _, Sha256};
use support::{GitWorkspace, REPOSITORY_IDS, complete_manifest};
use workspace_core::{
    WorkspaceLock, compare_workspace_lock, generate_workspace_lock, inspect_git_topology,
    render_workspace_lock, validate_manifest,
};

#[test]
fn same_inputs_render_byte_identically() {
    let first = GitWorkspace::new();
    let second = GitWorkspace::new();

    let first_bytes = generated_lock(&first);
    let second_bytes = generated_lock(&second);

    assert_eq!(first_bytes, second_bytes);
    assert_eq!(Sha256::digest(&first_bytes), Sha256::digest(&second_bytes));
}

#[test]
fn lock_has_stable_lexical_order() {
    let workspace = GitWorkspace::new();
    let source = String::from_utf8(generated_lock(&workspace)).expect("lock is UTF-8");

    let positions = REPOSITORY_IDS
        .iter()
        .map(|identity| {
            source
                .find(&format!("id = \"{identity}\""))
                .expect("repository appears in lock")
        })
        .collect::<Vec<_>>();

    assert!(
        positions
            .windows(2)
            .all(|pair| matches!(pair, [left, right] if left < right))
    );
}

#[test]
fn host_and_time_do_not_enter_lock() {
    let first = GitWorkspace::new();
    let second = GitWorkspace::new();
    let first_source = String::from_utf8(generated_lock(&first)).expect("lock is UTF-8");
    let second_source = String::from_utf8(generated_lock(&second)).expect("lock is UTF-8");

    assert_eq!(first_source, second_source);
    assert!(!first_source.contains(&first.root().display().to_string()));
    assert!(!second_source.contains(&second.root().display().to_string()));
    assert!(!first_source.contains("generated_at"));
    assert!(!first_source.contains("hostname"));
}

#[test]
fn stale_lock_reports_semantic_diff_without_rewrite() {
    let workspace = GitWorkspace::new();
    let expected = lock_model(&workspace);
    let canonical = render_workspace_lock(&expected);
    let stale = canonical.replacen(
        workspace.commit("x"),
        "0000000000000000000000000000000000000000",
        1,
    );
    let lock_path = workspace.root().join("workspace.lock");
    std::fs::write(&lock_path, &stale).expect("write stale lock fixture");
    let before = std::fs::read(&lock_path).expect("read stale lock fixture");

    let diagnostics = compare_workspace_lock(&expected, &stale);
    let after = std::fs::read(&lock_path).expect("read stale lock after comparison");

    assert!(diagnostics.iter().any(|diagnostic| {
        diagnostic.code == "lock.repository.commit"
            && diagnostic.message.contains("`x`")
            && diagnostic.message.contains(workspace.commit("x"))
            && diagnostic
                .message
                .contains("0000000000000000000000000000000000000000")
    }));
    assert_eq!(after, before, "lock check rewrote committed output");
}

fn generated_lock(workspace: &GitWorkspace) -> Vec<u8> {
    render_workspace_lock(&lock_model(workspace)).into_bytes()
}

fn lock_model(workspace: &GitWorkspace) -> WorkspaceLock {
    let source = complete_manifest();
    let manifest = validate_manifest(&source).expect("valid fleet fixture");
    let topology = inspect_git_topology(workspace.root(), &manifest);
    generate_workspace_lock(workspace.root(), &source, &manifest, &topology)
        .expect("generate deterministic lock")
}
