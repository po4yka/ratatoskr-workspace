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
        "08cf71e6677d120c9887286272ee352a9243006e",
    ),
    (
        "chatgpt",
        "repos/ai-archive/chatgpt",
        "1101452f2f4137d6c8805b0db5cca575e7834bc1",
    ),
    (
        "claude",
        "repos/ai-archive/claude",
        "a71701a45bd7db842926f41be23274adf429dd0e",
    ),
    (
        "contracts",
        "repos/contracts",
        "2c726027da79e0e899ad482afead0a2000b03e61",
    ),
    (
        "export-agent",
        "repos/clients/export-agent",
        "0ddda7164d72b7c100ff6334e14809e2d2ebda8c",
    ),
    (
        "extractor",
        "repos/extractor",
        "d1b7b012cbc9906509ad0a1fd22d3d735a43717e",
    ),
    (
        "github",
        "repos/github",
        "59bdddd8cb1a1f238c0b72765f76ce7adc1f8c8a",
    ),
    (
        "instagram",
        "repos/social/instagram",
        "3f32997b954a952e420963e7f8e8067dccaa1ef3",
    ),
    (
        "knowledge",
        "repos/knowledge",
        "9ce88f423889b005341f1a472012d4034f40896d",
    ),
    (
        "mobile",
        "repos/clients/mobile",
        "67646d3ec6f50a458b59ec50ccea0cec29981e98",
    ),
    (
        "notes",
        "repos/notes",
        "f39434654eedf3fe4371ceb1b077bf3ea18bc10d",
    ),
    (
        "obsidian-plugin",
        "repos/clients/obsidian-plugin",
        "5ed98a96387f0c47a8ce5dbe6847950c1b756896",
    ),
    (
        "platform",
        "repos/platform",
        "3a47f0f8a70203f74e432f20ade4c8bcd2fba034",
    ),
    (
        "site-sdk",
        "repos/clients/site-sdk",
        "89c683a872c2ca01c33efa1a969fd566fcef98ad",
    ),
    (
        "sites",
        "repos/sites",
        "d6aeab28d0f85c8617f77c2bc816b6fdc1e4b772",
    ),
    (
        "telegram",
        "repos/integrations/telegram",
        "0c424cc5c5858f1b212722923039c7f393b296a6",
    ),
    (
        "threads",
        "repos/social/threads",
        "20c3a9a276e97e1ce6bc9a1cc9ecbfa6b84b037b",
    ),
    (
        "vault",
        "repos/vault",
        "469ffef9616864b808766df8d0168f04acbb84ca",
    ),
    (
        "web",
        "repos/clients/web",
        "4972d4348d829f0cc9a32c4a606e53d31d4d80cd",
    ),
    (
        "x",
        "repos/social/x",
        "7de8f43a45edb75c4a7a13928983e857874ca400",
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
