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
        "4c71a19e59454ced5fe4475898f7614fd8f84a7d",
    ),
    (
        "export-agent",
        "repos/clients/export-agent",
        "38102df0987bfb6557b647c3a11ad904161e4628",
    ),
    (
        "extractor",
        "repos/extractor",
        "144cd7dce9930b8a1bdea5ef2355587fe7fa80fc",
    ),
    (
        "github",
        "repos/github",
        "7b702857e781384665d77209f93976271e96e956",
    ),
    (
        "instagram",
        "repos/social/instagram",
        "928d0c84448d8a50f6cb2ae666282a302f76ff69",
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
        "e2f3a8534521ad207ecedd1f8232cad5059e1f80",
    ),
    (
        "telegram",
        "repos/integrations/telegram",
        "40c8d1dfaa2bf754002e9b97cda2f3fa477fea8a",
    ),
    (
        "threads",
        "repos/social/threads",
        "9ece8690760bd7c1815b307cd813620c6deafdd7",
    ),
    (
        "vault",
        "repos/vault",
        "08c4fcfcd4376b8f4b61a01631cc1e1aeb8481d4",
    ),
    (
        "web",
        "repos/clients/web",
        "3ebb32a8414463d37c134402f12d2510cbf38e75",
    ),
    (
        "x",
        "repos/social/x",
        "30e1ccd2999bd0914439a723eafda605419152c6",
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
