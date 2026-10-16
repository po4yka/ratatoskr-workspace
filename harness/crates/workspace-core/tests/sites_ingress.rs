//! The managed ingress contains exactly the site's approved host routes.
#![allow(dead_code, clippy::expect_used, clippy::panic)]
#[path = "support/checkout.rs"]
mod checkout;
use std::fs;

const BEGIN: &str = "# BEGIN ratatoskr-sites";
const END: &str = "# END ratatoskr-sites";
fn rules(config: &str, hostnames: &[&str]) -> bool {
    let Some((_, rest)) = config.split_once(BEGIN) else {
        return false;
    };
    let Some((block, _)) = rest.split_once(END) else {
        return false;
    };
    hostnames.iter().all(|host| {
        block
            .matches(&format!(
                "hostname: {host}\n    service: http://127.0.0.1:8183"
            ))
            .count()
            == 1
    }) && block.matches("service: http://127.0.0.1:8183").count() == hostnames.len()
}
fn no_outside(config: &str) -> bool {
    let Some((before, rest)) = config.split_once(BEGIN) else {
        return false;
    };
    let Some((_, after)) = rest.split_once(END) else {
        return false;
    };
    !before.contains(":8183") && !after.contains(":8183")
}
fn rendered(hostnames: &[&str]) -> String {
    // Render the committed Jinja template with the same engine that Ansible uses.
    let root = checkout::workspace_root();
    let output = std::process::Command::new("python3").args(["-c", "import sys,json; from jinja2 import Environment, FileSystemLoader; e=Environment(loader=FileSystemLoader(sys.argv[1])); print(e.get_template('sites-ingress.j2').render(ratatoskr_sites_hostnames=json.loads(sys.argv[2])))", root.join("deploy/ansible/roles/host/templates").to_str().expect("UTF-8 path"), &serde_json::to_string(hostnames).expect("hostname JSON")]).output().expect("python3 starts");
    assert!(
        output.status.success(),
        "ingress template must render: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).expect("template is UTF-8")
}
#[test]
fn every_listed_hostname_has_one_rule_inside_the_block() {
    let hosts = ["garden.example.test", "notes.example.test"];
    let template = rendered(&hosts);
    assert!(
        rules(&template, &hosts),
        "every hostname needs one gateway rule inside the block"
    );
    assert!(!rules(
        &template.replace("garden.example.test", "other.example.test"),
        &hosts
    ));
    assert!(!rules(
        &template.replace("http://127.0.0.1:8183", "http://127.0.0.1:8184"),
        &hosts
    ));
    let sites = fs::read_to_string(
        checkout::workspace_root().join("deploy/ansible/group_vars/all/sites.json"),
    )
    .expect("sites.json exists");
    let value: serde_json::Value = serde_json::from_str(&sites).expect("valid JSON");
    let hosts = value
        .get("ratatoskr_sites_hostnames")
        .and_then(serde_json::Value::as_array)
        .expect("sites.json holds a hostname list");
    let hosts: Vec<&str> = hosts
        .iter()
        .map(|host| host.as_str().expect("a hostname string"))
        .collect();
    assert!(
        rules(&rendered(&hosts), &hosts),
        "the configured hostname list must render exactly"
    );
}
#[test]
fn no_rule_outside_the_block_points_to_the_gateway() {
    let template = rendered(&["garden.example.test"]);
    assert!(no_outside(&template));
    assert!(!no_outside(&format!(
        "- hostname: stray.test\n  service: http://127.0.0.1:8183\n{template}"
    )));
    assert!(!no_outside(&format!(
        "{template}\n- hostname: stray.test\n  service: http://127.0.0.1:8183\n"
    )));
}
