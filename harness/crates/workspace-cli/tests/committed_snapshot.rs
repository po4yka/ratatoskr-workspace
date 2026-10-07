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
        "c0853285b2201b500e03b7d2ed9ffdfe3154cb27",
    ),
    (
        "channel-digests",
        "repos/integrations/channel-digests",
        "44768fc91d6fd3058d5237a0042b06d9153b3944",
    ),
    (
        "chatgpt",
        "repos/ai-archive/chatgpt",
        "be32839a4ec48a71cc2d9db1d1c9e3629ec1e795",
    ),
    (
        "claude",
        "repos/ai-archive/claude",
        "3d5d2020ce3e14d429c4fd491913ec37bcab3b4d",
    ),
    (
        "contracts",
        "repos/contracts",
        "cac6c8d5aea25fa0f9ad96b08b8db992a44b4b29",
    ),
    (
        "export-agent",
        "repos/clients/export-agent",
        "38102df0987bfb6557b647c3a11ad904161e4628",
    ),
    (
        "extractor",
        "repos/extractor",
        "68afae406b0e5fc624feb57ee460b59600fb4207",
    ),
    (
        "github",
        "repos/github",
        "17487140690bb162478378a117b6b62609b5f9c6",
    ),
    (
        "instagram",
        "repos/social/instagram",
        "9f134c5075eab65eb432aa3922bf2256c4c8de02",
    ),
    (
        "knowledge",
        "repos/knowledge",
        "269c269465c49b4112eb0846dfa5088c760c990c",
    ),
    (
        "mobile",
        "repos/clients/mobile",
        "67646d3ec6f50a458b59ec50ccea0cec29981e98",
    ),
    (
        "platform",
        "repos/platform",
        "c3d0d3979106b690ae2b0d8450b42e37264d857a",
    ),
    (
        "telegram",
        "repos/integrations/telegram",
        "8394d7ded7fc7feba0cb46d68c0e0f4df70a6c08",
    ),
    (
        "threads",
        "repos/social/threads",
        "9ece8690760bd7c1815b307cd813620c6deafdd7",
    ),
    (
        "vault",
        "repos/vault",
        "c4ee86c5ca5589871c0e6cf1da87c7f70f8f830d",
    ),
    (
        "web",
        "repos/clients/web",
        "3c30f15f8d78d116aaf726e4ae085e8d2f317ea5",
    ),
    (
        "x",
        "repos/social/x",
        "b1bb58186e786e80ed539f9552b067bc4dd2a2fa",
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
