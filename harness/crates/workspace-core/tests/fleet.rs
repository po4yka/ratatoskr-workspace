//! Fleet bootstrap contract tests.

#![allow(clippy::expect_used, clippy::panic)]

#[path = "support/fleet.rs"]
mod support;

use std::fs;
use std::os::unix::fs::PermissionsExt as _;
use std::path::{Path, PathBuf};
use support::{
    FleetFixture, GENERATED, RUST_ONLY, RUST_SKILL_LINK, RUST_SKILL_LINK_TARGET, SHARED,
    SourceLayout, content, write,
};
use workspace_core::{FleetClass, fleet_init};

const ADVISORIES: &str = ".github/workflows/advisories.yml";
const DEPENDABOT: &str = ".github/dependabot.yml";
const AUTOMERGE: &str = ".github/workflows/dependabot-automerge.yml";

#[test]
fn rust_target_receives_every_shared_generated_and_rust_file() {
    let fixture = FleetFixture::new();
    let source = fixture.source(SourceLayout::RustAtRoot);
    let target = fixture.target(true);

    let report = fleet_init(&source, &target, false).expect("fleet init succeeds");

    assert_eq!(report.class, FleetClass::Rust);
    for path in SHARED
        .iter()
        .chain(GENERATED.iter())
        .chain(RUST_ONLY.iter())
        .chain([DEPENDABOT].iter())
    {
        assert_eq!(read(&target, path), content(path), "{path} differs");
        assert!(
            report.copied.iter().any(|copied| copied == path),
            "{path} not reported"
        );
    }
    let hook = fs::metadata(target.join(".githooks/pre-commit")).expect("hook metadata");
    assert_eq!(hook.permissions().mode() & 0o777, 0o755);
    let license = fs::metadata(target.join("LICENSE")).expect("license metadata");
    assert_eq!(license.permissions().mode() & 0o111, 0);
    assert_eq!(
        fs::read_link(target.join(RUST_SKILL_LINK)).expect("skill link is a symlink"),
        PathBuf::from(RUST_SKILL_LINK_TARGET)
    );
    assert!(
        !target.join("README.md").exists(),
        "a non-fleet file was copied"
    );
    assert!(report.withheld.is_empty());
}

#[test]
fn non_rust_target_receives_dependabot_but_no_rust_files() {
    let fixture = FleetFixture::new();
    let source = fixture.source(SourceLayout::NoRust);
    let target = fixture.target(false);

    let report = fleet_init(&source, &target, false).expect("fleet init succeeds");

    assert_eq!(report.class, FleetClass::NonRust);
    assert_eq!(read(&target, DEPENDABOT), content(DEPENDABOT));
    assert_eq!(read(&target, "LICENSE"), content("LICENSE"));
    for path in RUST_ONLY.iter().chain([RUST_SKILL_LINK].iter()) {
        assert!(
            fs::symlink_metadata(target.join(path)).is_err(),
            "{path} reached a non-Rust target"
        );
    }
}

#[test]
fn class_mismatch_fails_and_writes_nothing() {
    let fixture = FleetFixture::new();
    let source = fixture.source(SourceLayout::RustBelowRoot);
    let target = fixture.target(false);

    let result = fleet_init(&source, &target, false);

    let diagnostics = result.expect_err("a Rust source is refused for a non-Rust target");
    assert!(
        diagnostics
            .iter()
            .any(|diagnostic| diagnostic.code == "fleet.class-mismatch"
                && diagnostic.message.contains("--from")),
        "unexpected diagnostics: {diagnostics:?}"
    );
    assert_eq!(fs::read_dir(&target).expect("list target").count(), 0);
}

#[test]
fn differing_file_is_a_conflict_unless_forced() {
    let fixture = FleetFixture::new();
    let source = fixture.source(SourceLayout::RustAtRoot);
    let target = fixture.target(true);
    write(&target, "LICENSE", "a different licence\n");

    let diagnostics = fleet_init(&source, &target, false).expect_err("conflict is refused");

    assert!(
        diagnostics
            .iter()
            .any(|diagnostic| diagnostic.code == "fleet.conflict"
                && diagnostic.message.contains("`LICENSE`")),
        "unexpected diagnostics: {diagnostics:?}"
    );
    assert_eq!(read(&target, "LICENSE"), "a different licence\n");
    assert!(!target.join(".github/workflows/fleet.yml").exists());

    let report = fleet_init(&source, &target, true).expect("forced run succeeds");

    assert_eq!(read(&target, "LICENSE"), content("LICENSE"));
    assert!(report.copied.iter().any(|path| path == "LICENSE"));
}

#[test]
fn second_run_changes_nothing() {
    let fixture = FleetFixture::new();
    let source = fixture.source(SourceLayout::RustAtRoot);
    let target = fixture.target(true);
    let first = fleet_init(&source, &target, false).expect("first run succeeds");

    let second = fleet_init(&source, &target, false).expect("second run succeeds");

    assert!(!first.copied.is_empty());
    assert!(
        second.copied.is_empty(),
        "second run copied {:?}",
        second.copied
    );
    assert_eq!(second.unchanged, first.copied);
}

#[test]
fn absent_source_files_are_reported() {
    let fixture = FleetFixture::new();
    let source = fixture.source(SourceLayout::RustAtRoot);
    let target = fixture.target(true);

    let report = fleet_init(&source, &target, false).expect("fleet init succeeds");

    assert_eq!(report.absent_from_source, vec![AUTOMERGE.to_owned()]);
    assert!(!target.join(AUTOMERGE).exists());
}

#[test]
fn hand_written_required_files_are_reported() {
    let fixture = FleetFixture::new();
    let source = fixture.source(SourceLayout::RustAtRoot);
    let target = fixture.target(true);
    write(&target, "SECURITY.md", "policy\n");

    let report = fleet_init(&source, &target, false).expect("fleet init succeeds");

    for path in [
        ".gitignore",
        "README.md",
        "AGENTS.md",
        "CLAUDE.md",
        "DEVELOPMENT.md",
        "openspec/config.yaml",
        "docs/ARCHITECTURE.md",
        "docs/REQUIREMENTS.md",
        "docs/THREAT_MODEL.md",
        "docs/TESTING.md",
        "docs/adr/README.md",
        "clippy.toml",
        ".github/workflows/ci.yml",
    ] {
        assert!(
            report.still_missing.iter().any(|missing| missing == path),
            "{path} is not reported missing: {:?}",
            report.still_missing
        );
    }
    assert!(
        !report
            .still_missing
            .iter()
            .any(|path| path == "SECURITY.md")
    );
}

#[test]
fn only_committed_content_is_copied() {
    let fixture = FleetFixture::new();
    let source = fixture.source(SourceLayout::RustAtRoot);
    let target = fixture.target(true);
    write(
        &source,
        ".github/workflows/fleet.yml",
        "an uncommitted edit\n",
    );
    write(&source, ".agents/skills/rust-extra/SKILL.md", "untracked\n");

    fleet_init(&source, &target, false).expect("fleet init succeeds");

    assert_eq!(
        read(&target, ".github/workflows/fleet.yml"),
        content(".github/workflows/fleet.yml")
    );
    assert!(!target.join(".agents/skills/rust-extra").exists());
}

#[test]
fn advisories_are_withheld_from_a_source_with_nested_rust() {
    let fixture = FleetFixture::new();
    let source = fixture.source(SourceLayout::RustBelowRoot);
    let target = fixture.target(true);

    let report = fleet_init(&source, &target, false).expect("fleet init succeeds");

    assert_eq!(report.withheld, vec![ADVISORIES.to_owned()]);
    assert!(!target.join(ADVISORIES).exists());
    for path in RUST_ONLY.iter().filter(|path| **path != ADVISORIES) {
        assert_eq!(read(&target, path), content(path), "{path} differs");
    }
}

fn read(root: &Path, path: &str) -> String {
    fs::read_to_string(root.join(path)).unwrap_or_else(|error| panic!("read {path}: {error}"))
}
