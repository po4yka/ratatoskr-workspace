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
        "ab638527da008b55b4787ad37a51dc46237bd00c",
    ),
    (
        "chatgpt",
        "repos/ai-archive/chatgpt",
        "7dc1ef8fe208778967a4259ee8996d13469115b6",
    ),
    (
        "claude",
        "repos/ai-archive/claude",
        "bc07c0235cc909e48d220640014b15bb807da6db",
    ),
    (
        "contracts",
        "repos/contracts",
        "66bdb0c0545363f06137f13687084c21db9b27c5",
    ),
    (
        "export-agent",
        "repos/clients/export-agent",
        "e4be3b4fd54d17f85e9952097f1ded38f031d801",
    ),
    (
        "extractor",
        "repos/extractor",
        "9bbb68cad6670c72a0869c236bc26d5b91b832bc",
    ),
    (
        "github",
        "repos/github",
        "a66c503f4f6a6022a023eb3a2b6307e0a985716a",
    ),
    (
        "instagram",
        "repos/social/instagram",
        "dac7d4fe8d663bcb36e287b4f4cff19d94aab107",
    ),
    (
        "knowledge",
        "repos/knowledge",
        "0e6e447b77a38c374c7ab1a14064c5e668c02c04",
    ),
    (
        "mobile",
        "repos/clients/mobile",
        "67646d3ec6f50a458b59ec50ccea0cec29981e98",
    ),
    (
        "notes",
        "repos/notes",
        "5076346c7f66decd4a7b908155038f46c6d023ef",
    ),
    (
        "obsidian-plugin",
        "repos/clients/obsidian-plugin",
        "36bdb20404dca9a49b804e6245248c1ba194821c",
    ),
    (
        "platform",
        "repos/platform",
        "16b502ed502dfcdcfe6ce8574d794f4a303d4dce",
    ),
    (
        "site-sdk",
        "repos/clients/site-sdk",
        "f802e0ab8d4235b3b230ebd61eaa5c1668ea7610",
    ),
    (
        "sites",
        "repos/sites",
        "8bcfe8b8246438ee28a96ee08a6258fb474d2407",
    ),
    (
        "telegram",
        "repos/integrations/telegram",
        "07160e1f6ec6eebee3463c6b4db45095ce684f76",
    ),
    (
        "threads",
        "repos/social/threads",
        "9376ce9235cf41e73c56fd0d16913a1737709fac",
    ),
    (
        "vault",
        "repos/vault",
        "09232320353dc4bb467aa1ccad688706e5b3e535",
    ),
    (
        "web",
        "repos/clients/web",
        "5a83900de6ceb2c3c3632642beeb362f5a50a1eb",
    ),
    (
        "x",
        "repos/social/x",
        "5c6cdd76a7f152d56dd53be70654c6a21ca0b1b0",
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
