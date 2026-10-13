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
        "0aceedd44d2c9448c817cf6464fa6ea81917fd1c",
    ),
    (
        "channel-digests",
        "repos/integrations/channel-digests",
        "65a5df7a7f1d6c82a1ce6213cacb980897680d58",
    ),
    (
        "chatgpt",
        "repos/ai-archive/chatgpt",
        "6e9508764be8f9f876f4ddee611707951459b3a5",
    ),
    (
        "claude",
        "repos/ai-archive/claude",
        "272b6833d7207241416c1b8b00012ade4e234f22",
    ),
    (
        "contracts",
        "repos/contracts",
        "d98967b7b7ee80442c93ef4657140068955c8f61",
    ),
    (
        "export-agent",
        "repos/clients/export-agent",
        "22c14fdc8310b043772cc0ea6874abae575a66b0",
    ),
    (
        "extractor",
        "repos/extractor",
        "b5655232c10df6253bab2e9f97e13f913cf21547",
    ),
    (
        "github",
        "repos/github",
        "80aaa84a4c581336f88e034aeb8799248e010c22",
    ),
    (
        "instagram",
        "repos/social/instagram",
        "171caf11830e786900a7aafe88689f5e87f54b23",
    ),
    (
        "knowledge",
        "repos/knowledge",
        "577ccc3935ae0620d9952d05a42b7f4da2e18f42",
    ),
    (
        "mobile",
        "repos/clients/mobile",
        "67646d3ec6f50a458b59ec50ccea0cec29981e98",
    ),
    (
        "platform",
        "repos/platform",
        "3275d523d004787aa5871266b8636dd0b11e74e6",
    ),
    (
        "telegram",
        "repos/integrations/telegram",
        "a8a337ad504e2a7f89a218fa972edcfa6078193e",
    ),
    (
        "threads",
        "repos/social/threads",
        "e8cb95cfb074ae87c01c4fe8dca5f0988f687ba0",
    ),
    (
        "vault",
        "repos/vault",
        "b810b26b730de840fb2aa3225165d7a677df80a8",
    ),
    (
        "web",
        "repos/clients/web",
        "3c30f15f8d78d116aaf726e4ae085e8d2f317ea5",
    ),
    (
        "x",
        "repos/social/x",
        "cf21321f1286ebaa85181b498cf76a5687211978",
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
