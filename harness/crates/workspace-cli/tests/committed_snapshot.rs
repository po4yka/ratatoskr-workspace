//! Real committed WS-013 snapshot acceptance test.

#![allow(clippy::expect_used, clippy::panic)]

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use workspace_core::{
    compare_workspace_lock, generate_workspace_lock, inspect_baseline, inspect_git_topology,
    validate_manifest,
};

const EXPECTED_PINS: [(&str, &str, &str); 18] = [
    (
        "browser-extension",
        "repos/clients/browser-extension",
        "0aceedd44d2c9448c817cf6464fa6ea81917fd1c",
    ),
    (
        "channel-digests",
        "repos/integrations/channel-digests",
        "95e625247af8bf667e4c860e9a98c82778fc71c2",
    ),
    (
        "chatgpt",
        "repos/ai-archive/chatgpt",
        "4e5b06d9cfc544c95cc827e6623631173ff4fb84",
    ),
    (
        "claude",
        "repos/ai-archive/claude",
        "91e259f8a65a29800b2faa4162af16685346bbb2",
    ),
    (
        "contracts",
        "repos/contracts",
        "a9289e27bcf53f496b5917889580965d97ff2358",
    ),
    (
        "export-agent",
        "repos/clients/export-agent",
        "22c14fdc8310b043772cc0ea6874abae575a66b0",
    ),
    (
        "extractor",
        "repos/extractor",
        "6c34bbc2d9e6993b6223ad31b280e2e7daa3111b",
    ),
    (
        "github",
        "repos/github",
        "035cf8c93d844dac0b7ea0c172d484d92a33e498",
    ),
    (
        "instagram",
        "repos/social/instagram",
        "a31c54842ed840777742d8b454412f471122d12c",
    ),
    (
        "knowledge",
        "repos/knowledge",
        "c08df4b33147362d7435bedca797d5644cd6646e",
    ),
    (
        "mobile",
        "repos/clients/mobile",
        "67646d3ec6f50a458b59ec50ccea0cec29981e98",
    ),
    (
        "notes",
        "repos/notes",
        "1d09bc00761b3da491728f1c599a5edaf69c3dc3",
    ),
    (
        "platform",
        "repos/platform",
        "47c7fe47147735c61cac61eb87cb0bf6079c772c",
    ),
    (
        "telegram",
        "repos/integrations/telegram",
        "cd78de402b5b1935482ded5a4512f2760959b661",
    ),
    (
        "threads",
        "repos/social/threads",
        "ec653ba8e5e03fa9b5226f937ebf94594422396e",
    ),
    (
        "vault",
        "repos/vault",
        "6c3af29d7f283f7862ca4776aa4da2936bbf9c13",
    ),
    (
        "web",
        "repos/clients/web",
        "3c30f15f8d78d116aaf726e4ae085e8d2f317ea5",
    ),
    (
        "x",
        "repos/social/x",
        "dbbae909c1af2d884c97db48ba8461ac0c2f261f",
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
