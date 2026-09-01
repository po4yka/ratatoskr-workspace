//! Real committed WS-013 snapshot acceptance test.

#![allow(clippy::expect_used, clippy::panic)]

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use workspace_core::{
    compare_workspace_lock, generate_workspace_lock, inspect_baseline, inspect_git_topology,
    validate_manifest,
};

const EXPECTED_PINS: [(&str, &str, &str); 16] = [
    (
        "browser-extension",
        "repos/clients/browser-extension",
        "79bcba985135c4a71a0c7734adb9d855cedbdb53",
    ),
    (
        "chatgpt",
        "repos/ai-archive/chatgpt",
        "875e99abd6d0d550ac6d05040f31f6ba3e42c422",
    ),
    (
        "claude",
        "repos/ai-archive/claude",
        "39985a18a9200ce07bb927a8ebbeb7d1530c2c59",
    ),
    (
        "contracts",
        "repos/contracts",
        "d43b62a402f47984c95037c158ec29c5ee62ee5c",
    ),
    (
        "export-agent",
        "repos/clients/export-agent",
        "fcb1397372bda0608316cb80b200bd2bd86e36f4",
    ),
    (
        "extractor",
        "repos/extractor",
        "e380202073190bd6e21e0ea36f236fc150732ebc",
    ),
    (
        "github",
        "repos/github",
        "fd60dd37e22b30056d2153ef22b271f75659e654",
    ),
    (
        "instagram",
        "repos/social/instagram",
        "4161a83db86335637e234737024687ff79e2095e",
    ),
    (
        "knowledge",
        "repos/knowledge",
        "25fb4a92d8b9ebcc3f15c4f2c9bfd8ee6b027ba1",
    ),
    (
        "mobile",
        "repos/clients/mobile",
        "c496046fb0718b727e54e14071d61f2ed148e3d4",
    ),
    (
        "platform",
        "repos/platform",
        "070b718238c4e6e45a5b7fc08ebe719ed5374e33",
    ),
    (
        "telegram",
        "repos/integrations/telegram",
        "f814cdde49cd76000b7a20bb497a840b52fa99e0",
    ),
    (
        "threads",
        "repos/social/threads",
        "1b69c3f6e6d89116981b9bd629cdec25d65a9756",
    ),
    (
        "vault",
        "repos/vault",
        "27843706b7bfad46c9d263740bf8da9f75772d65",
    ),
    (
        "web",
        "repos/clients/web",
        "48b21c5fdcf9b85705ab2942b4b2db57a61728b2",
    ),
    (
        "x",
        "repos/social/x",
        "a16b50b4425fe92c789f326fdac2a26712b18e7b",
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
