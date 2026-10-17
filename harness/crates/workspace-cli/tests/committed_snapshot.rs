//! Real committed WS-013 snapshot acceptance test.

#![allow(clippy::expect_used, clippy::panic)]

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use workspace_core::{
    compare_workspace_lock, generate_workspace_lock, inspect_baseline, inspect_git_topology,
    validate_manifest,
};

const EXPECTED_PINS: [(&str, &str, &str); 21] = [
    (
        "browser-extension",
        "repos/clients/browser-extension",
        "0aceedd44d2c9448c817cf6464fa6ea81917fd1c",
    ),
    (
        "channel-digests",
        "repos/integrations/channel-digests",
        "46efd8fb9e4c93abf5651bac030ee252fb997ef0",
    ),
    (
        "chatgpt",
        "repos/ai-archive/chatgpt",
        "63a4506b39315749aab71d3fe3e9193fe23aa0e2",
    ),
    (
        "claude",
        "repos/ai-archive/claude",
        "fc759137a7b6fc790d9e6266a94b82d444c91bba",
    ),
    (
        "contracts",
        "repos/contracts",
        "1756034314a15d3a83d5c7d15b172da502990e98",
    ),
    (
        "export-agent",
        "repos/clients/export-agent",
        "e4be3b4fd54d17f85e9952097f1ded38f031d801",
    ),
    (
        "extractor",
        "repos/extractor",
        "4295e5a181d2f52ae2db56c26fd9ff830616eec1",
    ),
    (
        "github",
        "repos/github",
        "22813f5dada06c31ae8df503ffc5e69bea793a8a",
    ),
    (
        "instagram",
        "repos/social/instagram",
        "bd2e1096fc94af4e0c9bcf7abb5e336ec9c431e5",
    ),
    (
        "knowledge",
        "repos/knowledge",
        "fff1bacc63636cf27868c1ff1bcc509d4dfc9d4c",
    ),
    (
        "mobile",
        "repos/clients/mobile",
        "67646d3ec6f50a458b59ec50ccea0cec29981e98",
    ),
    (
        "notes",
        "repos/notes",
        "ac9866961533dad955450a2eb356d834bda19501",
    ),
    (
        "obsidian-plugin",
        "repos/clients/obsidian-plugin",
        "36bdb20404dca9a49b804e6245248c1ba194821c",
    ),
    (
        "platform",
        "repos/platform",
        "83dcba6498ebaf2a3b7a97739d64b47ca47c25a8",
    ),
    (
        "site-sdk",
        "repos/clients/site-sdk",
        "0df7963db8facd15d5713a5fa01800198539e2a6",
    ),
    (
        "sites",
        "repos/sites",
        "3cb379225cfa2bb5da9d0e83d94e877b835b1921",
    ),
    (
        "telegram",
        "repos/integrations/telegram",
        "c9552c8bfa64577970297ed103485a0706d936fb",
    ),
    (
        "threads",
        "repos/social/threads",
        "3b11fd1464b9afe721d350868a3f6fa2639aaec8",
    ),
    (
        "vault",
        "repos/vault",
        "53e8dc92bc1072f280cb7e72ec7d2436540945d4",
    ),
    (
        "web",
        "repos/clients/web",
        "3f7da8f1a6ef368b7cf7354a17d497ef96a4bc64",
    ),
    (
        "x",
        "repos/social/x",
        "81929848e0c3e75fe19219c6d261f2cbeaaa4336",
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
