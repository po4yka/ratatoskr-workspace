//! Bus ACL equality: `ratatoskr-platform/deploy/nats/ratatoskr.conf` is the only deployed NATS
//! authorization file, every service that carries a copy of its own stanza must carry an equal
//! one, and the stanzas must keep the least-privilege invariants of the XR-021 bus topology.
//!
//! XR-021 round 3 (R3-01) added the reply namespace: every non-Edge stanza may subscribe only to its
//! own `_INBOX_<name>.>` prefix, Edge keeps `_INBOX.>`, the owning repository must hand the prefix to
//! `custom_inbox_prefix(` in non-test source (the wiring scan lives in `support/inbox_wiring.rs`,
//! with its limitation stated there), and twelve vendored copies, one per non-Edge identity, must
//! equal their stanza.
//!
//! XR-021 round 5 (R5-11, R5-12) moved the table to 23 service durables and added three publish
//! rights: KNOWLEDGE publishes `evt.knowledge.deletion.acknowledged.v1`, CHATGPT and CLAUDE publish
//! `cmd.platform.stream_erasure.requested.v1`, and nobody else may publish any of the three
//! (`the_deletion_publish_rights_belong_to_exactly_their_stanzas`). Invariant 7: no stanza but EDGE
//! may publish a `$JS.API.STREAM.` subject, because stream erasure is Edge's alone. Sanity run on
//! the real sample (`platform` at `3275d52`, `deploy/nats/ratatoskr.conf`): the literal rule
//! "starts with `$JS.API.STREAM.`" also catches
//! `$JS.API.STREAM.INFO.KV_browser_worker_completions` in the `EXTRACTOR_BROWSER_WORKER` stanza,
//! which opens its own completion bucket and mutates nothing, so the check allows exactly the
//! stream-info subjects of a `KV_` bucket and nothing else under that prefix.
//!
//! The splitter is plain text on purpose. The comparison is on what a reviewer read (comments,
//! whitespace and the nkey token ignored), so it must not depend on a NATS parser's idea of
//! meaning. A stanza is a brace block that opens at the start of a file or right after `[` or
//! `,`; `jetstream {`, `authorization {` and `permissions: {` open after a word or a colon.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

#[path = "support/acl.rs"]
mod acl;
#[path = "support/checkout.rs"]
mod checkout;
#[path = "support/inbox_wiring.rs"]
mod inbox_wiring;

use acl::{Stanza, allow_list, platform_stanzas, stanzas};
use checkout::{committed_manifest, require_checkout};
use inbox_wiring::{Sources, inbox_wiring_problem, sources_of};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;

const IDENTITIES: [&str; 15] = [
    "EDGE",
    "TELEGRAM",
    "CHATGPT",
    "CLAUDE",
    "X",
    "INSTAGRAM",
    "THREADS",
    "EXTRACTOR",
    "EXTRACTOR_BROWSER_WORKER",
    "KNOWLEDGE",
    "GITHUB",
    "VAULT",
    "CHANNEL_DIGESTS",
    "NOTES",
    "SITES",
];

/// The repository that owns each identity: it publishes or consumes with it.
const OWNERS: [(&str, &str); 15] = [
    ("EDGE", "platform"),
    ("TELEGRAM", "telegram"),
    ("CHATGPT", "chatgpt"),
    ("CLAUDE", "claude"),
    ("X", "x"),
    ("INSTAGRAM", "instagram"),
    ("THREADS", "threads"),
    ("EXTRACTOR", "extractor"),
    ("EXTRACTOR_BROWSER_WORKER", "extractor"),
    ("KNOWLEDGE", "knowledge"),
    ("GITHUB", "github"),
    ("VAULT", "vault"),
    ("CHANNEL_DIGESTS", "channel-digests"),
    ("NOTES", "notes"),
    ("SITES", "sites"),
];

/// `(repository, path of the copy, identity)`: one vendored copy for every non-Edge identity
/// (R3-01 gave the six services that had none a `deploy/nats/identity.conf` as well).
const FRAGMENTS: [(&str, &str, &str); 14] = [
    ("telegram", "deploy/nats/identity.conf", "TELEGRAM"),
    ("chatgpt", "deploy/nats/identity.conf", "CHATGPT"),
    ("claude", "deploy/nats/identity.conf", "CLAUDE"),
    ("x", "deploy/nats/identity.conf", "X"),
    ("instagram", "deploy/nats/identity.conf", "INSTAGRAM"),
    ("threads", "deploy/nats/identity.conf", "THREADS"),
    ("extractor", "deploy/nats/identity.conf", "EXTRACTOR"),
    (
        "extractor",
        "deploy/nats/identity-browser-worker.conf",
        "EXTRACTOR_BROWSER_WORKER",
    ),
    ("knowledge", "deploy/nats/identity.conf", "KNOWLEDGE"),
    (
        "channel-digests",
        "deploy/nats/identity.conf",
        "CHANNEL_DIGESTS",
    ),
    ("github", "deploy/nats/identity.conf", "GITHUB"),
    ("vault", "deploy/nats/identity.conf", "VAULT"),
    ("notes", "deploy/nats/identity.conf", "NOTES"),
    ("sites", "deploy/nats/identity.conf", "SITES"),
];

/// R3-01: the one reply namespace each non-Edge identity may subscribe to. EDGE keeps `_INBOX.>`.
/// `_INBOX_x.>` does not match `_INBOX.>` because NATS compares whole tokens.
const INBOX_PREFIXES: [(&str, &str); 14] = [
    ("TELEGRAM", "_INBOX_telegram"),
    ("CHATGPT", "_INBOX_chatgpt"),
    ("CLAUDE", "_INBOX_claude"),
    ("X", "_INBOX_x"),
    ("INSTAGRAM", "_INBOX_instagram"),
    ("THREADS", "_INBOX_threads"),
    ("EXTRACTOR", "_INBOX_extractor"),
    (
        "EXTRACTOR_BROWSER_WORKER",
        "_INBOX_extractor_browser_worker",
    ),
    ("KNOWLEDGE", "_INBOX_knowledge"),
    ("GITHUB", "_INBOX_github"),
    ("VAULT", "_INBOX_vault"),
    ("CHANNEL_DIGESTS", "_INBOX_channel_digests"),
    ("NOTES", "_INBOX_notes"),
    ("SITES", "_INBOX_sites"),
];

const COMMANDS: &str = "ratatoskr_commands";
const EVENTS: &str = "ratatoskr_events";

/// `(stream, durable, owning identity)`: the ACL owner column of the fixed-durable table.
const DURABLE_OWNERS: [(&str, &str, &str); 34] = [
    (EVENTS, "ratatoskr_telegram_notifications", "TELEGRAM"),
    (COMMANDS, "ratatoskr_x_browser_capture", "X"),
    (COMMANDS, "ratatoskr_instagram_browser_capture", "INSTAGRAM"),
    (COMMANDS, "threads_browser_capture", "THREADS"),
    (COMMANDS, "ratatoskr_extractor_capture", "EXTRACTOR"),
    (
        COMMANDS,
        "ratatoskr_browser_worker",
        "EXTRACTOR_BROWSER_WORKER",
    ),
    (COMMANDS, "ratatoskr_knowledge_channel_recap", "KNOWLEDGE"),
    (
        COMMANDS,
        "ratatoskr_channel_digest_subscriptions",
        "CHANNEL_DIGESTS",
    ),
    (COMMANDS, "ratatoskr_channel_digest_runs", "CHANNEL_DIGESTS"),
    (
        COMMANDS,
        "ratatoskr_channel_digest_schedule_occurrences",
        "CHANNEL_DIGESTS",
    ),
    (COMMANDS, "ratatoskr_vault_backup_policy", "VAULT"),
    (EVENTS, "ratatoskr_knowledge_documents", "KNOWLEDGE"),
    (EVENTS, "ratatoskr_knowledge_social_sources", "KNOWLEDGE"),
    (EVENTS, "ratatoskr_knowledge_ai_archive", "KNOWLEDGE"),
    (
        EVENTS,
        "ratatoskr_knowledge_repository_requests",
        "KNOWLEDGE",
    ),
    (EVENTS, "ratatoskr_github_analysis_completed", "GITHUB"),
    (EVENTS, "ratatoskr_github_analysis_failed", "GITHUB"),
    (EVENTS, "ratatoskr_github_policy_acknowledged", "GITHUB"),
    (EVENTS, "ratatoskr_x_extractor_reports", "X"),
    (
        EVENTS,
        "ratatoskr_channel_digest_recap_completed",
        "CHANNEL_DIGESTS",
    ),
    (
        EVENTS,
        "ratatoskr_channel_digest_recap_failed",
        "CHANNEL_DIGESTS",
    ),
    (EVENTS, "ratatoskr_extractor_render_awaits", "EXTRACTOR"),
    (EVENTS, "ratatoskr_chatgpt_deletion_acks", "CHATGPT"),
    (EVENTS, "ratatoskr_claude_deletion_acks", "CLAUDE"),
    (EVENTS, "ratatoskr_x_deletion_acks", "X"),
    (EVENTS, "ratatoskr_instagram_deletion_acks", "INSTAGRAM"),
    (EVENTS, "ratatoskr_threads_deletion_acks", "THREADS"),
    (EVENTS, "ratatoskr_knowledge_notes_files", "KNOWLEDGE"),
    (EVENTS, "ratatoskr_knowledge_notes_vaults", "KNOWLEDGE"),
    (COMMANDS, "ratatoskr_notes_write_requests", "NOTES"),
    (COMMANDS, "ratatoskr_sites_release_builds", "SITES"),
    (EVENTS, "ratatoskr_sites_note_changes", "SITES"),
    (EVENTS, "ratatoskr_sites_vault_disconnections", "SITES"),
    (EVENTS, "ratatoskr_sites_approvals", "SITES"),
];

/// R5-11 and R5-12: `(subject, identities that may publish it)`. The set must match exactly.
const PUBLISH_RIGHTS: [(&str, &[&str]); 3] = [
    ("evt.knowledge.deletion.acknowledged.v1", &["KNOWLEDGE"]),
    (
        "cmd.platform.stream_erasure.requested.v1",
        &["CHATGPT", "CLAUDE"],
    ),
    (
        "evt.ai_archive.subject.tombstoned.v1",
        &["CHATGPT", "CLAUDE"],
    ),
];

/// Subjects (or prefixes) no identity other than EDGE may be able to publish.
const FORBIDDEN_EXACT: [&str; 3] = ["$JS.API.>", "evt.>", "cmd.>"];
const FORBIDDEN_PREFIXES: [&str; 4] = [
    "$JS.API.CONSUMER.CREATE",
    "$JS.API.CONSUMER.DURABLE.CREATE",
    "$JS.API.STREAM.CREATE",
    "$JS.API.STREAM.UPDATE",
];
/// Invariant 7 (R5-12): the one subject under `$JS.API.STREAM.` a non-Edge stanza may publish is the
/// read-only info of a KV bucket's stream, which a client needs to open the bucket.
const STREAM_API_PREFIX: &str = "$JS.API.STREAM.";
const FORBIDDEN_FRAGMENTS: [&str; 2] = ["STREAM.MSG.GET.ratatoskr_", "DIRECT.GET.ratatoskr_"];

fn owner_of(identity: &str) -> &'static str {
    let Some((_, owner)) = OWNERS.iter().find(|(name, _)| *name == identity) else {
        panic!("identity `{identity}` has no owner repository");
    };
    owner
}

/// `$JS.API.STREAM.INFO.KV_<bucket>` and nothing else under the stream API prefix.
fn is_kv_stream_info(subject: &str) -> bool {
    subject
        .strip_prefix("$JS.API.STREAM.INFO.KV_")
        .is_some_and(|bucket| {
            !bucket.is_empty()
                && bucket
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '_')
        })
}

fn is_allowed_wildcard(subject: &str) -> bool {
    if !subject.contains('>') && !subject.contains('*') {
        return true;
    }
    if subject.contains('*') {
        return false;
    }
    let segments = subject.split('.').collect::<Vec<_>>();
    let wildcard_is_last = segments.last() == Some(&">")
        && segments
            .iter()
            .take(segments.len().saturating_sub(1))
            .all(|segment| !segment.contains('>'));
    if !wildcard_is_last {
        return false;
    }
    let is_ack =
        segments.len() == 5 && segments.first() == Some(&"$JS") && segments.get(1) == Some(&"ACK");
    let is_kv_direct_get = segments.len() == 6
        && segments.first() == Some(&"$JS")
        && segments.get(1) == Some(&"API")
        && segments.get(2) == Some(&"DIRECT")
        && segments.get(3) == Some(&"GET")
        && segments
            .get(4)
            .is_some_and(|bucket| bucket.starts_with("KV_"));
    let is_kv_subject = segments.len() == 3 && segments.first() == Some(&"$KV");
    is_ack || is_kv_direct_get || is_kv_subject
}

#[test]
fn platform_conf_has_exactly_the_fifteen_identities() {
    let manifest = committed_manifest();
    let found = platform_stanzas();
    let names = found
        .iter()
        .map(|stanza| stanza.name.clone())
        .collect::<Vec<_>>();
    let unique = names.iter().cloned().collect::<BTreeSet<_>>();
    let placeholders = found
        .iter()
        .map(|stanza| stanza.placeholder.clone())
        .collect::<BTreeSet<_>>();

    assert_eq!(
        names.len(),
        unique.len(),
        "an identity appears twice in ratatoskr.conf: {names:?}"
    );
    assert_eq!(
        placeholders.len(),
        found.len(),
        "two identities share one nkey placeholder"
    );
    assert_eq!(
        unique,
        IDENTITIES
            .iter()
            .map(|name| (*name).to_owned())
            .collect::<BTreeSet<_>>(),
        "ratatoskr.conf must hold exactly the fifteen identities of the bus topology"
    );
    for identity in IDENTITIES {
        require_checkout(&manifest, owner_of(identity));
    }
}

#[test]
fn every_service_fragment_equals_its_platform_stanza() {
    let manifest = committed_manifest();
    let platform = platform_stanzas()
        .into_iter()
        .map(|stanza| (stanza.name.clone(), stanza))
        .collect::<BTreeMap<_, _>>();
    let mut problems = Vec::new();

    for (repository, relative, identity) in FRAGMENTS {
        let root = require_checkout(&manifest, repository);
        let path = root.join(relative);
        let Ok(source) = fs::read_to_string(&path) else {
            problems.push(format!("{repository}: {relative} is missing"));
            continue;
        };
        let copies = stanzas(&source);
        let [copy] = copies.as_slice() else {
            problems.push(format!(
                "{repository}: {relative} holds {} stanzas, expected exactly one",
                copies.len()
            ));
            continue;
        };
        if copy.name != identity {
            problems.push(format!(
                "{repository}: {relative} is the `{}` identity, expected `{identity}`",
                copy.name
            ));
            continue;
        }
        let Some(reviewed) = platform.get(identity) else {
            problems.push(format!("ratatoskr.conf has no `{identity}` stanza"));
            continue;
        };
        if copy.normalized() != reviewed.normalized() {
            problems.push(format!(
                "{repository}: {relative} differs from the `{identity}` stanza of ratatoskr.conf"
            ));
        }
    }

    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn extractor_permissions_conf_is_gone() {
    let manifest = committed_manifest();
    let root = require_checkout(&manifest, "extractor");
    let old = root.join("deploy/nats/extractor-permissions.conf");

    assert!(
        !old.exists(),
        "{} still exists; the extractor's narrow stanza replaced it",
        old.display()
    );
}

#[test]
fn non_edge_stanzas_obey_the_permission_invariants() {
    let found = platform_stanzas();
    let mut problems = Vec::new();
    let mut holders = BTreeMap::<(String, String, String), BTreeSet<String>>::new();

    for stanza in found.iter().filter(|stanza| stanza.name != "EDGE") {
        if stanza.text.contains("deny:") {
            problems.push(format!("{} has a deny block", stanza.name));
        }
        for subject in allow_list(&stanza.text, "publish:") {
            if FORBIDDEN_EXACT.contains(&subject.as_str())
                || FORBIDDEN_PREFIXES
                    .iter()
                    .any(|prefix| subject.starts_with(prefix))
                || FORBIDDEN_FRAGMENTS
                    .iter()
                    .any(|fragment| subject.contains(fragment))
            {
                problems.push(format!("{} may publish `{subject}`", stanza.name));
            }
            if subject.starts_with(STREAM_API_PREFIX) && !is_kv_stream_info(&subject) {
                problems.push(format!(
                    "{} may publish `{subject}`, a stream API subject only EDGE may hold (invariant 7)",
                    stanza.name
                ));
            }
            if !is_allowed_wildcard(&subject) {
                problems.push(format!(
                    "{} holds the wildcard `{subject}`, which is not an ack, KV direct-get or KV subject",
                    stanza.name
                ));
            }
            for (kind, prefix) in [
                ("info", "$JS.API.CONSUMER.INFO."),
                ("next", "$JS.API.CONSUMER.MSG.NEXT."),
                ("ack", "$JS.ACK."),
            ] {
                let Some(rest) = subject.strip_prefix(prefix) else {
                    continue;
                };
                let rest = rest.trim_end_matches(".>");
                if let Some((stream, durable)) = rest.split_once('.') {
                    holders
                        .entry((kind.to_owned(), stream.to_owned(), durable.to_owned()))
                        .or_default()
                        .insert(stanza.name.clone());
                }
            }
        }
    }

    for ((kind, stream, durable), owners) in &holders {
        if owners.len() != 1 {
            problems.push(format!(
                "the {kind} permission of durable `{durable}` on `{stream}` is held by {owners:?}, expected exactly one stanza"
            ));
        }
    }
    for (stream, durable, owner) in DURABLE_OWNERS {
        let info = holders.get(&("info".to_owned(), stream.to_owned(), durable.to_owned()));
        if info.is_none_or(|owners| !owners.contains(owner)) {
            problems.push(format!(
                "durable `{durable}` on `{stream}` has no consumer-info permission in the `{owner}` stanza"
            ));
        }
    }
    let edge = found.iter().find(|stanza| stanza.name == "EDGE");
    match edge {
        Some(edge) => {
            let publish = allow_list(&edge.text, "publish:");
            if publish
                != [
                    "cmd.>",
                    "evt.platform.site_approval.changed.v1",
                    "$JS.API.>",
                    "$JS.ACK.>",
                ]
            {
                problems.push(format!("EDGE publish allow is {publish:?}"));
            }
        }
        None => problems.push("ratatoskr.conf has no EDGE stanza".to_owned()),
    }

    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

/// The identities whose stanza allows publishing exactly `subject`.
fn publishers_of(found: &[Stanza], subject: &str) -> BTreeSet<String> {
    found
        .iter()
        .filter(|stanza| {
            allow_list(&stanza.text, "publish:")
                .iter()
                .any(|allowed| allowed == subject)
        })
        .map(|stanza| stanza.name.clone())
        .collect()
}

#[test]
fn the_deletion_publish_rights_belong_to_exactly_their_stanzas() {
    let found = platform_stanzas();
    let mut problems = Vec::new();
    for (subject, expected) in PUBLISH_RIGHTS {
        let actual = publishers_of(&found, subject);
        let wanted = expected
            .iter()
            .map(|name| (*name).to_owned())
            .collect::<BTreeSet<_>>();
        if actual != wanted {
            problems.push(format!(
                "`{subject}` may be published by {actual:?}, expected exactly {wanted:?}"
            ));
        }
    }
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

/// SITE-025 (`fleet-bus-topology`): the SITES stanza consumes its four durables, publishes its two
/// event subjects, and no command; only EDGE publishes the release build command.
#[test]
fn sites_stanza_allows_its_durables_and_events() {
    let found = platform_stanzas();
    let Some(sites) = found.iter().find(|stanza| stanza.name == "SITES") else {
        panic!("ratatoskr.conf has no SITES stanza");
    };
    let publish = allow_list(&sites.text, "publish:");
    let mut problems = Vec::new();
    for (stream, durable, _) in DURABLE_OWNERS
        .iter()
        .filter(|(_, _, owner)| *owner == "SITES")
    {
        for wanted in [
            format!("$JS.API.CONSUMER.INFO.{stream}.{durable}"),
            format!("$JS.API.CONSUMER.MSG.NEXT.{stream}.{durable}"),
            format!("$JS.ACK.{stream}.{durable}.>"),
        ] {
            if !publish.contains(&wanted) {
                problems.push(format!("SITES does not allow `{wanted}`"));
            }
        }
    }
    for event in [
        "evt.sites.release.published.v1",
        "evt.platform.operation.reported.v1",
    ] {
        if !publish.iter().any(|allowed| allowed == event) {
            problems.push(format!("SITES does not allow `{event}`"));
        }
    }
    for subject in publish.iter().filter(|subject| subject.starts_with("cmd.")) {
        problems.push(format!("SITES may publish the command `{subject}`"));
    }
    let command = "cmd.sites.release.build_requested.v1";
    let named = publishers_of(&found, command);
    if !named.is_empty() {
        problems.push(format!(
            "`{command}` is named by {named:?}; only EDGE publishes it, through `cmd.>`"
        ));
    }
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn no_stanza_but_edge_publishes_under_the_stream_api_except_a_kv_info() {
    let found = platform_stanzas();
    let mut offenders = Vec::new();
    for stanza in found.iter().filter(|stanza| stanza.name != "EDGE") {
        for subject in allow_list(&stanza.text, "publish:") {
            if subject.starts_with(STREAM_API_PREFIX) && !is_kv_stream_info(&subject) {
                offenders.push(format!("{} may publish `{subject}`", stanza.name));
            }
        }
    }
    assert!(offenders.is_empty(), "{}", offenders.join("\n"));
    assert!(
        found.iter().any(|stanza| stanza.name == "EDGE"
            && allow_list(&stanza.text, "publish:")
                .iter()
                .any(|allowed| allowed == "$JS.API.>")),
        "EDGE must keep `$JS.API.>`, the one grant that reaches STREAM.MSG.DELETE"
    );
}

#[test]
fn the_stream_api_rule_reports_a_message_delete_and_allows_a_kv_info() {
    assert!(is_kv_stream_info(
        "$JS.API.STREAM.INFO.KV_browser_worker_completions"
    ));
    assert!(!is_kv_stream_info("$JS.API.STREAM.INFO.ratatoskr_events"));
    assert!(!is_kv_stream_info(
        "$JS.API.STREAM.MSG.DELETE.ratatoskr_events"
    ));
    assert!(!is_kv_stream_info("$JS.API.STREAM.INFO.KV_"));

    let mutated = r#"{ nkey: UREPLACE_ME_WITH_THE_PUBLIC_NKEY_OF_RATATOSKR_CHATGPT_XXXXXX
        permissions: { publish: { allow: ["$JS.API.STREAM.MSG.DELETE.ratatoskr_events", "evt.ai_archive.subject.tombstoned.v1"] } } }"#;
    let parsed = stanzas(mutated);
    let [chatgpt] = parsed.as_slice() else {
        panic!("one stanza expected");
    };
    let offenders = allow_list(&chatgpt.text, "publish:")
        .into_iter()
        .filter(|subject| subject.starts_with(STREAM_API_PREFIX) && !is_kv_stream_info(subject))
        .collect::<Vec<_>>();
    assert_eq!(offenders, ["$JS.API.STREAM.MSG.DELETE.ratatoskr_events"]);
    assert_eq!(
        publishers_of(&parsed, "evt.ai_archive.subject.tombstoned.v1"),
        BTreeSet::from(["CHATGPT".to_owned()])
    );
}

fn inbox_prefix_of(identity: &str) -> &'static str {
    let Some((_, prefix)) = INBOX_PREFIXES.iter().find(|(name, _)| *name == identity) else {
        panic!("identity `{identity}` has no inbox prefix row");
    };
    prefix
}

#[test]
fn every_non_edge_stanza_subscribes_only_to_its_own_inbox_prefix() {
    let found = platform_stanzas();
    let mut problems = Vec::new();

    for (identity, prefix) in INBOX_PREFIXES {
        if !IDENTITIES.contains(&identity) {
            problems.push(format!(
                "the prefix table names unknown identity `{identity}`"
            ));
        }
        let expected = format!("{prefix}.>");
        match found.iter().find(|stanza| stanza.name == identity) {
            None => problems.push(format!("ratatoskr.conf has no `{identity}` stanza")),
            Some(stanza) => {
                let subscribe = allow_list(&stanza.text, "subscribe:");
                if subscribe != [expected.as_str()] {
                    problems.push(format!(
                        "{identity} subscribes to {subscribe:?}, expected only `{expected}`"
                    ));
                }
            }
        }
    }
    for identity in IDENTITIES.iter().filter(|name| **name != "EDGE") {
        if !INBOX_PREFIXES.iter().any(|(name, _)| name == identity) {
            problems.push(format!("`{identity}` has no row in the prefix table"));
        }
    }
    match found.iter().find(|stanza| stanza.name == "EDGE") {
        None => problems.push("ratatoskr.conf has no EDGE stanza".to_owned()),
        Some(edge) => {
            let subscribe = allow_list(&edge.text, "subscribe:");
            if subscribe != ["_INBOX.>"] {
                problems.push(format!(
                    "EDGE subscribes to {subscribe:?}, expected only `_INBOX.>`"
                ));
            }
        }
    }

    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn every_identity_has_a_vendored_copy() {
    let manifest = committed_manifest();
    let covered = FRAGMENTS
        .iter()
        .map(|(_, _, identity)| *identity)
        .collect::<BTreeSet<_>>();
    let wanted = IDENTITIES
        .iter()
        .copied()
        .filter(|name| *name != "EDGE")
        .collect::<BTreeSet<_>>();
    let mut problems = Vec::new();

    for missing in wanted.difference(&covered) {
        problems.push(format!("no vendored copy is listed for `{missing}`"));
    }
    for (repository, relative, identity) in FRAGMENTS {
        let owner = owner_of(identity);
        if owner != repository {
            problems.push(format!(
                "the copy of `{identity}` is listed in `{repository}`, its owner is `{owner}`"
            ));
        }
        let path = require_checkout(&manifest, repository).join(relative);
        if !path.is_file() {
            problems.push(format!("{repository}: {relative} is missing"));
        }
    }

    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn the_owner_repository_uses_the_prefix_literal() {
    let mut problems = Vec::new();
    let mut by_owner = BTreeMap::<&str, Sources>::new();
    for (identity, prefix) in INBOX_PREFIXES {
        let owner = owner_of(identity);
        let sources = by_owner.entry(owner).or_insert_with(|| sources_of(owner));
        if let Some(problem) = inbox_wiring_problem(sources, prefix) {
            problems.push(format!("{owner} ({identity}): {problem}"));
        }
    }
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn the_wiring_scan_reports_a_changed_literal_and_a_dropped_call() {
    let sources = sources_of("knowledge");
    let prefix = inbox_prefix_of("KNOWLEDGE");
    assert!(
        inbox_wiring_problem(&sources, prefix).is_none(),
        "the unmodified source must pass before a mutation means anything"
    );

    let mutate = |from: &str, to: &str| Sources {
        rust: sources
            .rust
            .iter()
            .map(|(path, text)| (path.clone(), text.replace(from, to)))
            .collect(),
        crate_dirs: sources.crate_dirs.clone(),
    };
    let changed = mutate(&format!("\"{prefix}\""), &format!("\"{prefix}_other\""));
    assert!(
        inbox_wiring_problem(&changed, prefix).is_some(),
        "a changed literal must be reported"
    );
    let dropped = mutate("custom_inbox_prefix(", "custom_inbox_prefx(");
    assert!(
        inbox_wiring_problem(&dropped, prefix).is_some(),
        "a dropped call must be reported"
    );
}

#[test]
fn the_wiring_scan_reads_both_wirings_and_ignores_tests() {
    let crate_dirs = vec!["crates/a/".to_owned()];
    let constant = Sources {
        rust: vec![(
            "crates/a/src/bus.rs".to_owned(),
            "const INBOX_PREFIX: &str = \"_INBOX_a\";\nfn f() { o.custom_inbox_prefix(INBOX_PREFIX) }"
                .to_owned(),
        )],
        crate_dirs: crate_dirs.clone(),
    };
    assert!(inbox_wiring_problem(&constant, "_INBOX_a").is_none());
    assert!(inbox_wiring_problem(&constant, "_INBOX_b").is_some());

    let literal = Sources {
        rust: vec![(
            "crates/a/src/bus.rs".to_owned(),
            "fn f() { o.custom_inbox_prefix(\"_INBOX_a\") }".to_owned(),
        )],
        crate_dirs: crate_dirs.clone(),
    };
    assert!(inbox_wiring_problem(&literal, "_INBOX_a").is_none());

    let only_a_test = Sources {
        rust: vec![(
            "crates/a/tests/bus.rs".to_owned(),
            "const P: &str = \"_INBOX_a\"; fn f() { o.custom_inbox_prefix(P) }".to_owned(),
        )],
        crate_dirs: crate_dirs.clone(),
    };
    assert!(inbox_wiring_problem(&only_a_test, "_INBOX_a").is_some());

    let other_crate = Sources {
        rust: vec![
            (
                "crates/a/src/topology.rs".to_owned(),
                "pub const INBOX_PREFIX: &str = \"_INBOX_a\";".to_owned(),
            ),
            (
                "crates/b/src/lib.rs".to_owned(),
                "fn f() { o.custom_inbox_prefix(INBOX_PREFIX) }".to_owned(),
            ),
        ],
        crate_dirs: vec!["crates/a/".to_owned(), "crates/b/".to_owned()],
    };
    assert!(
        inbox_wiring_problem(&other_crate, "_INBOX_a").is_some(),
        "a call in another crate must not satisfy the declaring crate"
    );
}

const FIXTURE_STANZA: &str = r#"
# comment with "quotes" and { braces
{
    nkey: UREPLACE_ME_WITH_THE_PUBLIC_NKEY_OF_RATATOSKR_VAULT_XXXXXXXX
    permissions: {
        publish: { allow: ["evt.vault.backup_policy.acknowledged.v1"] }
        subscribe: { allow: ["_INBOX_vault.>"] }
    }
}
"#;

#[test]
fn comparison_ignores_comments_whitespace_and_the_nkey_token() {
    let reformatted = FIXTURE_STANZA
        .replace('\n', " ")
        .replace("# comment with \"quotes\" and { braces", "")
        .replace("XXXXXXXX", "XXXX");
    let other = stanzas(&reformatted);
    let original = stanzas(FIXTURE_STANZA);

    assert_eq!(original.len(), 1);
    assert_eq!(
        original.first().map(|stanza| stanza.name.as_str()),
        Some("VAULT")
    );
    assert_eq!(other.len(), 1);
    assert_eq!(
        original.first().map(Stanza::normalized),
        other.first().map(Stanza::normalized)
    );
}

#[test]
fn comparison_detects_a_changed_subject() {
    let widened = FIXTURE_STANZA.replace("acknowledged.v1", "acknowledged.v2");
    let original = stanzas(FIXTURE_STANZA);
    let changed = stanzas(&widened);

    assert_ne!(
        original.first().map(Stanza::normalized),
        changed.first().map(Stanza::normalized)
    );
}

#[test]
fn wildcard_rule_accepts_only_ack_kv_direct_get_and_kv_subjects() {
    for allowed in [
        "evt.vault.backup_policy.acknowledged.v1",
        "$JS.ACK.ratatoskr_commands.ratatoskr_vault_backup_policy.>",
        "$JS.API.DIRECT.GET.KV_browser_worker_completions.>",
        "$KV.browser_worker_completions.>",
    ] {
        assert!(is_allowed_wildcard(allowed), "{allowed} should be allowed");
    }
    for refused in ["evt.>", "cmd.>", "$JS.API.>", "$JS.ACK.>", "evt.*.v1"] {
        assert!(!is_allowed_wildcard(refused), "{refused} should be refused");
    }
}
