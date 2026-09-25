use std::fs;
use std::os::unix::fs::{PermissionsExt as _, symlink};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_FLEET_FIXTURE: AtomicU64 = AtomicU64::new(1);

/// Files every fleet source in these fixtures carries. `dependabot-automerge.yml` is deliberately
/// absent, so the report of files the source lacks has something to say.
pub(crate) const SHARED: [&str; 7] = [
    ".github/workflows/fleet.yml",
    ".github/workflows/zizmor.yml",
    ".github/workflows/openspec.yml",
    ".githooks/pre-commit",
    ".gitattributes",
    ".editorconfig",
    "LICENSE",
];

/// One path under each prefix `openspec init` generates.
pub(crate) const GENERATED: [&str; 6] = [
    ".claude/commands/opsx/propose.md",
    ".claude/skills/openspec-propose/SKILL.md",
    ".agents/skills/openspec-propose/SKILL.md",
    ".agents/skills/.openspec-target",
    ".opencode/commands/opsx-propose.md",
    ".opencode/skills/openspec-propose/SKILL.md",
];

/// Rust-class files apart from the `.claude/skills/rust-tdd` symlink.
pub(crate) const RUST_ONLY: [&str; 4] = [
    ".github/workflows/advisories.yml",
    "skills-lock.json",
    ".agents/skills/rust-tdd/SKILL.md",
    ".agents/skills/rust-tdd/references/cycle.md",
];

pub(crate) const RUST_SKILL_LINK: &str = ".claude/skills/rust-tdd";
pub(crate) const RUST_SKILL_LINK_TARGET: &str = "../../.agents/skills/rust-tdd";

#[derive(Clone, Copy)]
pub(crate) enum SourceLayout {
    /// A product repository whose `Cargo.toml` is at the root.
    RustAtRoot,
    /// The workspace shape: Rust only under `harness/`.
    RustBelowRoot,
    /// A repository with no Rust.
    NoRust,
}

pub(crate) struct FleetFixture {
    root: PathBuf,
}

impl FleetFixture {
    pub(crate) fn new() -> Self {
        let sequence = NEXT_FLEET_FIXTURE.fetch_add(1, Ordering::Relaxed);
        let root = std::env::temp_dir().join(format!(
            "ratatoskr-fleet-fixture-{}-{sequence}",
            std::process::id()
        ));
        fs::create_dir_all(&root).expect("create fleet fixture root");
        Self { root }
    }

    /// A committed fleet repository of the given layout.
    pub(crate) fn source(&self, layout: SourceLayout) -> PathBuf {
        let source = self.root.join("source");
        fs::create_dir_all(&source).expect("create fleet source");
        git(&source, &["init", "--quiet"]);
        git(
            &source,
            &["config", "user.email", "fixture@example.invalid"],
        );
        git(&source, &["config", "user.name", "Fixture"]);
        for path in SHARED.iter().chain(GENERATED.iter()) {
            write(&source, path, &content(path));
        }
        fs::set_permissions(
            source.join(".githooks/pre-commit"),
            fs::Permissions::from_mode(0o755),
        )
        .expect("make fixture hook executable");
        write(
            &source,
            ".github/dependabot.yml",
            &content(".github/dependabot.yml"),
        );
        write(&source, "README.md", "not a fleet file\n");
        match layout {
            SourceLayout::RustAtRoot => write(&source, "Cargo.toml", "[package]\n"),
            SourceLayout::RustBelowRoot => write(&source, "harness/Cargo.toml", "[workspace]\n"),
            SourceLayout::NoRust => {}
        }
        if !matches!(layout, SourceLayout::NoRust) {
            for path in RUST_ONLY {
                write(&source, path, &content(path));
            }
            let link = source.join(RUST_SKILL_LINK);
            fs::create_dir_all(link.parent().expect("link parent")).expect("create link parent");
            symlink(RUST_SKILL_LINK_TARGET, link).expect("create skill symlink");
        }
        git(&source, &["add", "--all"]);
        git(&source, &["commit", "--quiet", "-m", "fleet fixture"]);
        source
    }

    /// An empty target, with a root `Cargo.toml` when `rust` is set.
    pub(crate) fn target(&self, rust: bool) -> PathBuf {
        let target = self.root.join("target");
        fs::create_dir_all(&target).expect("create fleet target");
        if rust {
            write(&target, "Cargo.toml", "[package]\n");
        }
        target
    }
}

impl Drop for FleetFixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

/// The committed bytes the fixture writes at `path`.
pub(crate) fn content(path: &str) -> String {
    format!("{path} as committed in the fleet source\n")
}

pub(crate) fn write(root: &Path, path: &str, text: &str) {
    let file = root.join(path);
    if let Some(parent) = file.parent() {
        fs::create_dir_all(parent).expect("create fixture parent");
    }
    fs::write(file, text).expect("write fixture file");
}

fn git(repository: &Path, arguments: &[&str]) {
    let output = Command::new("git")
        .args(arguments)
        .current_dir(repository)
        .env("GIT_AUTHOR_DATE", "2000-01-01T00:00:00Z")
        .env("GIT_COMMITTER_DATE", "2000-01-01T00:00:00Z")
        .output()
        .expect("run Git fixture command");
    assert!(
        output.status.success(),
        "git {arguments:?} failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
}
