//! The provisioning inventory and the pinned repositories agree (openspec `host-provisioning`).
//!
//! `deploy/ansible/group_vars/all/services.json` enrolls each systemd unit the playbook installs,
//! and lists each database role it provisions. This test holds it to the pinned children:
//!
//! - every `deploy/systemd/ratatoskr-*.service` a pinned repository ships is enrolled, and every
//!   enrolled service names a unit, a binary and a config example that the pinned repository has;
//! - every enrolled unit joins `ratatoskr.target` (`PartOf=` and `WantedBy=`);
//! - every pinned `deploy/postgres/role.sql` is provisioned, under the role name the file creates;
//! - `deploy/ansible/` holds no copy of a child deploy file and no secret in plain text. The
//!   playbook reads child files from the submodule at the pinned commit; a copy here would drift
//!   from its owner, which `postgres-provisioning` forbids.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

#[path = "support/checkout.rs"]
mod checkout;

use checkout::{
    committed_manifest, is_checked_out, repository_root, tracked_files, workspace_root,
};
use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

const SERVICES: &str = "deploy/ansible/group_vars/all/services.json";
const ANSIBLE: &str = "deploy/ansible";

#[derive(Debug, Deserialize)]
struct Inventory {
    ratatoskr_services: Vec<Service>,
    ratatoskr_database_roles: Vec<DatabaseRole>,
}

#[derive(Debug, Deserialize)]
struct Service {
    name: String,
    repository: String,
    unit: String,
    binary: String,
    config_example: String,
}

#[derive(Debug, Deserialize)]
struct DatabaseRole {
    repository: String,
    role: String,
}

fn inventory() -> Inventory {
    let path = workspace_root().join(SERVICES);
    let text = fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("{} must exist: {error}", path.display()));
    serde_json::from_str(&text).unwrap_or_else(|error| panic!("{SERVICES} is not valid: {error}"))
}

/// `(repository id, checkout root)` of every pinned repository, failing on one that is missing.
fn pinned() -> Vec<(String, PathBuf)> {
    committed_manifest()
        .repositories()
        .iter()
        .map(|repository| {
            let root = repository_root(repository);
            assert!(
                is_checked_out(&root),
                "repository `{}` is not checked out at {}; run `git submodule update --init {}`",
                repository.id,
                root.display(),
                repository.path
            );
            (repository.id.clone(), root)
        })
        .collect()
}

/// The basename of the first `ExecStart=` command of a unit.
fn exec_start_binary(unit: &str) -> Option<String> {
    unit.lines()
        .find_map(|line| line.strip_prefix("ExecStart="))
        .and_then(|command| {
            command
                .trim_start_matches(['-', '@', ':', '+', '!'])
                .split_whitespace()
                .next()
        })
        .and_then(|path| Path::new(path).file_name())
        .map(|name| name.to_string_lossy().into_owned())
}

/// Why the shipped units and the two inventory lists disagree. Each argument holds
/// `(repository id, unit file name)`.
fn enrolment_findings(
    services: &[(&str, &str)],
    _templates: &[(&str, &str)],
    shipped: &[(&str, &str)],
) -> Vec<String> {
    shipped
        .iter()
        .filter(|unit| !services.contains(unit))
        .map(|(id, unit)| {
            format!("{id}: deploy/systemd/{unit} ships and is not enrolled in {SERVICES}")
        })
        .collect()
}

/// The lines a unit is missing to join `ratatoskr.target`.
fn target_gaps(unit: &str) -> Vec<&'static str> {
    ["PartOf=ratatoskr.target", "WantedBy=ratatoskr.target"]
        .into_iter()
        .filter(|wanted| !unit.lines().any(|line| line.trim() == *wanted))
        .collect()
}

/// The role a `role.sql` creates: the name after `create role`.
fn created_role(sql: &str) -> Option<String> {
    let lower = sql.to_ascii_lowercase();
    let start = lower.find("create role ")? + "create role ".len();
    lower
        .get(start..)?
        .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
        .next()
        .filter(|name| !name.is_empty())
        .map(str::to_owned)
}

/// Why a file of the Ansible tree must not be there, if it must not.
fn tree_finding(relative: &str, text: &str) -> Option<String> {
    let name = relative.rsplit('/').next().unwrap_or(relative);
    if name.ends_with(".service")
        || name.ends_with(".target")
        || name.ends_with(".conf.example")
        || name == "role.sql"
    {
        return Some(format!(
            "{relative}: a child deploy file; read it from the submodule"
        ));
    }
    if name.contains("vault") && !text.starts_with("$ANSIBLE_VAULT;") {
        return Some(format!("{relative}: a vault file that is not encrypted"));
    }
    for line in text.lines() {
        let token = line.trim().trim_matches(|c| c == '"' || c == '\'');
        let seed = token.len() == 58
            && token.starts_with("SU")
            && token
                .bytes()
                .all(|b| b.is_ascii_uppercase() || (b'2'..=b'7').contains(&b));
        if seed {
            return Some(format!("{relative}: holds an nkey seed"));
        }
        if line.contains("PRIVATE KEY-----") {
            return Some(format!("{relative}: holds a private key"));
        }
    }
    None
}

fn walk(dir: &Path, root: &Path, out: &mut Vec<(String, String)>) {
    for entry in fs::read_dir(dir).expect("readable directory") {
        let path = entry.expect("directory entry").path();
        if path.is_dir() {
            walk(&path, root, out);
        } else if let Ok(text) = fs::read_to_string(&path) {
            let relative = path
                .strip_prefix(root)
                .expect("under the root")
                .to_string_lossy()
                .into_owned();
            out.push((relative, text));
        }
    }
}

#[test]
fn every_pinned_unit_is_enrolled() {
    let inventory = inventory();
    let enrolled = inventory
        .ratatoskr_services
        .iter()
        .map(|service| (service.repository.as_str(), service.unit.as_str()))
        .collect::<BTreeSet<_>>();
    let mut missing = Vec::new();
    for (id, root) in pinned() {
        for (path, _) in tracked_files(&root, "deploy/systemd/ratatoskr-*.service") {
            let unit = path.rsplit('/').next().unwrap_or(&path).to_owned();
            if !enrolled.contains(&(id.as_str(), unit.as_str())) {
                missing.push(format!(
                    "{id}: {path} ships and is not enrolled in {SERVICES}"
                ));
            }
        }
    }
    assert!(missing.is_empty(), "{}", missing.join("\n"));
}

#[test]
fn every_enrolled_service_has_a_pinned_unit() {
    let pinned = pinned().into_iter().collect::<BTreeMap<_, _>>();
    let mut wrong = Vec::new();
    for service in inventory().ratatoskr_services {
        let Some(root) = pinned.get(&service.repository) else {
            wrong.push(format!(
                "{}: repository `{}` is not pinned",
                service.name, service.repository
            ));
            continue;
        };
        let unit_path = root.join("deploy/systemd").join(&service.unit);
        let Ok(unit) = fs::read_to_string(&unit_path) else {
            wrong.push(format!(
                "{}: {} has no deploy/systemd/{}",
                service.name, service.repository, service.unit
            ));
            continue;
        };
        if exec_start_binary(&unit).as_deref() != Some(service.binary.as_str()) {
            wrong.push(format!(
                "{}: the unit starts {:?}, the enrolment says {}",
                service.name,
                exec_start_binary(&unit),
                service.binary
            ));
        }
        if !root.join(&service.config_example).is_file() {
            wrong.push(format!(
                "{}: {} has no {}",
                service.name, service.repository, service.config_example
            ));
        }
    }
    assert!(wrong.is_empty(), "{}", wrong.join("\n"));
}

#[test]
fn every_enrolled_unit_joins_ratatoskr_target() {
    let pinned = pinned().into_iter().collect::<BTreeMap<_, _>>();
    let mut gaps = Vec::new();
    for service in inventory().ratatoskr_services {
        let path = pinned
            .get(&service.repository)
            .map(|root| root.join("deploy/systemd").join(&service.unit))
            .expect("checked by every_enrolled_service_has_a_pinned_unit");
        let unit = fs::read_to_string(&path).unwrap_or_default();
        for line in target_gaps(&unit) {
            gaps.push(format!(
                "{}: {} lacks `{line}`",
                service.repository, service.unit
            ));
        }
    }
    assert!(gaps.is_empty(), "{}", gaps.join("\n"));
}

#[test]
fn every_pinned_role_file_is_provisioned() {
    let listed = inventory()
        .ratatoskr_database_roles
        .into_iter()
        .map(|role| (role.repository, role.role))
        .collect::<BTreeSet<_>>();
    let mut shipped = BTreeSet::new();
    let mut wrong = Vec::new();
    for (id, root) in pinned() {
        let path = root.join("deploy/postgres/role.sql");
        let Ok(sql) = fs::read_to_string(&path) else {
            continue;
        };
        match created_role(&sql) {
            Some(role) => {
                shipped.insert((id, role));
            }
            None => wrong.push(format!("{id}: deploy/postgres/role.sql creates no role")),
        }
    }
    for missing in shipped.difference(&listed) {
        wrong.push(format!(
            "{}: role {} is shipped and not provisioned",
            missing.0, missing.1
        ));
    }
    for extra in listed.difference(&shipped) {
        wrong.push(format!(
            "{}: role {} is provisioned and no role.sql creates it",
            extra.0, extra.1
        ));
    }
    assert!(wrong.is_empty(), "{}", wrong.join("\n"));
}

#[test]
fn the_ansible_tree_holds_no_child_deploy_file_or_plain_secret() {
    let root = workspace_root().join(ANSIBLE);
    let mut files = Vec::new();
    walk(&root, &root, &mut files);
    assert!(!files.is_empty(), "{ANSIBLE} holds no files");

    let mut child = BTreeMap::new();
    for (id, checkout) in pinned() {
        for (path, text) in tracked_files(&checkout, "deploy") {
            if text.len() >= 64 {
                child.insert(text, format!("{id}/{path}"));
            }
        }
    }

    let mut findings = Vec::new();
    for (relative, text) in &files {
        if let Some(finding) = tree_finding(relative, text) {
            findings.push(finding);
        }
        if let Some(owner) = child.get(text) {
            findings.push(format!("{relative}: a copy of {owner}"));
        }
    }
    assert!(findings.is_empty(), "{}", findings.join("\n"));
}

#[test]
fn a_template_unit_enrols_only_as_a_template_and_a_plain_unit_only_as_a_service() {
    let edge = ("platform", "ratatoskr-edge.service");
    let cleanup = ("notes", "ratatoskr-notes-cleanup@.service");
    let shipped = [edge, cleanup];
    let not_enrolled = |id: &str, unit: &str| {
        format!("{id}: deploy/systemd/{unit} ships and is not enrolled in {SERVICES}")
    };

    assert_eq!(
        enrolment_findings(&[edge], &[cleanup], &shipped),
        Vec::<String>::new()
    );
    assert_eq!(
        enrolment_findings(&[edge, cleanup], &[], &shipped),
        vec![
            not_enrolled(cleanup.0, cleanup.1),
            "notes: ratatoskr-notes-cleanup@.service is a template unit and is listed in \
             ratatoskr_services; list it in ratatoskr_template_units"
                .to_owned(),
        ]
    );
    assert_eq!(
        enrolment_findings(&[], &[edge, cleanup], &shipped),
        vec![
            not_enrolled(edge.0, edge.1),
            "platform: ratatoskr-edge.service is not a template unit and is listed in \
             ratatoskr_template_units; list it in ratatoskr_services"
                .to_owned(),
        ]
    );
    assert_eq!(
        enrolment_findings(
            &[edge],
            &[cleanup, ("notes", "ratatoskr-notes-sync@.service")],
            &shipped
        ),
        vec![
            "notes: ratatoskr-notes-sync@.service is listed in ratatoskr_template_units and the \
             pinned repository does not ship it"
                .to_owned()
        ]
    );
}

#[test]
fn the_checks_catch_what_they_claim_to() {
    let unit = "[Unit]\nPartOf=ratatoskr.target\n[Service]\nExecStart=-/usr/local/bin/svc --x\n";
    assert_eq!(exec_start_binary(unit).as_deref(), Some("svc"));
    assert_eq!(target_gaps(unit), vec!["WantedBy=ratatoskr.target"]);
    assert_eq!(
        created_role("do $$ begin\n  create role ratatoskr_x login;\nend $$;").as_deref(),
        Some("ratatoskr_x")
    );
    assert!(tree_finding("roles/x/files/ratatoskr-edge.service", "").is_some());
    assert!(tree_finding("files/role.sql", "").is_some());
    assert!(tree_finding("inventories/production/secrets.vault.yml", "token: x").is_some());
    assert!(
        tree_finding(
            "inventories/production/secrets.vault.yml",
            "$ANSIBLE_VAULT;1.1;AES256\n6162"
        )
        .is_none()
    );
    let seed = format!("SU{}", "A".repeat(56));
    assert!(tree_finding("group_vars/all/x.yml", &format!("seed: \"{seed}\"\n")).is_none());
    assert!(tree_finding("group_vars/all/x.yml", &format!("{seed}\n")).is_some());
    assert!(tree_finding("files/key", "-----BEGIN PRIVATE KEY-----\n").is_some());
    assert!(tree_finding("roles/host/tasks/main.yml", "- name: users\n").is_none());
}
