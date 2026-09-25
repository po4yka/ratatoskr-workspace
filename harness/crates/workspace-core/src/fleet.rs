//! Bootstrap of the files every fleet repository carries.
//!
//! The source is read from its committed tree (`git ls-tree HEAD`), which is the object
//! `.github/workflows/drift.yml` compares across the fleet, so a copy is identical by the same
//! definition: exact blob bytes, mode `100755` written executable, and mode `120000` written as a
//! symbolic link.

use crate::{GitTreeEntry, ManifestDiagnostic, git_bytes, git_output, parse_tree_entry};
use std::ffi::OsStr;
use std::fs;
use std::io;
use std::os::unix::ffi::OsStrExt as _;
use std::os::unix::fs::{PermissionsExt as _, symlink};
use std::path::Path;

/// Files every fleet repository carries identically, whatever its class.
const SHARED_FILES: [&str; 8] = [
    ".github/workflows/fleet.yml",
    ".github/workflows/zizmor.yml",
    ".github/workflows/openspec.yml",
    ".github/workflows/dependabot-automerge.yml",
    ".githooks/pre-commit",
    ".gitattributes",
    ".editorconfig",
    "LICENSE",
];

/// The prefixes of the paths `openspec init` generates. These are the prefixes `drift.yml` names
/// in its `generated` tuple, and they must stay equal to them.
const GENERATED_PREFIXES: [&str; 6] = [
    ".claude/commands/opsx/",
    ".claude/skills/openspec-",
    ".agents/skills/openspec-",
    ".agents/skills/.openspec-target",
    ".opencode/commands/opsx-",
    ".opencode/skills/openspec-",
];

/// Where the vendored Rust skill catalogue and its `.claude/skills/` symlinks live. A path here
/// that is not a generated path is vendored, which is `drift.yml`'s `vendored` rule.
const VENDORED_PREFIXES: [&str; 2] = [".agents/skills/", ".claude/skills/"];

const ADVISORIES: &str = ".github/workflows/advisories.yml";
const RUST_FILES: [&str; 3] = [".github/dependabot.yml", "skills-lock.json", ADVISORIES];
const NON_RUST_FILES: [&str; 1] = [".github/dependabot.yml"];

/// Files the fleet requires that each repository writes itself, so they cannot be copied.
///
/// This list must match the required-file list in `.github/workflows/fleet.yml` (minus the files
/// copied above) and the presence checks in `.github/workflows/drift.yml`. When either workflow
/// adds or drops a required file, change this list in the same commit.
const HAND_WRITTEN: [&str; 12] = [
    ".gitignore",
    "README.md",
    "AGENTS.md",
    "CLAUDE.md",
    "DEVELOPMENT.md",
    "SECURITY.md",
    "openspec/config.yaml",
    "docs/ARCHITECTURE.md",
    "docs/REQUIREMENTS.md",
    "docs/THREAT_MODEL.md",
    "docs/TESTING.md",
    "docs/adr/README.md",
];

/// What a repository with Rust also has to write: `fleet.yml` requires `clippy.toml` beside a
/// `Cargo.toml`, and `drift.yml` requires `ci.yml` in every repository with Rust.
const RUST_HAND_WRITTEN: [&str; 2] = ["clippy.toml", ".github/workflows/ci.yml"];

/// Which class-specific file set a repository receives.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FleetClass {
    /// A repository with Rust in it.
    Rust,
    /// A repository without Rust.
    NonRust,
}

impl FleetClass {
    const fn name(self) -> &'static str {
        match self {
            Self::Rust => "Rust",
            Self::NonRust => "non-Rust",
        }
    }
}

/// What one `fleet_init` run did and what it could not do.
#[derive(Debug, Eq, PartialEq)]
pub struct FleetInitReport {
    /// The target's class.
    pub class: FleetClass,
    /// Paths written into the target.
    pub copied: Vec<String>,
    /// Paths the target already had with identical content.
    pub unchanged: Vec<String>,
    /// Fleet paths the source does not carry.
    pub absent_from_source: Vec<String>,
    /// Paths the source carries in a form that is not the fleet form for the target. Today only
    /// `advisories.yml` from a source whose Rust is below the root, such as this workspace.
    pub withheld: Vec<String>,
    /// Required paths the target lacks that each repository writes itself.
    pub still_missing: Vec<String>,
}

enum Content {
    File { bytes: Vec<u8>, executable: bool },
    Link(Vec<u8>),
}

struct Planned {
    path: String,
    content: Content,
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum TargetState {
    Missing,
    Same,
    Differs,
    Directory,
}

struct Selection<'a> {
    entries: Vec<&'a GitTreeEntry>,
    absent: Vec<String>,
    withheld: Vec<String>,
}

/// Copies the committed fleet files from `source` into `target`.
///
/// Every planned path is compared with the target before anything is written, so a refused run
/// leaves the target unchanged. With `force`, differing files and links are replaced; a directory
/// where a file belongs is always a conflict.
///
/// # Errors
///
/// Returns diagnostics when the target is not a directory, the source has no readable committed
/// tree, the source and target classes differ, a target file conflicts, or a write fails.
pub fn fleet_init(
    source: &Path,
    target: &Path,
    force: bool,
) -> Result<FleetInitReport, Vec<ManifestDiagnostic>> {
    if !target.is_dir() {
        return Err(vec![diagnostic(
            "fleet.target-missing",
            "the target is not an existing directory".to_owned(),
        )]);
    }
    let tree = source_tree(source)?;
    let class = target_class(target);
    check_classes(class, source_class(&tree))?;
    let selection = select(&tree, class);
    let planned = load(source, &selection.entries)?;
    let states = planned
        .iter()
        .map(|planned| target_state(target, planned))
        .collect::<Result<Vec<_>, _>>()?;
    check_conflicts(&planned, &states, force)?;

    let mut copied = Vec::new();
    let mut unchanged = Vec::new();
    for (planned, state) in planned.iter().zip(states) {
        if state == TargetState::Same {
            unchanged.push(planned.path.clone());
            continue;
        }
        write_planned(target, planned, state == TargetState::Differs)
            .map_err(|error| vec![io_diagnostic(&planned.path, &error)])?;
        copied.push(planned.path.clone());
    }

    Ok(FleetInitReport {
        class,
        copied,
        unchanged,
        absent_from_source: selection.absent,
        withheld: selection.withheld,
        still_missing: still_missing(target, class),
    })
}

fn source_tree(source: &Path) -> Result<Vec<GitTreeEntry>, Vec<ManifestDiagnostic>> {
    let unreadable = || {
        vec![diagnostic(
            "fleet.source-unreadable",
            "the source is not a Git repository with a readable committed tree at HEAD".to_owned(),
        )]
    };
    let output = git_output(source, &["ls-tree", "-r", "-z", "HEAD"]).ok_or_else(unreadable)?;
    output
        .split('\0')
        .filter(|record| !record.is_empty())
        .map(parse_tree_entry)
        .collect::<Option<Vec<_>>>()
        .ok_or_else(unreadable)
}

fn target_class(target: &Path) -> FleetClass {
    if target.join("Cargo.toml").is_file() {
        FleetClass::Rust
    } else {
        FleetClass::NonRust
    }
}

/// A `Cargo.toml` at any depth makes the source Rust, the rule `drift.yml` applies. It is what
/// puts this workspace, whose Rust is under `harness/`, in the Rust class.
fn source_class(tree: &[GitTreeEntry]) -> FleetClass {
    if tree
        .iter()
        .any(|entry| entry.path == "Cargo.toml" || entry.path.ends_with("/Cargo.toml"))
    {
        FleetClass::Rust
    } else {
        FleetClass::NonRust
    }
}

fn check_classes(target: FleetClass, source: FleetClass) -> Result<(), Vec<ManifestDiagnostic>> {
    if target == source {
        return Ok(());
    }
    let why = match target {
        FleetClass::Rust => "it has a root Cargo.toml",
        FleetClass::NonRust => "it has no root Cargo.toml",
    };
    Err(vec![diagnostic(
        "fleet.class-mismatch",
        format!(
            "the target is a {} repository ({why}) but the source is a {} repository; pass --from a fleet repository of the {} class",
            target.name(),
            source.name(),
            target.name()
        ),
    )])
}

fn select(tree: &[GitTreeEntry], class: FleetClass) -> Selection<'_> {
    let mut selection = Selection {
        entries: Vec::new(),
        absent: Vec::new(),
        withheld: Vec::new(),
    };
    let class_files: &[&str] = match class {
        FleetClass::Rust => &RUST_FILES,
        FleetClass::NonRust => &NON_RUST_FILES,
    };
    // `drift.yml` requires one `advisories.yml` blob only across repositories with a root
    // `Cargo.toml`. A source whose Rust is nested carries a different, deliberate form.
    let root_rust = tree.iter().any(|entry| entry.path == "Cargo.toml");
    for name in SHARED_FILES.iter().chain(class_files) {
        if *name == ADVISORIES && !root_rust {
            selection.withheld.push((*name).to_owned());
            continue;
        }
        match tree.iter().find(|entry| entry.path == *name) {
            Some(entry) => selection.entries.push(entry),
            None => selection.absent.push((*name).to_owned()),
        }
    }
    for prefix in GENERATED_PREFIXES {
        let before = selection.entries.len();
        selection
            .entries
            .extend(tree.iter().filter(|entry| entry.path.starts_with(prefix)));
        if selection.entries.len() == before {
            selection.absent.push(prefix.to_owned());
        }
    }
    if class == FleetClass::Rust {
        let before = selection.entries.len();
        selection.entries.extend(tree.iter().filter(|entry| {
            VENDORED_PREFIXES
                .iter()
                .any(|prefix| entry.path.starts_with(prefix))
                && !GENERATED_PREFIXES
                    .iter()
                    .any(|prefix| entry.path.starts_with(prefix))
        }));
        if selection.entries.len() == before {
            selection
                .absent
                .push(".agents/skills/ (the Rust skill catalogue)".to_owned());
        }
    }
    selection
}

fn load(source: &Path, entries: &[&GitTreeEntry]) -> Result<Vec<Planned>, Vec<ManifestDiagnostic>> {
    entries
        .iter()
        .map(|entry| {
            let bytes = git_bytes(source, &["cat-file", "blob", entry.object_id.as_str()])
                .ok_or_else(|| {
                    vec![diagnostic(
                        "fleet.source-unreadable",
                        format!("the source blob for `{}` could not be read", entry.path),
                    )]
                })?;
            let content = match (entry.mode.as_str(), entry.kind.as_str()) {
                ("100644", "blob") => Content::File {
                    bytes,
                    executable: false,
                },
                ("100755", "blob") => Content::File {
                    bytes,
                    executable: true,
                },
                ("120000", "blob") => Content::Link(bytes),
                (mode, kind) => {
                    return Err(vec![diagnostic(
                        "fleet.source-unsupported",
                        format!(
                            "`{}` is a `{kind}` with mode `{mode}`, which cannot be copied",
                            entry.path
                        ),
                    )]);
                }
            };
            Ok(Planned {
                path: entry.path.clone(),
                content,
            })
        })
        .collect()
}

fn target_state(target: &Path, planned: &Planned) -> Result<TargetState, Vec<ManifestDiagnostic>> {
    let io_error = |error: io::Error| vec![io_diagnostic(&planned.path, &error)];
    let path = target.join(&planned.path);
    let metadata = match fs::symlink_metadata(&path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(TargetState::Missing),
        Err(error) => return Err(io_error(error)),
    };
    if metadata.is_dir() {
        return Ok(TargetState::Directory);
    }
    let same = match &planned.content {
        Content::File { bytes, executable } => {
            metadata.is_file()
                && (metadata.permissions().mode() & 0o111 != 0) == *executable
                && fs::read(&path).map_err(io_error)? == *bytes
        }
        Content::Link(link) => {
            metadata.file_type().is_symlink()
                && fs::read_link(&path)
                    .map_err(io_error)?
                    .as_os_str()
                    .as_bytes()
                    == link.as_slice()
        }
    };
    Ok(if same {
        TargetState::Same
    } else {
        TargetState::Differs
    })
}

fn check_conflicts(
    planned: &[Planned],
    states: &[TargetState],
    force: bool,
) -> Result<(), Vec<ManifestDiagnostic>> {
    let conflicts = planned
        .iter()
        .zip(states)
        .filter_map(|(planned, state)| match state {
            TargetState::Directory => Some(diagnostic(
                "fleet.conflict",
                format!(
                    "`{}` is a directory in the target where the fleet has a file; move it aside, --force does not replace a directory",
                    planned.path
                ),
            )),
            TargetState::Differs if !force => Some(diagnostic(
                "fleet.conflict",
                format!(
                    "`{}` differs from the fleet copy; nothing was written, rerun with --force to replace it",
                    planned.path
                ),
            )),
            _ => None,
        })
        .collect::<Vec<_>>();
    if conflicts.is_empty() {
        Ok(())
    } else {
        Err(conflicts)
    }
}

fn write_planned(target: &Path, planned: &Planned, replace: bool) -> io::Result<()> {
    let path = target.join(&planned.path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    if replace {
        fs::remove_file(&path)?;
    }
    match &planned.content {
        Content::File { bytes, executable } => {
            fs::write(&path, bytes)?;
            let mode = if *executable { 0o755 } else { 0o644 };
            fs::set_permissions(&path, fs::Permissions::from_mode(mode))
        }
        Content::Link(link) => symlink(OsStr::from_bytes(link), &path),
    }
}

fn still_missing(target: &Path, class: FleetClass) -> Vec<String> {
    let rust: &[&str] = match class {
        FleetClass::Rust => &RUST_HAND_WRITTEN,
        FleetClass::NonRust => &[],
    };
    HAND_WRITTEN
        .iter()
        .chain(rust)
        .filter(|path| fs::symlink_metadata(target.join(path)).is_err())
        .map(|path| (*path).to_owned())
        .collect()
}

fn diagnostic(code: &'static str, message: String) -> ManifestDiagnostic {
    ManifestDiagnostic { code, message }
}

fn io_diagnostic(path: &str, error: &io::Error) -> ManifestDiagnostic {
    diagnostic(
        "fleet.io",
        format!("`{path}` could not be written: {error}"),
    )
}
