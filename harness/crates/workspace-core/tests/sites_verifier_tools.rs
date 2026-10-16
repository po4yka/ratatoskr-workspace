//! SITE-028 pins one credential-free verifier policy for the ARM64 host.
#[test]
fn runtime_tools_are_pinned_and_confined() -> Result<(), Box<dyn std::error::Error>> {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(3)
        .ok_or("missing workspace root")?;
    let bytes = std::fs::read(root.join("deploy/ansible/group_vars/all/sites-verifier.json"))
        .unwrap_or_default();
    assert!(!bytes.is_empty(), "Sites verifier policy is missing");
    let value: serde_json::Value = serde_json::from_slice(&bytes)?;
    let tools = value
        .get("ratatoskr_sites_verifier")
        .ok_or("missing tool policy")?;
    assert_eq!(
        tools
            .pointer("/gh/version")
            .and_then(serde_json::Value::as_str),
        Some("2.102.0")
    );
    assert_eq!(
        tools
            .pointer("/oras/version")
            .and_then(serde_json::Value::as_str),
        Some("1.3.0")
    );
    for tool in ["gh", "oras"] {
        let sha = tools
            .get(tool)
            .and_then(|tool| tool.get("arm64_sha256"))
            .and_then(serde_json::Value::as_str)
            .ok_or("missing ARM64 artifact digest")?;
        assert!(sha.len() == 64 && sha.bytes().all(|byte| byte.is_ascii_hexdigit()));
    }
    let signer = tools
        .get("signer_commit")
        .and_then(serde_json::Value::as_str)
        .ok_or("missing workflow revision")?;
    assert!(signer.len() == 40 && signer.bytes().all(|byte| byte.is_ascii_hexdigit()));
    let role =
        std::fs::read_to_string(root.join("deploy/ansible/roles/sites_verifier/tasks/main.yml"))?;
    assert!(role.contains("owner: root") && role.contains("checksum:") && role.contains("0755"));
    assert!(!role.contains("github_token") && !role.contains("GH_TOKEN"));
    let playbook = std::fs::read_to_string(root.join("deploy/ansible/site.yml"))?;
    assert!(playbook.contains("name: sites_verifier"));
    Ok(())
}
