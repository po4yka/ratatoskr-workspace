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
        "70011f9e9c57877caf2f75ae0ba436456845ad5f",
    ),
    (
        "channel-digests",
        "repos/integrations/channel-digests",
        "30d6cd74b429f85f2a59f754b755cf800a1c8520",
    ),
    (
        "chatgpt",
        "repos/ai-archive/chatgpt",
        "bd852e8483603423cd08f1a79c452b7946974c48",
    ),
    (
        "claude",
        "repos/ai-archive/claude",
        "c242ac567c0ac7278f1a43b99ca39875847ac2dc",
    ),
    (
        "contracts",
        "repos/contracts",
        "5426cf3096733d714c59b02ec41e946fdedcd94d",
    ),
    (
        "export-agent",
        "repos/clients/export-agent",
        "da1acd41f20ce972b7530aad9c231ba7bd9b4a6c",
    ),
    (
        "extractor",
        "repos/extractor",
        "cf64d84cb6f41c929fd9b836fd47bb3f57bd23dc",
    ),
    (
        "github",
        "repos/github",
        "7891aea45541192a0201e8ec61d430253dbabcee",
    ),
    (
        "instagram",
        "repos/social/instagram",
        "b4d13176e3b728ae69f55148f34f84da5e0f87f7",
    ),
    (
        "knowledge",
        "repos/knowledge",
        "14326b4b1a5f83b83d601c3df17dd9726aae1248",
    ),
    (
        "mobile",
        "repos/clients/mobile",
        "67646d3ec6f50a458b59ec50ccea0cec29981e98",
    ),
    (
        "platform",
        "repos/platform",
        "8f8a8d8318f3c4ad44a508f8124cf923bc5552e8",
    ),
    (
        "telegram",
        "repos/integrations/telegram",
        "869333b8d78395526096f183b219afba71ca8573",
    ),
    (
        "threads",
        "repos/social/threads",
        "9cf3707cdb26f6782392e102d8fd65d03724d9b8",
    ),
    (
        "vault",
        "repos/vault",
        "24adc4cd782fdcc17a33890488cfc8376979186d",
    ),
    (
        "web",
        "repos/clients/web",
        "3c30f15f8d78d116aaf726e4ae085e8d2f317ea5",
    ),
    (
        "x",
        "repos/social/x",
        "da4ab3d8e9674f4b2e126266a6179702a01e0254",
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
