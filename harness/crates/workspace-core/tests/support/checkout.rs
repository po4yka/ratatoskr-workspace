//! Access to the real workspace checkout for tests that read the pinned child repositories.

use std::path::{Path, PathBuf};
use workspace_core::{ManifestRepository, ValidatedManifest, validate_manifest};

/// Root of the real workspace, three levels above `harness/crates/workspace-core`.
pub(crate) fn workspace_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(3)
        .expect("workspace root ancestor")
        .to_owned()
}

/// The committed `workspace.toml`, validated.
pub(crate) fn committed_manifest() -> ValidatedManifest {
    let source = std::fs::read_to_string(workspace_root().join("workspace.toml"))
        .expect("committed workspace.toml exists");
    validate_manifest(&source).expect("committed manifest is valid")
}

/// Whether the child repository is materialized (a submodule has a `.git` file, a clone a directory).
pub(crate) fn is_checked_out(root: &Path) -> bool {
    root.join(".git").exists()
}

/// The checkout path of a manifest repository.
pub(crate) fn repository_root(repository: &ManifestRepository) -> PathBuf {
    workspace_root().join(&repository.path)
}

/// The checkout path of a repository by identity, failing loudly when it is not materialized.
///
/// A skipped check passes in exactly the environment where nobody looked, so a missing owner
/// repository is an error here, not a skip.
pub(crate) fn require_checkout(manifest: &ValidatedManifest, id: &str) -> PathBuf {
    let repository = manifest
        .repositories()
        .iter()
        .find(|repository| repository.id == id)
        .unwrap_or_else(|| panic!("repository `{id}` is not in workspace.toml"));
    let root = repository_root(repository);
    assert!(
        is_checked_out(&root),
        "repository `{id}` is not checked out at {}; run `git submodule update --init {}`",
        root.display(),
        repository.path
    );
    root
}
