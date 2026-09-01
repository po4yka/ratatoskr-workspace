//! Manifest contract tests.

#![allow(clippy::panic)]

#[path = "support/manifest.rs"]
mod support;

use support::{complete_manifest, repository};
use workspace_core::validate_manifest;

#[test]
fn complete_fleet_manifest_is_accepted() {
    let result = validate_manifest(&complete_manifest());

    assert!(result.is_ok(), "complete manifest was rejected: {result:?}");
}

#[test]
fn duplicate_identity_is_rejected() {
    let mut source = complete_manifest();
    source.push_str(&repository("x"));

    let result = validate_manifest(&source);

    assert!(
        matches!(result, Err(ref diagnostics) if diagnostics.iter().any(|diagnostic| diagnostic.code == "manifest.repository.duplicate")),
        "duplicate repository identity was accepted: {result:?}"
    );
}

#[test]
fn commit_fields_are_rejected() {
    let mut source = complete_manifest();
    source.push_str("commit = \"0123456789012345678901234567890123456789\"\n");

    let result = validate_manifest(&source);

    assert!(
        matches!(result, Err(ref diagnostics) if diagnostics.iter().any(|diagnostic| diagnostic.code == "manifest.parse")),
        "manifest commit field was accepted: {result:?}"
    );
}

#[test]
fn missing_required_repository_is_rejected() {
    let source = complete_manifest().replace(&repository("x"), "");

    let result = validate_manifest(&source);

    assert!(
        matches!(result, Err(ref diagnostics) if diagnostics.iter().any(|diagnostic| diagnostic.code == "manifest.repository.missing" && diagnostic.message.contains("`x`"))),
        "incomplete fleet manifest was accepted: {result:?}"
    );
}
