//! Edge upstream contract: every address in Platform's `RATATOSKR__GATEWAY__ROUTES__<NAME>__LISTENER`
//! list must be bound by the repository that owns the service, unless no service implements that
//! route on purpose.
//!
//! Why the check exists: before XR-021 round 2 the `ChatGPT` receipt and Knowledge's library routes
//! were served only on their operator listeners, and the workspace profiles hid it by overloading
//! the operator address with the Edge route port. Edge's probe of the route port was refused and
//! the provider never became ready. A route whose port nobody binds is a silent outage, so the
//! harness reads both sides and fails when they disagree.
//!
//! Regex sanity check. A bind is a line that, after dropping leading `#` and whitespace, is
//! `RATATOSKR__<...>__BIND`, `__LISTEN_ADDRESS` or `__LISTENER` `=` `host:port` (the matcher in
//! `support/binds.rs`, shared with `port_allocation.rs`). Matches at the round 2 pins (Platform
//! `8f8a8d8`):
//!
//! - platform `deploy/systemd/edge.conf.example`: nine `GATEWAY__ROUTES__<NAME>__LISTENER` lines,
//!   KNOWLEDGE 8091, GITHUB 8092, VAULT 8093, SOCIAL 8094, AI 8095, CHATGPT 8096, CLAUDE 8097 and
//!   the channel-digests listener 8098, which is not a route and is ignored here (the key does not
//!   start with `RATATOSKR__GATEWAY__ROUTES__`).
//! - knowledge `knowledge.conf.example`: `API__LISTEN_ADDRESS` 8091 beside `ADMIN__LISTEN_ADDRESS` 9081.
//! - github `github.conf.example`: `API__LISTEN_ADDRESS` 8092 beside `ADMIN__LISTEN_ADDRESS` 9095.
//! - chatgpt `chatgpt.conf.example`: `RECEIPT__LISTEN_ADDRESS` 8096 beside `ADMIN__LISTEN_ADDRESS` 9085.
//! - claude `claude.conf.example`: `RECEIPT__LISTEN_ADDRESS` 8097 beside `ADMIN__LISTEN_ADDRESS` 9086.
//!
//! What it cannot see: that the service really serves the route on that listener (the service's own
//! tests and the native smoke do that), and a bind assembled from several keys. A bind under an
//! `__ADMIN__` key never satisfies a route, because the operator listener is host-only by design.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

#[path = "support/binds.rs"]
mod binds;
#[path = "support/checkout.rs"]
mod checkout;

use binds::{bind_of, example_files};
use checkout::{committed_manifest, require_checkout};
use std::collections::BTreeMap;
use std::fs;

const ROUTE_PREFIX: &str = "RATATOSKR__GATEWAY__ROUTES__";
const ROUTE_SUFFIX: &str = "__LISTENER";

/// Routes with an implementing service: `(route name, owning repository)`.
const IMPLEMENTED: [(&str, &str); 4] = [
    ("KNOWLEDGE", "knowledge"),
    ("GITHUB", "github"),
    ("CHATGPT", "chatgpt"),
    ("CLAUDE", "claude"),
];

/// Routes that have no implementing service, with the port Edge keeps for them.
const UNIMPLEMENTED: [(&str, u16); 3] = [("VAULT", 8093), ("SOCIAL", 8094), ("AI", 8095)];

const UNIMPLEMENTED_REASON: &str = "no service implements the vault (8093), social (8094) or \
ai-archive (8095) domain API yet; Edge reports their capability stale on purpose (XR-021 R2-01 \
rule 3). When one is implemented, move its name to IMPLEMENTED so the owner has to bind it.";

/// `route name -> port` for every gateway route of an Edge example.
fn routes_of(edge_example: &str) -> BTreeMap<String, u16> {
    edge_example
        .lines()
        .filter_map(bind_of)
        .filter_map(|(key, port)| {
            let name = key
                .strip_prefix(ROUTE_PREFIX)?
                .strip_suffix(ROUTE_SUFFIX)?
                .to_owned();
            Some((name, port))
        })
        .collect()
}

/// Problems with a route table: a name in neither group, or an unimplemented route whose port moved.
fn classification_problems(routes: &BTreeMap<String, u16>) -> Vec<String> {
    let mut problems = Vec::new();
    for (name, port) in routes {
        if IMPLEMENTED
            .iter()
            .any(|(implemented, _)| implemented == name)
        {
            continue;
        }
        match UNIMPLEMENTED.iter().find(|(known, _)| known == name) {
            None => problems.push(format!(
                "Edge route `{name}` ({port}) is in neither group of edge_upstreams.rs: add it to \
                 IMPLEMENTED with its owner repository, or to UNIMPLEMENTED with a reason"
            )),
            Some((_, expected)) if expected != port => problems.push(format!(
                "Edge route `{name}` moved to port {port}, the test records {expected}"
            )),
            Some(_) => {}
        }
    }
    let expected = IMPLEMENTED
        .iter()
        .map(|(name, _)| *name)
        .chain(UNIMPLEMENTED.iter().map(|(name, _)| *name));
    for name in expected {
        if !routes.contains_key(name) {
            problems.push(format!(
                "Edge example has no `{ROUTE_PREFIX}{name}{ROUTE_SUFFIX}` line, but the test expects the route"
            ));
        }
    }
    problems
}

/// Whether some non-operator bind in the owner's examples uses the route port.
fn owner_binds_port(owner_examples: &[(String, String)], port: u16) -> bool {
    owner_examples.iter().any(|(_, text)| {
        text.lines().filter_map(bind_of).any(|(key, bound)| {
            bound == port && !key.contains("__ADMIN__") && !key.starts_with(ROUTE_PREFIX)
        })
    })
}

#[test]
fn every_implemented_edge_upstream_is_bound_by_its_owner() {
    let manifest = committed_manifest();
    let platform = require_checkout(&manifest, "platform");
    let edge_path = platform.join("deploy/systemd/edge.conf.example");
    let edge = fs::read_to_string(&edge_path)
        .unwrap_or_else(|error| panic!("cannot read {}: {error}", edge_path.display()));
    let routes = routes_of(&edge);
    assert!(
        !routes.is_empty(),
        "the matcher found no gateway route in {}; it is broken",
        edge_path.display()
    );

    let mut problems = Vec::new();
    for (name, owner) in IMPLEMENTED {
        let Some(port) = routes.get(name) else {
            problems.push(format!("Edge example has no route `{name}`"));
            continue;
        };
        let root = require_checkout(&manifest, owner);
        let examples = example_files(&root)
            .into_iter()
            .map(|file| {
                let text = fs::read_to_string(&file).unwrap_or_default();
                (file.display().to_string(), text)
            })
            .collect::<Vec<_>>();
        if !owner_binds_port(&examples, *port) {
            problems.push(format!(
                "Edge routes `{name}` to 127.0.0.1:{port}, but no deploy example of `{owner}` binds \
                 that port outside its operator (`__ADMIN__`) listener ({} examples read under {})",
                examples.len(),
                root.display()
            ));
        }
    }
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn routes_without_a_service_are_exactly_vault_social_and_ai() {
    let manifest = committed_manifest();
    let platform = require_checkout(&manifest, "platform");
    let edge = fs::read_to_string(platform.join("deploy/systemd/edge.conf.example"))
        .expect("platform ships deploy/systemd/edge.conf.example");
    let problems = classification_problems(&routes_of(&edge));
    assert!(
        problems.is_empty(),
        "{UNIMPLEMENTED_REASON}\n{}",
        problems.join("\n")
    );
}

#[test]
fn a_route_in_neither_group_is_reported() {
    let mut routes = BTreeMap::new();
    for (name, _) in IMPLEMENTED {
        routes.insert(name.to_owned(), 8091);
    }
    for (name, port) in UNIMPLEMENTED {
        routes.insert(name.to_owned(), port);
    }
    assert!(classification_problems(&routes).is_empty());

    routes.insert("BILLING".to_owned(), 8099);
    let problems = classification_problems(&routes);
    assert_eq!(problems.len(), 1, "{problems:?}");
    assert!(
        problems
            .first()
            .is_some_and(|line| line.contains("BILLING")),
        "{problems:?}"
    );

    routes.remove("BILLING");
    routes.insert("VAULT".to_owned(), 8199);
    let problems = classification_problems(&routes);
    assert_eq!(problems.len(), 1, "{problems:?}");
    assert!(
        problems.first().is_some_and(|line| line.contains("VAULT")),
        "{problems:?}"
    );
}

#[test]
fn an_operator_listener_never_satisfies_a_route() {
    let owner = |text: &str| vec![("example".to_owned(), text.to_owned())];
    assert!(owner_binds_port(
        &owner("RATATOSKR__RECEIPT__LISTEN_ADDRESS=127.0.0.1:8096"),
        8096
    ));
    assert!(owner_binds_port(
        &owner("#RATATOSKR__API__LISTEN_ADDRESS=127.0.0.1:8091"),
        8091
    ));
    assert!(!owner_binds_port(
        &owner("RATATOSKR__ADMIN__LISTEN_ADDRESS=127.0.0.1:8096"),
        8096
    ));
    assert!(!owner_binds_port(
        &owner("RATATOSKR__RECEIPT__LISTEN_ADDRESS=127.0.0.1:9085"),
        8096
    ));
    assert!(!owner_binds_port(&owner(""), 8096));
}

#[test]
fn the_route_matcher_ignores_the_digest_listener_and_other_keys() {
    let text = "\
RATATOSKR__GATEWAY__ROUTES__KNOWLEDGE__PREFIX=/v1/k
RATATOSKR__GATEWAY__ROUTES__KNOWLEDGE__LISTENER=127.0.0.1:8091
RATATOSKR__CHANNEL_DIGESTS__LISTENER=127.0.0.1:8098
# RATATOSKR__GATEWAY__ROUTES__VAULT__LISTENER=127.0.0.1:8093
RATATOSKR__ADMIN__BIND=127.0.0.1:9464
";
    let routes = routes_of(text);
    assert_eq!(
        routes,
        BTreeMap::from([("KNOWLEDGE".to_owned(), 8091), ("VAULT".to_owned(), 8093)])
    );
}
