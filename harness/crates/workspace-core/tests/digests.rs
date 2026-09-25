//! Pinned Git content evidence contract tests.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

mod support;

use support::{GitWorkspace, complete_manifest, repository, repository_with_digest_inputs};
use workspace_core::{
    WorkspaceLock, generate_workspace_lock, inspect_git_topology, validate_manifest,
};

#[test]
fn file_digest_reads_pinned_blob() {
    let first = GitWorkspace::new();
    let mut second = GitWorkspace::new();
    second.add_files_and_repin("x", &[("README.md", b"changed blob\n")]);
    let source = manifest_with_x_inputs(&["README.md"]);

    let first_lock = lock_model(&first, &source).expect("digest first file");
    let second_lock = lock_model(&second, &source).expect("digest changed file");

    assert_ne!(
        x_digest(&first_lock, "README.md"),
        x_digest(&second_lock, "README.md")
    );
}

#[test]
fn directory_digest_is_canonical() {
    let mut first = GitWorkspace::new();
    let mut second = GitWorkspace::new();
    first.add_files_and_repin(
        "x",
        &[("evidence/b.txt", b"b\n"), ("evidence/a.txt", b"a\n")],
    );
    second.add_files_and_repin(
        "x",
        &[("evidence/a.txt", b"a\n"), ("evidence/b.txt", b"b\n")],
    );
    let source = manifest_with_x_inputs(&["evidence"]);

    let first_lock = lock_model(&first, &source).expect("digest first tree");
    let second_lock = lock_model(&second, &source).expect("digest second tree");
    let first_digest = x_digest(&first_lock, "evidence");
    let second_digest = x_digest(&second_lock, "evidence");

    assert_eq!(first_digest.kind, "tree");
    assert_eq!(first_digest, second_digest);
}

#[test]
fn missing_declared_path_fails() {
    let workspace = GitWorkspace::new();
    let source = manifest_with_x_inputs(&["missing.txt"]);

    let diagnostics = lock_model(&workspace, &source).expect_err("missing input was accepted");

    assert!(diagnostics.iter().any(|diagnostic| {
        diagnostic.code == "digest.missing" && diagnostic.message.contains("missing.txt")
    }));
}

#[test]
fn path_escape_fails() {
    let workspace = GitWorkspace::new();
    let source = manifest_with_x_inputs(&["../outside"]);

    let diagnostics = lock_model(&workspace, &source).expect_err("path escape was accepted");

    assert!(diagnostics.iter().any(|diagnostic| {
        diagnostic.code == "digest.path-unsafe" && diagnostic.message.contains("../outside")
    }));
}

#[test]
fn non_blob_entries_fail_closed() {
    let mut workspace = GitWorkspace::new();
    workspace.add_symlink_and_repin("x", "evidence-link", "README.md");
    let source = manifest_with_x_inputs(&["evidence-link"]);

    let diagnostics = lock_model(&workspace, &source).expect_err("symlink input was accepted");

    assert!(diagnostics.iter().any(|diagnostic| {
        diagnostic.code == "digest.unsupported-type"
            && diagnostic.message.contains("evidence-link")
            && diagnostic.message.contains("symbolic links")
    }));
}

fn manifest_with_x_inputs(inputs: &[&str]) -> String {
    complete_manifest().replace(
        &repository("x"),
        &repository_with_digest_inputs("x", inputs),
    )
}

fn lock_model(
    workspace: &GitWorkspace,
    source: &str,
) -> Result<WorkspaceLock, Vec<workspace_core::ManifestDiagnostic>> {
    let manifest = validate_manifest(source).expect("valid digest manifest fixture");
    let topology = inspect_git_topology(workspace.root(), &manifest);
    generate_workspace_lock(workspace.root(), source, &manifest, &topology)
}

fn x_digest<'a>(lock: &'a WorkspaceLock, path: &str) -> &'a workspace_core::LockDigest {
    lock.repositories
        .iter()
        .find(|repository| repository.id == "x")
        .and_then(|repository| repository.digests.iter().find(|digest| digest.path == path))
        .expect("x digest exists")
}
