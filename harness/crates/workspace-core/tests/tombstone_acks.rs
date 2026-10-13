//! Tombstone acknowledgement agreement (XR-021 CONTRACTS R5-11, R5-14 rule 6).
//!
//! Every service that may publish a deletion fact, `evt.ai_archive.subject.tombstoned.v1` or `evt.social.source.removed.v1`, re-sends it until Knowledge acknowledges it, and reads the acknowledgement on a durable of its own, `ratatoskr_<service>_deletion_acks`, that Edge provisions. A publisher without that durable would re-send for ever or never learn the outcome; a durable without that right would be a consumer nobody feeds. The two sets must be equal: the identities whose stanza in `deploy/nats/ratatoskr.conf` allows publishing either subject, and the services named by a `*_deletion_acks` row of Edge's table in `crates/eventing/src/stream.rs`.
//!
//! Limitation, stated plainly. This is a text scan of two files. It reads the durable name from the quoted `"ratatoskr_<service>_deletion_acks"` literal in the table, takes `<service>` upper-cased as the identity name (the five names `chatgpt`, `claude`, `x`, `instagram` and `threads` are the identities `CHATGPT`, `CLAUDE`, `X`, `INSTAGRAM` and `THREADS`), and reads publish rights from the allow list of each stanza. It cannot see that a service really consumes its durable or really sets `acknowledged_at` (the services' own broker tests and flow F6 of the native smoke do), and it does not read a wildcard allow such as `evt.>`, which `bus_acl.rs` already forbids for every identity but Edge.
//!
//! Sanity run on the real sample (platform `3275d52`): the table holds the five literals `ratatoskr_chatgpt_deletion_acks`, `ratatoskr_claude_deletion_acks`, `ratatoskr_x_deletion_acks`, `ratatoskr_instagram_deletion_acks` and `ratatoskr_threads_deletion_acks`, and the same five stanzas allow the tombstone or the removal subject; removing one literal from a copy of the table reports exactly that identity.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

#[path = "support/acl.rs"]
mod acl;
#[path = "support/checkout.rs"]
mod checkout;

use acl::{Stanza, allow_list, platform_stanzas};
use checkout::{committed_manifest, require_checkout};
use std::collections::BTreeSet;
use std::fs;

const TABLE: &str = "crates/eventing/src/stream.rs";
const DELETION_SUBJECTS: [&str; 2] = [
    "evt.ai_archive.subject.tombstoned.v1",
    "evt.social.source.removed.v1",
];

/// The identities that own a `ratatoskr_<service>_deletion_acks` row in `table`.
fn identities_with_an_ack_durable(table: &str) -> BTreeSet<String> {
    let mut found = BTreeSet::new();
    for piece in table.split('"').skip(1).step_by(2) {
        if let Some(service) = piece
            .strip_prefix("ratatoskr_")
            .and_then(|rest| rest.strip_suffix("_deletion_acks"))
            && !service.is_empty()
            && service.chars().all(|c| c.is_ascii_lowercase())
        {
            found.insert(service.to_ascii_uppercase());
        }
    }
    found
}

/// The identities whose stanza may publish a deletion fact.
fn deletion_publishers(stanzas: &[Stanza]) -> BTreeSet<String> {
    stanzas
        .iter()
        .filter(|stanza| {
            let allowed = allow_list(&stanza.text, "publish:");
            DELETION_SUBJECTS
                .iter()
                .any(|subject| allowed.iter().any(|entry| entry == subject))
        })
        .map(|stanza| stanza.name.clone())
        .collect()
}

/// Disagreements between the publishers and the durables, one line each.
fn problems(publishers: &BTreeSet<String>, durables: &BTreeSet<String>) -> Vec<String> {
    let mut problems = Vec::new();
    for missing in publishers.difference(durables) {
        problems.push(format!(
            "{missing} may publish a deletion fact but Edge provisions no ratatoskr_{}_deletion_acks durable for it",
            missing.to_ascii_lowercase()
        ));
    }
    for extra in durables.difference(publishers) {
        problems.push(format!(
            "Edge provisions ratatoskr_{}_deletion_acks but the {extra} stanza may publish no deletion fact",
            extra.to_ascii_lowercase()
        ));
    }
    problems
}

fn table_text() -> String {
    let manifest = committed_manifest();
    let platform = require_checkout(&manifest, "platform");
    fs::read_to_string(platform.join(TABLE))
        .unwrap_or_else(|error| panic!("cannot read Platform's {TABLE}: {error}"))
}

#[test]
fn the_services_that_may_publish_a_deletion_fact_are_the_services_with_an_ack_durable() {
    let publishers = deletion_publishers(&platform_stanzas());
    let durables = identities_with_an_ack_durable(&table_text());
    let problems = problems(&publishers, &durables);
    assert!(problems.is_empty(), "{}", problems.join("\n"));
    assert!(
        publishers.len() >= 5,
        "expected the five producers of R5-11, found {publishers:?}"
    );
}

#[test]
fn a_durable_removed_from_a_copy_of_the_table_is_reported() {
    let publishers = deletion_publishers(&platform_stanzas());
    let table = table_text();
    assert!(
        problems(&publishers, &identities_with_an_ack_durable(&table)).is_empty(),
        "the unmodified table must pass before the mutation means anything"
    );

    let mutated = table.replace(
        "\"ratatoskr_threads_deletion_acks\"",
        "\"ratatoskr_threads_deletions\"",
    );
    assert_ne!(mutated, table, "the mutation did not change the table");
    let found = problems(&publishers, &identities_with_an_ack_durable(&mutated));
    assert_eq!(found.len(), 1, "{found:?}");
    assert!(
        found.first().is_some_and(|line| line.contains("THREADS")),
        "{found:?}"
    );
}

#[test]
fn a_publisher_without_a_durable_and_a_durable_without_a_right_are_both_reported() {
    let publishers = BTreeSet::from(["CHATGPT".to_owned(), "X".to_owned()]);
    let durables = BTreeSet::from(["CHATGPT".to_owned(), "CLAUDE".to_owned()]);
    let found = problems(&publishers, &durables);
    assert_eq!(found.len(), 2, "{found:?}");
    assert!(found.iter().any(|line| line.starts_with("X may publish")));
    assert!(
        found
            .iter()
            .any(|line| line.contains("ratatoskr_claude_deletion_acks"))
    );
}

#[test]
fn the_durable_reader_ignores_names_that_only_look_alike() {
    let table = "\"ratatoskr_x_deletion_acks\" \"ratatoskr_knowledge_documents\" \"ratatoskr__deletion_acks\" \"ratatoskr_a_b_deletion_acks\" \"deletion_acks\"";
    assert_eq!(
        identities_with_an_ack_durable(table),
        BTreeSet::from(["X".to_owned()])
    );
}
