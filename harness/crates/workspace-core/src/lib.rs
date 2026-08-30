//! Semantic workspace manifest and snapshot validation.

#![forbid(unsafe_code)]
#![deny(rustdoc::broken_intra_doc_links)]

use serde::Deserialize;
use sha2::{Digest as _, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::{self, OpenOptions};
use std::io::{self, Write as _};
use std::path::{Component, Path};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_LOCK_WRITE: AtomicU64 = AtomicU64::new(1);

const REQUIRED_REPOSITORIES: [&str; 16] = [
    "browser-extension",
    "chatgpt",
    "claude",
    "contracts",
    "export-agent",
    "extractor",
    "github",
    "instagram",
    "knowledge",
    "mobile",
    "platform",
    "telegram",
    "threads",
    "vault",
    "web",
    "x",
];

/// One stable manifest validation failure.
#[derive(Debug, Eq, PartialEq)]
pub struct ManifestDiagnostic {
    /// Machine-readable diagnostic identifier.
    pub code: &'static str,
    /// Human-readable explanation without machine-local paths.
    pub message: String,
}

/// A parsed and validated workspace manifest.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ValidatedManifest {
    format_version: u32,
    repositories: Vec<ManifestRepository>,
}

impl ValidatedManifest {
    /// Returns the number of repositories declared by the manifest.
    #[must_use]
    pub fn repository_count(&self) -> usize {
        self.repositories.len()
    }

    /// Returns the manifest format version.
    #[must_use]
    pub const fn format_version(&self) -> u32 {
        self.format_version
    }

    /// Returns the repositories in manifest order.
    #[must_use]
    pub fn repositories(&self) -> &[ManifestRepository] {
        &self.repositories
    }
}

/// Semantic configuration for one product repository.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ManifestRepository {
    /// Stable fleet-wide repository identity.
    pub id: String,
    /// Gitlink path relative to the workspace root.
    pub path: String,
    /// Canonical public HTTPS remote.
    pub remote: String,
    /// Repository default branch.
    pub default_branch: String,
    /// Repository role in the fleet.
    pub kind: String,
    /// Repository owner.
    pub owner: String,
    /// Security classification.
    pub security: String,
    /// Supported workspace command names.
    pub commands: Vec<String>,
    /// Published or consumed contract identifiers.
    pub contracts: Vec<String>,
    /// Integration profiles that include the repository.
    pub profiles: Vec<String>,
    /// Git paths included in compatibility evidence.
    pub digest_inputs: Vec<String>,
    /// Typed dependencies on other fleet repositories.
    pub dependencies: Vec<ManifestDependency>,
}

/// One directed dependency between fleet repositories.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ManifestDependency {
    /// Referenced repository identity.
    pub repository: String,
    /// Dependency category.
    pub kind: String,
    /// Human-readable reason for the edge.
    pub purpose: String,
}

/// One repository pin discovered in the superproject Git index.
#[derive(Debug, Eq, PartialEq)]
pub struct GitPin {
    /// Manifest repository identity.
    pub id: String,
    /// Gitlink path relative to the workspace root.
    pub path: String,
    /// Canonical remote declared by `.gitmodules`.
    pub remote: String,
    /// Full forty-character gitlink commit.
    pub commit: String,
    /// Whether the child repository is materialized locally.
    pub initialized: bool,
    /// Whether the pinned commit exists in the materialized child object database.
    pub reachable: bool,
}

/// Read-only comparison of manifest, `.gitmodules`, gitlinks, and materialized children.
#[derive(Debug, Eq, PartialEq)]
pub struct GitTopologyReport {
    /// Pins joined successfully across the three workspace authorities.
    pub pins: Vec<GitPin>,
    /// Stable mismatch and materialization diagnostics.
    pub diagnostics: Vec<ManifestDiagnostic>,
}

/// Read-only health report for initialized baseline repositories.
#[derive(Debug, Eq, PartialEq)]
pub struct BaselineReport {
    /// Stable drift and dirty-state diagnostics.
    pub diagnostics: Vec<ManifestDiagnostic>,
}

/// Deterministic derived evidence for one workspace snapshot.
#[derive(Debug, Deserialize, Eq, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct WorkspaceLock {
    /// Lock format version.
    pub format_version: u32,
    /// SHA-256 of normalized semantic manifest bytes.
    pub manifest_sha256: String,
    /// SHA-256 of normalized `.gitmodules` bytes.
    pub gitmodules_sha256: String,
    /// Repository pins in lexical identity order.
    pub repositories: Vec<LockRepository>,
}

/// Derived pin and compatibility evidence for one repository.
#[derive(Debug, Deserialize, Eq, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct LockRepository {
    /// Stable repository identity.
    pub id: String,
    /// Gitlink path.
    pub path: String,
    /// Canonical public remote.
    pub remote: String,
    /// Default branch recorded for operator context.
    pub default_branch: String,
    /// Exact full gitlink commit.
    pub commit: String,
    /// Content digests in lexical path order.
    pub digests: Vec<LockDigest>,
}

/// SHA-256 evidence for one declared file or directory.
#[derive(Debug, Deserialize, Eq, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct LockDigest {
    /// Git path relative to the child repository root.
    pub path: String,
    /// Git object kind (`file` or `tree`).
    pub kind: String,
    /// Lower-case SHA-256 evidence digest.
    pub sha256: String,
}

/// Parses and validates a semantic workspace manifest.
///
/// # Errors
///
/// Returns every stable validation diagnostic when the document is invalid.
pub fn validate_manifest(source: &str) -> Result<ValidatedManifest, Vec<ManifestDiagnostic>> {
    let document = toml::from_str::<ValidatedManifest>(source).map_err(|error| {
        vec![ManifestDiagnostic {
            code: "manifest.parse",
            message: error.to_string(),
        }]
    })?;

    let mut diagnostics = Vec::new();
    if document.format_version != 1 {
        diagnostics.push(ManifestDiagnostic {
            code: "manifest.format-version",
            message: format!(
                "unsupported manifest format version `{}`; expected `1`",
                document.format_version
            ),
        });
    }

    diagnostics.extend(duplicate_diagnostics(
        &document.repositories,
        |repository| &repository.id,
        "manifest.repository.duplicate",
        "repository identity",
    ));
    diagnostics.extend(duplicate_diagnostics(
        &document.repositories,
        |repository| &repository.path,
        "manifest.repository.path-duplicate",
        "repository path",
    ));
    diagnostics.extend(duplicate_diagnostics(
        &document.repositories,
        |repository| &repository.remote,
        "manifest.repository.remote-duplicate",
        "repository remote",
    ));

    let identities = document
        .repositories
        .iter()
        .map(|repository| repository.id.as_str())
        .collect::<BTreeSet<_>>();
    diagnostics.extend(
        REQUIRED_REPOSITORIES
            .iter()
            .filter(|identity| !identities.contains(**identity))
            .map(|identity| ManifestDiagnostic {
                code: "manifest.repository.missing",
                message: format!("required repository `{identity}` is absent"),
            }),
    );
    diagnostics.extend(
        identities
            .iter()
            .filter(|identity| !REQUIRED_REPOSITORIES.contains(identity))
            .map(|identity| ManifestDiagnostic {
                code: "manifest.repository.unexpected",
                message: format!("repository `{identity}` is not part of the required fleet"),
            }),
    );

    if !diagnostics.is_empty() {
        return Err(diagnostics);
    }

    Ok(document)
}

/// Returns a deterministic dependency-first repository order.
///
/// # Errors
///
/// Returns stable diagnostics when an edge references an unknown repository or the graph contains
/// a cycle.
pub fn dependency_order(
    manifest: &ValidatedManifest,
) -> Result<Vec<String>, Vec<ManifestDiagnostic>> {
    let mut incoming = manifest
        .repositories
        .iter()
        .map(|repository| (repository.id.as_str(), 0_usize))
        .collect::<BTreeMap<_, _>>();
    let mut dependents = BTreeMap::<&str, Vec<&str>>::new();

    let unknown_dependencies = manifest
        .repositories
        .iter()
        .flat_map(|repository| {
            repository
                .dependencies
                .iter()
                .filter(|dependency| !incoming.contains_key(dependency.repository.as_str()))
                .map(|dependency| ManifestDiagnostic {
                    code: "manifest.dependency.unknown",
                    message: format!(
                        "repository `{}` depends on unknown repository `{}`",
                        repository.id, dependency.repository
                    ),
                })
        })
        .collect::<Vec<_>>();
    if !unknown_dependencies.is_empty() {
        return Err(unknown_dependencies);
    }

    for repository in &manifest.repositories {
        for dependency in &repository.dependencies {
            if let Some(count) = incoming.get_mut(repository.id.as_str()) {
                *count += 1;
            }
            dependents
                .entry(dependency.repository.as_str())
                .or_default()
                .push(repository.id.as_str());
        }
    }

    let mut ready = incoming
        .iter()
        .filter_map(|(identity, count)| (*count == 0).then_some(*identity))
        .collect::<BTreeSet<_>>();
    let mut order = Vec::with_capacity(manifest.repositories.len());
    while let Some(identity) = ready.pop_first() {
        order.push(identity.to_owned());
        if let Some(next_repositories) = dependents.get(identity) {
            for next in next_repositories {
                if let Some(count) = incoming.get_mut(next) {
                    *count -= 1;
                    if *count == 0 {
                        ready.insert(next);
                    }
                }
            }
        }
    }

    if order.len() != manifest.repositories.len() {
        let repositories_by_id = manifest
            .repositories
            .iter()
            .map(|repository| (repository.id.as_str(), repository))
            .collect::<BTreeMap<_, _>>();
        let cycle = repositories_by_id
            .keys()
            .copied()
            .filter(|identity| repository_is_in_cycle(identity, &repositories_by_id))
            .map(|identity| format!("`{identity}`"))
            .collect::<Vec<_>>()
            .join(", ");
        return Err(vec![ManifestDiagnostic {
            code: "manifest.dependency.cycle",
            message: format!("dependency cycle contains repositories: {cycle}"),
        }]);
    }

    Ok(order)
}

/// Inspects workspace Git topology without fetching, checking out, or repairing repositories.
#[must_use]
pub fn inspect_git_topology(
    workspace_root: &Path,
    manifest: &ValidatedManifest,
) -> GitTopologyReport {
    let Some(gitmodules) = read_gitmodules(workspace_root) else {
        return topology_unimplemented();
    };
    let Some(gitlinks) = read_gitlinks(workspace_root) else {
        return topology_unimplemented();
    };

    let mut inspector = TopologyInspector {
        workspace_root,
        gitmodules: &gitmodules,
        gitlinks: &gitlinks,
        pins: Vec::with_capacity(manifest.repositories.len()),
        diagnostics: Vec::new(),
    };
    for repository in &manifest.repositories {
        inspector.inspect(repository);
    }

    GitTopologyReport {
        pins: inspector.pins,
        diagnostics: inspector.diagnostics,
    }
}

/// Inspects child HEAD and worktree state without modifying a repository.
#[must_use]
pub fn inspect_baseline(workspace_root: &Path, topology: &GitTopologyReport) -> BaselineReport {
    let mut diagnostics = Vec::new();
    for pin in &topology.pins {
        let Some(head) = git_output(
            workspace_root,
            &["-C", pin.path.as_str(), "rev-parse", "HEAD"],
        )
        .map(|output| output.trim().to_owned()) else {
            diagnostics.push(ManifestDiagnostic {
                code: "baseline.git-error",
                message: format!("repository `{}` HEAD could not be inspected", pin.id),
            });
            continue;
        };
        if head != pin.commit {
            diagnostics.push(ManifestDiagnostic {
                code: "baseline.head-drift",
                message: format!(
                    "repository `{}` is at `{head}` but the gitlink pins `{}`",
                    pin.id, pin.commit
                ),
            });
        }

        let Some(status) = git_output(
            workspace_root,
            &[
                "-C",
                pin.path.as_str(),
                "status",
                "--porcelain=v1",
                "-z",
                "--untracked-files=all",
            ],
        ) else {
            diagnostics.push(ManifestDiagnostic {
                code: "baseline.git-error",
                message: format!("repository `{}` status could not be inspected", pin.id),
            });
            continue;
        };
        let (tracked, untracked) = classify_status(&status);
        if !tracked.is_empty() {
            diagnostics.push(ManifestDiagnostic {
                code: "baseline.tracked-changes",
                message: format!(
                    "repository `{}` has tracked changes: {}",
                    pin.id,
                    tracked.join(", ")
                ),
            });
        }
        if !untracked.is_empty() {
            diagnostics.push(ManifestDiagnostic {
                code: "baseline.untracked-changes",
                message: format!(
                    "repository `{}` has untracked paths: {}",
                    pin.id,
                    untracked.join(", ")
                ),
            });
        }
    }

    BaselineReport { diagnostics }
}

/// Derives a deterministic lock model from committed workspace authorities.
///
/// # Errors
///
/// Returns stable diagnostics when an authority cannot be read or joined.
pub fn generate_workspace_lock(
    workspace_root: &Path,
    manifest_source: &str,
    manifest: &ValidatedManifest,
    topology: &GitTopologyReport,
) -> Result<WorkspaceLock, Vec<ManifestDiagnostic>> {
    if !topology.diagnostics.is_empty() || topology.pins.len() != manifest.repositories.len() {
        return Err(vec![ManifestDiagnostic {
            code: "lock.topology-invalid",
            message: "workspace topology must be valid before lock generation".to_owned(),
        }]);
    }
    let gitmodules_source =
        fs::read_to_string(workspace_root.join(".gitmodules")).map_err(|error| {
            vec![ManifestDiagnostic {
                code: "lock.gitmodules-read",
                message: format!("`.gitmodules` could not be read: {error}"),
            }]
        })?;
    let pins = topology
        .pins
        .iter()
        .map(|pin| (pin.id.as_str(), pin))
        .collect::<BTreeMap<_, _>>();
    let mut repositories = Vec::with_capacity(manifest.repositories.len());
    let mut digest_diagnostics = Vec::new();
    for repository in &manifest.repositories {
        let Some(pin) = pins.get(repository.id.as_str()) else {
            continue;
        };
        let mut inputs = repository.digest_inputs.iter().collect::<Vec<_>>();
        inputs.sort();
        let mut digests = Vec::with_capacity(inputs.len());
        for input in inputs {
            match digest_git_input(workspace_root, repository, &pin.commit, input) {
                Ok(digest) => digests.push(digest),
                Err(diagnostic) => digest_diagnostics.push(diagnostic),
            }
        }
        repositories.push(LockRepository {
            id: repository.id.clone(),
            path: repository.path.clone(),
            remote: repository.remote.clone(),
            default_branch: repository.default_branch.clone(),
            commit: pin.commit.clone(),
            digests,
        });
    }
    if !digest_diagnostics.is_empty() {
        return Err(digest_diagnostics);
    }
    repositories.sort_by(|left, right| left.id.cmp(&right.id));

    Ok(WorkspaceLock {
        format_version: 1,
        manifest_sha256: sha256(normalize_text(manifest_source).as_bytes()),
        gitmodules_sha256: sha256(normalize_text(&gitmodules_source).as_bytes()),
        repositories,
    })
}

/// Renders canonical v1 lock TOML.
#[must_use]
pub fn render_workspace_lock(lock: &WorkspaceLock) -> String {
    let mut lines = vec![
        format!("format_version = {}", lock.format_version),
        format!("manifest_sha256 = {}", toml_string(&lock.manifest_sha256)),
        format!(
            "gitmodules_sha256 = {}",
            toml_string(&lock.gitmodules_sha256)
        ),
    ];

    for repository in &lock.repositories {
        lines.push(String::new());
        lines.push("[[repositories]]".to_owned());
        lines.push(format!("id = {}", toml_string(&repository.id)));
        lines.push(format!("path = {}", toml_string(&repository.path)));
        lines.push(format!("remote = {}", toml_string(&repository.remote)));
        lines.push(format!(
            "default_branch = {}",
            toml_string(&repository.default_branch)
        ));
        lines.push(format!("commit = {}", toml_string(&repository.commit)));
        if repository.digests.is_empty() {
            lines.push("digests = []".to_owned());
        } else {
            lines.push("digests = [".to_owned());
            for digest in &repository.digests {
                lines.push(format!(
                    "  {{ path = {}, kind = {}, sha256 = {} }},",
                    toml_string(&digest.path),
                    toml_string(&digest.kind),
                    toml_string(&digest.sha256)
                ));
            }
            lines.push("]".to_owned());
        }
    }
    lines.push(String::new());
    lines.join("\n")
}

/// Compares committed lock text with freshly derived semantic data without writing.
#[must_use]
pub fn compare_workspace_lock(
    expected: &WorkspaceLock,
    committed_source: &str,
) -> Vec<ManifestDiagnostic> {
    let actual = match toml::from_str::<WorkspaceLock>(committed_source) {
        Ok(actual) => actual,
        Err(error) => {
            return vec![ManifestDiagnostic {
                code: "lock.parse",
                message: error.to_string(),
            }];
        }
    };
    semantic_lock_diagnostics(expected, &actual)
}

/// Atomically writes canonical lock output to an explicit path in its parent directory.
///
/// # Errors
///
/// Returns an I/O error when the output name is invalid or the temporary write, sync, or rename
/// fails.
pub fn write_workspace_lock_atomic(output: &Path, source: &str) -> io::Result<()> {
    let parent = output.parent().unwrap_or_else(|| Path::new("."));
    let filename = output
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| {
            io::Error::new(io::ErrorKind::InvalidInput, "lock output has no file name")
        })?;
    let sequence = NEXT_LOCK_WRITE.fetch_add(1, Ordering::Relaxed);
    let temporary = parent.join(format!(
        ".{filename}.{}.{}.tmp",
        std::process::id(),
        sequence
    ));
    let result = (|| {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)?;
        file.write_all(source.as_bytes())?;
        file.sync_all()?;
        fs::rename(&temporary, output)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

fn semantic_lock_diagnostics(
    expected: &WorkspaceLock,
    actual: &WorkspaceLock,
) -> Vec<ManifestDiagnostic> {
    let mut diagnostics = Vec::new();
    compare_lock_value(
        &mut diagnostics,
        "lock.format-version",
        "format version",
        &expected.format_version.to_string(),
        &actual.format_version.to_string(),
    );
    compare_lock_value(
        &mut diagnostics,
        "lock.manifest-sha256",
        "manifest SHA-256",
        &expected.manifest_sha256,
        &actual.manifest_sha256,
    );
    compare_lock_value(
        &mut diagnostics,
        "lock.gitmodules-sha256",
        ".gitmodules SHA-256",
        &expected.gitmodules_sha256,
        &actual.gitmodules_sha256,
    );
    let actual_repositories = actual
        .repositories
        .iter()
        .map(|repository| (repository.id.as_str(), repository))
        .collect::<BTreeMap<_, _>>();
    for repository in &expected.repositories {
        let Some(actual_repository) = actual_repositories.get(repository.id.as_str()) else {
            diagnostics.push(ManifestDiagnostic {
                code: "lock.repository.missing",
                message: format!("lock is missing repository `{}`", repository.id),
            });
            continue;
        };
        if repository.commit != actual_repository.commit {
            diagnostics.push(ManifestDiagnostic {
                code: "lock.repository.commit",
                message: format!(
                    "repository `{}` expected commit `{}` but lock contains `{}`",
                    repository.id, repository.commit, actual_repository.commit
                ),
            });
        }
        if repository != *actual_repository && repository.commit == actual_repository.commit {
            diagnostics.push(ManifestDiagnostic {
                code: "lock.repository.metadata",
                message: format!("repository `{}` lock metadata is stale", repository.id),
            });
        }
    }
    diagnostics
}

fn compare_lock_value(
    diagnostics: &mut Vec<ManifestDiagnostic>,
    code: &'static str,
    label: &str,
    expected: &str,
    actual: &str,
) {
    if expected != actual {
        diagnostics.push(ManifestDiagnostic {
            code,
            message: format!("{label} expected `{expected}` but lock contains `{actual}`"),
        });
    }
}

struct GitTreeEntry {
    mode: String,
    kind: String,
    object_id: String,
    path: String,
}

fn digest_git_input(
    workspace_root: &Path,
    repository: &ManifestRepository,
    commit: &str,
    input: &str,
) -> Result<LockDigest, ManifestDiagnostic> {
    if !digest_path_is_safe(input) {
        return Err(digest_diagnostic(
            "digest.path-unsafe",
            repository,
            input,
            "path must be a non-empty relative Git path without traversal",
        ));
    }
    let pathspec = format!(":(literal){input}");
    let output = git_output(
        workspace_root,
        &[
            "-C",
            repository.path.as_str(),
            "ls-tree",
            "-z",
            commit,
            "--",
            &pathspec,
        ],
    )
    .ok_or_else(|| {
        digest_diagnostic(
            "digest.git-error",
            repository,
            input,
            "Git object lookup failed",
        )
    })?;
    let mut records = output.split('\0').filter(|record| !record.is_empty());
    let Some(record) = records.next() else {
        return Err(digest_diagnostic(
            "digest.missing",
            repository,
            input,
            "path does not exist at the pinned commit",
        ));
    };
    let entry = parse_tree_entry(record).ok_or_else(|| {
        digest_diagnostic(
            "digest.git-output",
            repository,
            input,
            "Git returned an invalid tree entry",
        )
    })?;
    if entry.path != input || records.next().is_some() {
        return Err(digest_diagnostic(
            "digest.git-output",
            repository,
            input,
            "Git path lookup was not exact",
        ));
    }

    match (entry.mode.as_str(), entry.kind.as_str()) {
        ("100644" | "100755", "blob") => {
            let bytes = git_object_bytes(workspace_root, repository, input, &entry.object_id)?;
            Ok(LockDigest {
                path: input.to_owned(),
                kind: "file".to_owned(),
                sha256: sha256(&bytes),
            })
        }
        ("040000", "tree") => Ok(LockDigest {
            path: input.to_owned(),
            kind: "tree".to_owned(),
            sha256: digest_git_tree(workspace_root, repository, input, &entry.object_id)?,
        }),
        ("120000", "blob") => Err(digest_diagnostic(
            "digest.unsupported-type",
            repository,
            input,
            "symbolic links are not valid digest inputs",
        )),
        ("160000", "commit") => Err(digest_diagnostic(
            "digest.unsupported-type",
            repository,
            input,
            "nested submodules are not valid digest inputs",
        )),
        _ => Err(digest_diagnostic(
            "digest.unsupported-type",
            repository,
            input,
            &format!(
                "unsupported Git entry mode `{}` and type `{}`",
                entry.mode, entry.kind
            ),
        )),
    }
}

fn digest_git_tree(
    workspace_root: &Path,
    repository: &ManifestRepository,
    input: &str,
    tree_id: &str,
) -> Result<String, ManifestDiagnostic> {
    let output = git_output(
        workspace_root,
        &[
            "-C",
            repository.path.as_str(),
            "ls-tree",
            "-r",
            "-z",
            "-l",
            tree_id,
        ],
    )
    .ok_or_else(|| {
        digest_diagnostic(
            "digest.git-error",
            repository,
            input,
            "Git tree traversal failed",
        )
    })?;
    let mut hasher = Sha256::new();
    for record in output.split('\0').filter(|record| !record.is_empty()) {
        let entry = parse_tree_entry(record).ok_or_else(|| {
            digest_diagnostic(
                "digest.git-output",
                repository,
                input,
                "Git returned an invalid recursive tree entry",
            )
        })?;
        if entry.kind != "blob" || !matches!(entry.mode.as_str(), "100644" | "100755") {
            return Err(digest_diagnostic(
                "digest.unsupported-type",
                repository,
                input,
                &format!(
                    "tree contains unsupported `{}` entry `{}` with mode `{}`",
                    entry.kind, entry.path, entry.mode
                ),
            ));
        }
        let bytes = git_object_bytes(workspace_root, repository, input, &entry.object_id)?;
        hasher.update(entry.path.as_bytes());
        hasher.update([0]);
        hasher.update(entry.mode.as_bytes());
        hasher.update([0]);
        hasher.update(entry.object_id.as_bytes());
        hasher.update([0]);
        hasher.update(bytes.len().to_string().as_bytes());
        hasher.update([0]);
        hasher.update(&bytes);
        hasher.update([0]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

fn git_object_bytes(
    workspace_root: &Path,
    repository: &ManifestRepository,
    input: &str,
    object_id: &str,
) -> Result<Vec<u8>, ManifestDiagnostic> {
    git_bytes(
        workspace_root,
        &[
            "-C",
            repository.path.as_str(),
            "cat-file",
            "blob",
            object_id,
        ],
    )
    .ok_or_else(|| {
        digest_diagnostic(
            "digest.git-error",
            repository,
            input,
            "Git blob read failed",
        )
    })
}

fn parse_tree_entry(record: &str) -> Option<GitTreeEntry> {
    let (metadata, path) = record.split_once('\t')?;
    let mut fields = metadata.split_whitespace();
    Some(GitTreeEntry {
        mode: fields.next()?.to_owned(),
        kind: fields.next()?.to_owned(),
        object_id: fields.next()?.to_owned(),
        path: path.to_owned(),
    })
}

fn digest_path_is_safe(path: &str) -> bool {
    !path.is_empty()
        && !path.contains('\\')
        && Path::new(path)
            .components()
            .all(|component| matches!(component, Component::Normal(_)))
}

fn digest_diagnostic(
    code: &'static str,
    repository: &ManifestRepository,
    input: &str,
    detail: &str,
) -> ManifestDiagnostic {
    ManifestDiagnostic {
        code,
        message: format!(
            "repository `{}` digest input `{input}`: {detail}",
            repository.id
        ),
    }
}

fn normalize_text(source: &str) -> String {
    let normalized = source.replace("\r\n", "\n").replace('\r', "\n");
    format!("{}\n", normalized.trim_end_matches('\n'))
}

fn sha256(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn toml_string(value: &str) -> String {
    toml::Value::String(value.to_owned()).to_string()
}

fn classify_status(status: &str) -> (Vec<String>, Vec<String>) {
    let mut tracked = Vec::new();
    let mut untracked = Vec::new();
    for record in status.split('\0').filter(|record| !record.is_empty()) {
        if let Some(path) = record.strip_prefix("?? ") {
            untracked.push(path.to_owned());
        } else {
            tracked.push(record.chars().skip(3).collect());
        }
    }
    (tracked, untracked)
}

struct TopologyInspector<'a> {
    workspace_root: &'a Path,
    gitmodules: &'a BTreeMap<String, (String, String)>,
    gitlinks: &'a BTreeMap<String, (String, String)>,
    pins: Vec<GitPin>,
    diagnostics: Vec<ManifestDiagnostic>,
}

impl TopologyInspector<'_> {
    fn inspect(&mut self, repository: &ManifestRepository) {
        let module = self.gitmodules.get(repository.id.as_str());
        if let Some((module_path, module_remote)) = module {
            if module_path != &repository.path {
                self.diagnostics.push(ManifestDiagnostic {
                    code: "topology.path-mismatch",
                    message: format!(
                        "repository `{}` declares path `{}` but `.gitmodules` declares `{module_path}`",
                        repository.id, repository.path
                    ),
                });
            }
            if module_remote != &repository.remote {
                self.diagnostics.push(ManifestDiagnostic {
                    code: "topology.remote-mismatch",
                    message: format!(
                        "repository `{}` declares remote `{}` but `.gitmodules` declares `{module_remote}`",
                        repository.id, repository.remote
                    ),
                });
            }
        } else {
            self.diagnostics.push(ManifestDiagnostic {
                code: "topology.gitmodules-missing",
                message: format!(
                    "repository `{}` has no matching `.gitmodules` entry",
                    repository.id
                ),
            });
        }

        let gitlink = self.gitlinks.get(repository.path.as_str());
        if let Some((mode, _commit)) = gitlink {
            if mode != "160000" {
                self.diagnostics.push(ManifestDiagnostic {
                    code: "topology.mode-mismatch",
                    message: format!(
                        "repository `{}` index mode is `{mode}`; expected gitlink mode `160000`",
                        repository.id
                    ),
                });
            }
        } else {
            self.diagnostics.push(ManifestDiagnostic {
                code: "topology.gitlink-missing",
                message: format!(
                    "repository `{}` has no gitlink at `{}`",
                    repository.id, repository.path
                ),
            });
        }

        let Some((module_path, module_remote)) = module else {
            return;
        };
        let Some((mode, commit)) = gitlink else {
            return;
        };
        if module_path != &repository.path
            || module_remote != &repository.remote
            || mode != "160000"
        {
            return;
        }
        let module_remote = module_remote.clone();
        let commit = commit.clone();
        self.inspect_materialization(repository, &module_remote, &commit);
    }

    fn inspect_materialization(
        &mut self,
        repository: &ManifestRepository,
        module_remote: &str,
        commit: &str,
    ) {
        let child_path = self.workspace_root.join(&repository.path);
        let initialized = child_path.join(".git").exists();
        let reachable = initialized
            && git_status(
                self.workspace_root,
                &[
                    "-C",
                    repository.path.as_str(),
                    "cat-file",
                    "-e",
                    &format!("{commit}^{{commit}}"),
                ],
            );
        if !initialized {
            self.diagnostics.push(ManifestDiagnostic {
                code: "topology.submodule-uninitialized",
                message: format!(
                    "repository `{}` is uninitialized; run `git submodule update --init --recursive` explicitly",
                    repository.id
                ),
            });
            return;
        }
        if !reachable {
            self.diagnostics.push(ManifestDiagnostic {
                code: "topology.gitlink-unreachable",
                message: format!(
                    "repository `{}` does not contain pinned commit `{commit}`",
                    repository.id
                ),
            });
            return;
        }

        self.pins.push(GitPin {
            id: repository.id.clone(),
            path: repository.path.clone(),
            remote: module_remote.to_owned(),
            commit: commit.to_owned(),
            initialized,
            reachable,
        });
    }
}

fn topology_unimplemented() -> GitTopologyReport {
    GitTopologyReport {
        pins: Vec::new(),
        diagnostics: vec![ManifestDiagnostic {
            code: "topology.unimplemented",
            message: "Git topology mismatch reporting is not implemented".to_owned(),
        }],
    }
}

fn read_gitmodules(workspace_root: &Path) -> Option<BTreeMap<String, (String, String)>> {
    let output = git_output(
        workspace_root,
        &[
            "config",
            "-f",
            ".gitmodules",
            "--get-regexp",
            r"^submodule\..*\.(path|url)$",
        ],
    )?;
    let mut partial = BTreeMap::<String, (Option<String>, Option<String>)>::new();
    for line in output.lines() {
        let (key, value) = line.split_once(' ')?;
        let key = key.strip_prefix("submodule.")?;
        let (identity, field) = key.rsplit_once('.')?;
        let entry = partial.entry(identity.to_owned()).or_default();
        match field {
            "path" => entry.0 = Some(value.to_owned()),
            "url" => entry.1 = Some(value.to_owned()),
            _ => return None,
        }
    }

    partial
        .into_iter()
        .map(|(identity, (path, remote))| Some((identity, (path?, remote?))))
        .collect()
}

fn read_gitlinks(workspace_root: &Path) -> Option<BTreeMap<String, (String, String)>> {
    let output = git_output(workspace_root, &["ls-files", "--stage", "-z"])?;
    let mut gitlinks = BTreeMap::new();
    for record in output.split('\0').filter(|record| !record.is_empty()) {
        let (metadata, path) = record.split_once('\t')?;
        let mut fields = metadata.split_whitespace();
        let mode = fields.next()?;
        let commit = fields.next()?;
        let _stage = fields.next()?;
        gitlinks.insert(path.to_owned(), (mode.to_owned(), commit.to_owned()));
    }
    Some(gitlinks)
}

fn git_output(workspace_root: &Path, arguments: &[&str]) -> Option<String> {
    String::from_utf8(git_bytes(workspace_root, arguments)?).ok()
}

fn git_bytes(workspace_root: &Path, arguments: &[&str]) -> Option<Vec<u8>> {
    let output = git_command(workspace_root, arguments).output().ok()?;
    output.status.success().then_some(output.stdout)
}

fn git_status(workspace_root: &Path, arguments: &[&str]) -> bool {
    git_command(workspace_root, arguments)
        .status()
        .is_ok_and(|status| status.success())
}

fn git_command(workspace_root: &Path, arguments: &[&str]) -> Command {
    let mut command = Command::new("git");
    command
        .args(arguments)
        .current_dir(workspace_root)
        .env("GIT_OPTIONAL_LOCKS", "0")
        .env("GIT_TERMINAL_PROMPT", "0");
    command
}

fn repository_is_in_cycle<'a>(
    identity: &'a str,
    repositories: &BTreeMap<&'a str, &'a ManifestRepository>,
) -> bool {
    let mut stack = repositories
        .get(identity)
        .into_iter()
        .flat_map(|repository| {
            repository
                .dependencies
                .iter()
                .map(|dependency| dependency.repository.as_str())
        })
        .collect::<Vec<_>>();
    let mut visited = BTreeSet::new();

    while let Some(candidate) = stack.pop() {
        if candidate == identity {
            return true;
        }
        if !visited.insert(candidate) {
            continue;
        }
        if let Some(repository) = repositories.get(candidate) {
            stack.extend(
                repository
                    .dependencies
                    .iter()
                    .map(|dependency| dependency.repository.as_str()),
            );
        }
    }

    false
}

fn duplicate_diagnostics<'a>(
    repositories: &'a [ManifestRepository],
    value: impl Fn(&'a ManifestRepository) -> &'a str,
    code: &'static str,
    label: &'static str,
) -> Vec<ManifestDiagnostic> {
    let mut seen = BTreeSet::new();
    let mut reported = BTreeSet::new();

    repositories
        .iter()
        .map(value)
        .filter(|candidate| !seen.insert(*candidate) && reported.insert(*candidate))
        .map(|duplicate| ManifestDiagnostic {
            code,
            message: format!("{label} `{duplicate}` is declared more than once"),
        })
        .collect()
}
