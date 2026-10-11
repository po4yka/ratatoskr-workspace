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
        "cdbf87fbbc757d445c27c4e72950e755af29690e",
    ),
    (
        "chatgpt",
        "repos/ai-archive/chatgpt",
        "d994f8b7a05436d0cdc81de51f608c601d70a8ac",
    ),
    (
        "claude",
        "repos/ai-archive/claude",
        "49baae26bea34ecf3d87018ab8a2b96275ba12e3",
    ),
    (
        "contracts",
        "repos/contracts",
        "5426cf3096733d714c59b02ec41e946fdedcd94d",
    ),
    (
        "export-agent",
        "repos/clients/export-agent",
        "1009f2992a51e5a6ff54724d3a3bf762e1c30243",
    ),
    (
        "extractor",
        "repos/extractor",
        "b44ba81637ff8979f9e3ad4ebbea967335f6bd6b",
    ),
    (
        "github",
        "repos/github",
        "2bc979d27db9c82b5e347294cd48665769d4ecea",
    ),
    (
        "instagram",
        "repos/social/instagram",
        "79ae7767178b9a57a6a2a6e0f43a6218fcf4e88a",
    ),
    (
        "knowledge",
        "repos/knowledge",
        "542cd6998deaa7228dbdf1fe9d48bfb99a639ad8",
    ),
    (
        "mobile",
        "repos/clients/mobile",
        "67646d3ec6f50a458b59ec50ccea0cec29981e98",
    ),
    (
        "platform",
        "repos/platform",
        "075c7efca80adad938843faf7ae194a35386d55f",
    ),
    (
        "telegram",
        "repos/integrations/telegram",
        "81aa9e2116ea9e61faad5da594dd3ae28df0dc46",
    ),
    (
        "threads",
        "repos/social/threads",
        "e3656d08da406537cd63c143d3dba5520e1aa43a",
    ),
    (
        "vault",
        "repos/vault",
        "24573faf20882f3c55c47664c84f0b1458f8dff9",
    ),
    (
        "web",
        "repos/clients/web",
        "3c30f15f8d78d116aaf726e4ae085e8d2f317ea5",
    ),
    (
        "x",
        "repos/social/x",
        "4a32e8eaa39771a2926d6932ff08f84848d7ce8a",
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
