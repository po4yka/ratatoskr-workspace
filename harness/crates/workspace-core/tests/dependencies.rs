//! Dependency graph contract tests.

#![allow(clippy::panic)]

#[path = "support/manifest.rs"]
mod support;

use support::{complete_manifest, repository, repository_with_dependencies};
use workspace_core::{dependency_order, validate_manifest};

#[test]
fn valid_graph_has_stable_order() {
    let source = complete_manifest()
        .replace(
            &repository("platform"),
            &repository_with_dependencies(
                "platform",
                &[("contracts", "contract", "shared event envelopes")],
            ),
        )
        .replace(
            &repository("instagram"),
            &repository_with_dependencies(
                "instagram",
                &[("platform", "runtime", "durable event publication")],
            ),
        )
        .replace(
            &repository("knowledge"),
            &repository_with_dependencies(
                "knowledge",
                &[("instagram", "event", "captured social documents")],
            ),
        );
    let manifest = validate_manifest(&source);
    assert!(manifest.is_ok(), "graph fixture was rejected: {manifest:?}");

    let order = manifest.and_then(|manifest| dependency_order(&manifest));

    assert_eq!(
        order,
        Ok(vec![
            "browser-extension".to_owned(),
            "chatgpt".to_owned(),
            "claude".to_owned(),
            "contracts".to_owned(),
            "export-agent".to_owned(),
            "extractor".to_owned(),
            "github".to_owned(),
            "mobile".to_owned(),
            "platform".to_owned(),
            "instagram".to_owned(),
            "knowledge".to_owned(),
            "telegram".to_owned(),
            "threads".to_owned(),
            "vault".to_owned(),
            "web".to_owned(),
            "x".to_owned(),
        ])
    );
}

#[test]
fn unknown_dependency_is_rejected() {
    let source = complete_manifest().replace(
        &repository("x"),
        &repository_with_dependencies(
            "x",
            &[("missing-provider", "event", "captured social events")],
        ),
    );
    let result = validate_manifest(&source).and_then(|manifest| dependency_order(&manifest));

    assert!(
        matches!(result, Err(ref diagnostics) if diagnostics.iter().any(|diagnostic| {
            diagnostic.code == "manifest.dependency.unknown"
                && diagnostic.message.contains("`x`")
                && diagnostic.message.contains("`missing-provider`")
        })),
        "unknown dependency did not produce complete diagnostics: {result:?}"
    );
}

#[test]
fn complete_cycle_is_reported() {
    let source = complete_manifest()
        .replace(
            &repository("contracts"),
            &repository_with_dependencies("contracts", &[("x", "contract", "cycle fixture")]),
        )
        .replace(
            &repository("platform"),
            &repository_with_dependencies(
                "platform",
                &[("contracts", "contract", "cycle fixture")],
            ),
        )
        .replace(
            &repository("x"),
            &repository_with_dependencies("x", &[("platform", "runtime", "cycle fixture")]),
        );
    let result = validate_manifest(&source).and_then(|manifest| dependency_order(&manifest));

    assert_eq!(
        result,
        Err(vec![workspace_core::ManifestDiagnostic {
            code: "manifest.dependency.cycle",
            message: "dependency cycle contains repositories: `contracts`, `platform`, `x`"
                .to_owned(),
        }])
    );
}
