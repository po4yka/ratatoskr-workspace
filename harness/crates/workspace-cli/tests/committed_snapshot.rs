//! Real committed WS-013 snapshot acceptance test.

#![allow(clippy::expect_used, clippy::panic)]

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use workspace_core::{
    compare_workspace_lock, generate_workspace_lock, inspect_baseline, inspect_git_topology,
    validate_manifest,
};

const EXPECTED_PINS: [(&str, &str, &str); 17] = [
    (
        "browser-extension",
        "repos/clients/browser-extension",
        "ff8bdd8e8816a499e34ba3aaefcfdd3879dea282",
    ),
    (
        "channel-digests",
        "repos/integrations/channel-digests",
        "a476079ec0115c38ab8c76e9280bf23a1ea89539",
    ),
    (
        "chatgpt",
        "repos/ai-archive/chatgpt",
        "c72a1faddb713afb43a95f44bb3f275c67789ac3",
    ),
    (
        "claude",
        "repos/ai-archive/claude",
        "f3194364cac2a1bbf8f4483670c08195415c47ce",
    ),
    (
        "contracts",
        "repos/contracts",
        "ad16855c4e7f3d52cd118274faa3b8f3ab4da576",
    ),
    (
        "export-agent",
        "repos/clients/export-agent",
        "da1acd41f20ce972b7530aad9c231ba7bd9b4a6c",
    ),
    (
        "extractor",
        "repos/extractor",
        "da1247ae3f842ee9ad1550fc0afc8780b5a16026",
    ),
    (
        "github",
        "repos/github",
        "dfb5a88090e9f84f1d9e48b27c47a8b7a1085c56",
    ),
    (
        "instagram",
        "repos/social/instagram",
        "956f0cb66c8357297db68140715f8413cd3f7adc",
    ),
    (
        "knowledge",
        "repos/knowledge",
        "3833d489d444270d854afa31e38dc87247d7e477",
    ),
    (
        "mobile",
        "repos/clients/mobile",
        "67646d3ec6f50a458b59ec50ccea0cec29981e98",
    ),
    (
        "platform",
        "repos/platform",
        "f13a78587009f2a6bd5369e413e5f56b83141c0d",
    ),
    (
        "telegram",
        "repos/integrations/telegram",
        "b43c62554b61cd70f89f581887d5903d74cdff5e",
    ),
    (
        "threads",
        "repos/social/threads",
        "51b0fdd968ab4817b6bf2bf63a5f0174dd78855c",
    ),
    (
        "vault",
        "repos/vault",
        "0a6c8d4700f7202633b5671e59341cb7d3f8bbc0",
    ),
    (
        "web",
        "repos/clients/web",
        "3c30f15f8d78d116aaf726e4ae085e8d2f317ea5",
    ),
    (
        "x",
        "repos/social/x",
        "f1810d5078eb688aa3715c2edb95e87e2d742e16",
    ),
];

#[test]
fn committed_workspace_is_complete_and_current() {
    let root = workspace_root();
    let manifest_source =
        fs::read_to_string(root.join("workspace.toml")).expect("committed workspace.toml exists");
    let manifest = validate_manifest(&manifest_source).expect("committed manifest is valid");
    let expected = EXPECTED_PINS
        .iter()
        .map(|(identity, path, commit)| (*identity, (*path, *commit)))
        .collect::<BTreeMap<_, _>>();

    assert_eq!(manifest.repositories().len(), expected.len());
    for repository in manifest.repositories() {
        let (path, _) = expected
            .get(repository.id.as_str())
            .expect("repository identity is audited");
        assert_eq!(&repository.path, path);
        assert!(!repository.digest_inputs.is_empty());
    }

    let topology = inspect_git_topology(&root, &manifest);
    assert!(
        topology.diagnostics.is_empty(),
        "committed topology is invalid: {:?}",
        topology.diagnostics
    );
    for pin in &topology.pins {
        let (_, commit) = expected.get(pin.id.as_str()).expect("pin is audited");
        assert_eq!(&pin.commit, commit);
    }
    assert!(inspect_baseline(&root, &topology).diagnostics.is_empty());

    let generated = generate_workspace_lock(&root, &manifest_source, &manifest, &topology)
        .expect("derive committed lock");
    assert!(
        generated
            .repositories
            .iter()
            .all(|repository| !repository.digests.is_empty())
    );
    let committed_lock =
        fs::read_to_string(root.join("workspace.lock")).expect("committed workspace.lock exists");
    assert!(
        compare_workspace_lock(&generated, &committed_lock).is_empty(),
        "committed lock is stale"
    );
}

fn workspace_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(3)
        .expect("workspace root ancestor")
        .to_owned()
}
