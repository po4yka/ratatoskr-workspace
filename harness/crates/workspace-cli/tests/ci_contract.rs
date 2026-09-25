//! Hosted workspace snapshot gate contract tests.

#![allow(clippy::expect_used, clippy::panic)]

use std::fs;
use std::path::{Path, PathBuf};

#[test]
fn workspace_ci_initializes_and_verifies_snapshot() {
    let workflow = workflow();

    assert!(workflow.contains("submodules: recursive"));
    assert!(workflow.contains("fetch-depth: 0"));
    assert!(workflow.contains("./ws lock check"));
    assert!(workflow.contains("./ws doctor"));
    assert!(workflow.contains("harness/rust-toolchain.toml"));
    assert!(workflow.contains("cargo fmt --all -- --check"));
    assert!(workflow.contains("cargo clippy --workspace --all-targets --all-features --locked"));
    assert!(workflow.contains("cargo test --workspace --all-features --locked"));
    assert!(workflow.contains("cargo deny check"));
}

fn workflow() -> String {
    fs::read_to_string(workspace_root().join(".github/workflows/ci.yml"))
        .expect("workspace CI workflow exists")
}

fn workspace_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(3)
        .expect("workspace root ancestor")
        .to_owned()
}
